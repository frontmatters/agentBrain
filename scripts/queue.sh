#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# queue.sh — markdown-native work queue + dispatch for agentBrain.
# Items are `type: task` notes under local/queue/<scope>/<slug>.md.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMIT_BIN="${QUEUE_EMIT_BIN:-$ROOT_DIR/system/addons/event-bus/bin/brain-emit}"
POLL_BIN="${QUEUE_POLL_BIN:-$ROOT_DIR/system/addons/event-bus/bin/brain-poll}"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-60; }

# locate a task note by its id (uuid5). Prints relative path or exits 1.
find_by_id() {
  local id="$1" f
  f="$(grep -rl "^id: ${id}$" "$ROOT_DIR/vault/queue" --include='*.md' 2>/dev/null | head -1 || true)"
  [ -n "$f" ] || { echo "queue: no item with id $id" >&2; return 1; }
  printf '%s' "${f#"$ROOT_DIR"/}"
}

# set a frontmatter field (key: value) in-place; adds it before the id line if missing.
set_field() {
  local file="$1" key="$2" val="$3" esc
  esc="$(printf '%s' "$val" | sed 's/[\\&|]/\\&/g')"
  if grep -q "^${key}:" "$file"; then
    sed -i.bak "s|^${key}:.*|${key}: ${esc}|" "$file" && rm -f "${file}.bak"
  else
    sed -i.bak "1,/^---$/{/^id: /i\\
${key}: ${val}
}" "$file" && rm -f "${file}.bak"
  fi
}
get_field() { sed -n "s|^$2: *||p" "$1" | head -1; }

cmd_add() {
  local title="$1"; shift
  [ -n "$title" ] || { echo "queue: title must not be empty" >&2; return 1; }
  local scope=inbox prio=P2 verify="" blocked_by=""
  while [ $# -gt 0 ]; do case "$1" in
    --scope) scope="$(slugify "$2")"; shift 2;;
    --prio)  prio="$2"; shift 2;;
    --verify) verify="$2"; shift 2;;
    --blocked-by) blocked_by="$2"; shift 2;;
    *) shift;;
  esac; done
  local slug rel out t; slug="$(slugify "$title")"; t="$(now)"
  [ -n "$slug" ] || { echo "queue: title produces empty slug: '$title'" >&2; return 1; }
  rel="vault/queue/${scope}/${slug}"
  out="$(cd "$ROOT_DIR" && bash scripts/new-note.sh task "$rel" "$title")"
  local f="$out"; [ -f "$f" ] || f="$ROOT_DIR/${out#"$ROOT_DIR"/}"
  set_field "$f" scope "$scope"
  set_field "$f" priority "$prio"
  set_field "$f" agent local
  set_field "$f" dispatch none
  set_field "$f" created "$t"
  set_field "$f" updated "$t"
  set_field "$f" completed ""
  [ -n "$verify" ] && set_field "$f" verify "$verify"
  [ -n "$blocked_by" ] && block_on "$f" "$blocked_by"
  printf '%s\n' "${f#"$ROOT_DIR"/}"
}

# --- blockers -------------------------------------------------------------
# Only the `blocked_by:` field (comma-separated ids) blocks a task; a
# "blocked by X" line in the body does nothing. A task wakes (-> pending) once
# every listed blocker is `done`. A cancelled blocker keeps it blocked: that
# is a call for a human, not for the queue.
all_blockers_done() {
  local f="$1" b rel
  for b in $(get_field "$f" blocked_by | tr ',' ' '); do
    rel="$(find_by_id "$b" 2>/dev/null)" || return 1
    [ "$(get_field "$ROOT_DIR/$rel" status)" = "done" ] || return 1
  done
}
block_on() {  # $1=file $2=comma-separated blocker ids
  local f="$1" b
  for b in $(printf '%s' "$2" | tr ',' ' '); do
    find_by_id "$b" >/dev/null || return 1
  done
  set_field "$f" blocked_by "$2"
  all_blockers_done "$f" || set_field "$f" status blocked
  set_field "$f" updated "$(now)"
}
cmd_block() {  # $1=id $2=comma-separated blocker ids
  local id="$1" rel; rel="$(find_by_id "$id")" || return 1
  [ -n "${2:-}" ] || { echo "queue: block <id> <blocker-id>[,<id>...]" >&2; return 1; }
  block_on "$ROOT_DIR/$rel" "$2"
}
wake_dependents() {  # $1=id that just reached done
  local id="$1" f
  grep -rl "^blocked_by:.*${id}" "$ROOT_DIR/vault/queue" --include='*.md' 2>/dev/null | while IFS= read -r f; do
    [ "$(get_field "$f" status)" = blocked ] || continue
    if all_blockers_done "$f"; then
      set_field "$f" status pending; set_field "$f" updated "$(now)"
    fi
  done || true
}

# --- verification ---------------------------------------------------------
# `verify:` holds a shell command that proves the task is done (run from the
# caller's cwd). `done` runs it; a task without `verify:` completes as before.
# A failing proof refuses `done`. QUEUE_FORCE=1 overrides, but the note then
# says `verify_overridden:` instead of `verified:`, so "done" never claims a
# proof that did not hold. Exit 126/127 come from the shell itself: the proof
# could not run, which is a different message from "the claim is false".
on_verify_fail() {  # $1=file $2=exit code of the verify command
  local verify; verify="$(get_field "$1" verify)"
  if [ "${QUEUE_FORCE:-}" = 1 ]; then
    set_field "$1" verify_overridden "$(now) exit $2"
    echo "queue: verify failed (exit $2), done by override: $verify" >&2
    return 0
  fi
  case "$2" in
    126|127) echo "queue: verify command could not run (exit $2), fix it: $verify" >&2 ;;
    *)       echo "queue: verify failed (exit $2), not done: $verify" >&2 ;;
  esac
  echo "queue: QUEUE_FORCE=1 marks it done anyway, recorded as verify_overridden" >&2
  return 1
}

cmd_start() {
  local id="$1" rel f scope; rel="$(find_by_id "$id")" || return 1
  f="$ROOT_DIR/$rel"; scope="$(get_field "$f" scope)"
  local cur; cur="$(get_field "$f" status)"
  if [ "$cur" = "done" ] || [ "$cur" = cancelled ]; then
    echo "queue: item is terminal (${id})" >&2; return 1
  fi
  if [ "$cur" = blocked ] && ! all_blockers_done "$f"; then
    echo "queue: item is blocked by $(get_field "$f" blocked_by)" >&2; return 1
  fi
  # invariant: at most one in_progress per scope
  local others; others="$(grep -rl "^type: task" "$ROOT_DIR/vault/queue/$scope" --include='*.md' 2>/dev/null || true)"
  while IFS= read -r o; do
    [ -n "$o" ] || continue
    [ "$o" = "$f" ] && continue
    if [ "$(get_field "$o" status)" = in_progress ]; then
      set_field "$o" status pending; set_field "$o" updated "$(now)"
    fi
  done <<< "$others"
  set_field "$f" status in_progress; set_field "$f" updated "$(now)"
}
cmd_terminal() {  # $1=id $2=done|cancelled
  local id="$1" st="$2" rel f cur; rel="$(find_by_id "$id")" || return 1
  f="$ROOT_DIR/$rel"; cur="$(get_field "$f" status)"
  [ "$cur" = "$st" ] && return 0
  if [ "$cur" = "done" ] || [ "$cur" = cancelled ]; then
    echo "queue: already terminal ($cur)" >&2; return 1
  fi
  if [ "$st" = "done" ]; then
    local verify rc=0; verify="$(get_field "$f" verify)"
    if [ -n "$verify" ]; then
      bash -c "$verify" >&2 || rc=$?
      if [ "$rc" -eq 0 ]; then
        set_field "$f" verified "$(now)"
      elif ! on_verify_fail "$f" "$rc"; then
        return 1
      fi
    fi
  fi
  set_field "$f" status "$st"; set_field "$f" updated "$(now)"
  if [ "$st" = "done" ]; then
    set_field "$f" completed "$(now)"
    wake_dependents "$(get_field "$f" id)"
  fi
  return 0
}

# --- watchdog -------------------------------------------------------------
# `review <id> --watchdog <agent>` parks the claim in in_review and asks another
# agent (event-bus) to re-check it independently. The watchdog never fixes; it
# answers with queue.item.verified {note_id, verdict: pass|fail, reason}.
cmd_review() {
  local id="$1"; shift
  local agent="" rel f cur
  while [ $# -gt 0 ]; do case "$1" in
    --watchdog) agent="$2"; shift 2;; *) shift;;
  esac; done
  [ -n "$agent" ] || { echo "queue: --watchdog <agent> required" >&2; return 1; }
  rel="$(find_by_id "$id")" || return 1; f="$ROOT_DIR/$rel"; cur="$(get_field "$f" status)"
  if [ "$cur" = "done" ] || [ "$cur" = cancelled ]; then
    echo "queue: item is terminal (${id})" >&2; return 1
  fi
  "$EMIT_BIN" --type=queue.item.verify.requested \
    --payload="{\"note_id\":\"${id}\",\"path\":\"${rel}\",\"watchdog\":\"${agent}\"}"
  set_field "$f" watchdog "$agent"
  set_field "$f" status in_review; set_field "$f" updated "$(now)"
}
apply_verdict() {  # $1=id $2=pass|fail $3=reason
  local rel f; rel="$(find_by_id "$1")" || return 1; f="$ROOT_DIR/$rel"
  [ "$(get_field "$f" status)" = in_review ] || return 0
  if [ "$2" = pass ]; then
    cmd_terminal "$1" "done"
  else
    set_field "$f" status pending; set_field "$f" updated "$(now)"
    printf '\n- %s watchdog %s rejected: %s\n' "$(now)" "$(get_field "$f" watchdog)" "${3:-no reason given}" >> "$f"
  fi
}

cmd_list() {
  local scope="" status=""
  while [ $# -gt 0 ]; do case "$1" in
    --scope) scope="$2"; shift 2;; --status) status="$2"; shift 2;; *) shift;;
  esac; done
  local dir="$ROOT_DIR/vault/queue"; [ -n "$scope" ] && dir="$dir/$scope"
  [ -d "$dir" ] || return 0
  grep -rl "^type: task" "$dir" --include='*.md' 2>/dev/null | while read -r f; do
    local st ti; st="$(get_field "$f" status)"; ti="$(sed -n 's/^# //p' "$f" | head -1)"
    [ -n "$status" ] && [ "$st" != "$status" ] && continue
    printf '%s\t[%s]\t%s\t%s\n' "$st" "$(get_field "$f" priority)" "$ti" "$(get_field "$f" id)"
  done
}

cmd_dispatch() {
  local id="$1"; shift
  local mode=handoff agent="" rel f
  while [ $# -gt 0 ]; do case "$1" in
    --to) agent="$2"; shift 2;; --event) mode=event; shift;; *) shift;;
  esac; done
  rel="$(find_by_id "$id")" || return 1; f="$ROOT_DIR/$rel"
  if [ "$mode" = event ]; then
    "$EMIT_BIN" --type=queue.item.dispatched --payload="{\"note_id\":\"${id}\",\"path\":\"${rel}\"}"
    local eid; eid="$(get_field "$f" id)"
    set_field "$f" dispatch "event:${eid}"
  else
    [ -n "$agent" ] || { echo "queue: --to <agent> required for handoff" >&2; return 1; }
    set_field "$f" dispatch "handoff:${agent}"
  fi
  cmd_start "$id"
}

cmd_board() {
  local out="$ROOT_DIR/vault/queue/index.md"
  mkdir -p "$ROOT_DIR/vault/queue"
  {
    echo "# Queue board"; echo
    for st in in_progress in_review blocked pending "done" cancelled; do
      echo "## $st"
      cmd_list --status "$st" | sort | while IFS=$'\t' read -r _ prio ti id; do
        printf -- '- %s %s (%s)\n' "$prio" "$ti" "$id"
      done || true
      echo
    done
  } > "$out"
  printf '%s\n' "vault/queue/index.md"
}

cmd_consume_completions() {
  "$POLL_BIN" --type='queue.item.*' 2>/dev/null | while IFS= read -r line; do
    [ -n "$line" ] || continue
    local ev nid verdict reason
    ev="$(printf '%s' "$line" | python3 -c 'import sys,json; e=json.load(sys.stdin); p=e.get("payload",{}); print("\t".join([e.get("type",""), p.get("note_id",""), p.get("verdict",""), p.get("reason","").replace("\t"," ").replace("\n"," ")]))' 2>/dev/null || true)"
    IFS=$'\t' read -r ev nid verdict reason <<< "$ev" || true
    [ -n "$nid" ] || continue
    case "$ev" in
      queue.item.completed) cmd_terminal "$nid" "done" 2>/dev/null || true ;;
      queue.item.verified)  apply_verdict "$nid" "$verdict" "$reason" 2>/dev/null || true ;;
    esac
  done || true
}

case "${1:-}" in
  add)    shift; cmd_add "$@";;
  list)   shift; cmd_list "$@";;
  start)  shift; cmd_start "$1";;
  "done") shift; cmd_terminal "$1" "done";;
  cancel)   shift; cmd_terminal "$1" cancelled;;
  dispatch) shift; cmd_dispatch "$@";;
  block)  shift; cmd_block "$@";;
  review) shift; cmd_review "$@";;
  board) shift; cmd_board;;
  consume-completions) shift; cmd_consume_completions;;
  *) echo "usage: queue.sh {add|list|start|done|cancel|block|review|dispatch|board|consume-completions}" >&2; exit 2;;
esac
