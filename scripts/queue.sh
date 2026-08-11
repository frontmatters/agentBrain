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
  f="$(grep -rl "^id: ${id}$" "$ROOT_DIR/local/queue" --include='*.md' 2>/dev/null | head -1 || true)"
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
  local scope=inbox prio=P2
  while [ $# -gt 0 ]; do case "$1" in
    --scope) scope="$(slugify "$2")"; shift 2;;
    --prio)  prio="$2"; shift 2;;
    *) shift;;
  esac; done
  local slug rel out t; slug="$(slugify "$title")"; t="$(now)"
  [ -n "$slug" ] || { echo "queue: title produces empty slug: '$title'" >&2; return 1; }
  rel="local/queue/${scope}/${slug}"
  out="$(cd "$ROOT_DIR" && bash scripts/new-note.sh task "$rel" "$title")"
  local f="$out"; [ -f "$f" ] || f="$ROOT_DIR/${out#"$ROOT_DIR"/}"
  set_field "$f" scope "$scope"
  set_field "$f" priority "$prio"
  set_field "$f" agent local
  set_field "$f" dispatch none
  set_field "$f" created "$t"
  set_field "$f" updated "$t"
  set_field "$f" completed ""
  printf '%s\n' "${f#"$ROOT_DIR"/}"
}

cmd_start() {
  local id="$1" rel f scope; rel="$(find_by_id "$id")" || return 1
  f="$ROOT_DIR/$rel"; scope="$(get_field "$f" scope)"
  local cur; cur="$(get_field "$f" status)"
  if [ "$cur" = "done" ] || [ "$cur" = cancelled ]; then
    echo "queue: item is terminal (${id})" >&2; return 1
  fi
  # invariant: at most one in_progress per scope
  local others; others="$(grep -rl "^type: task" "$ROOT_DIR/local/queue/$scope" --include='*.md' 2>/dev/null || true)"
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
  set_field "$f" status "$st"; set_field "$f" updated "$(now)"
  [ "$st" = "done" ] && set_field "$f" completed "$(now)"
  return 0
}

cmd_list() {
  local scope="" status=""
  while [ $# -gt 0 ]; do case "$1" in
    --scope) scope="$2"; shift 2;; --status) status="$2"; shift 2;; *) shift;;
  esac; done
  local dir="$ROOT_DIR/local/queue"; [ -n "$scope" ] && dir="$dir/$scope"
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
  local out="$ROOT_DIR/local/queue/index.md"
  mkdir -p "$ROOT_DIR/local/queue"
  {
    echo "# Queue board"; echo
    for st in in_progress pending "done" cancelled; do
      echo "## $st"
      cmd_list --status "$st" | sort | while IFS=$'\t' read -r _ prio ti id; do
        printf -- '- %s %s (%s)\n' "$prio" "$ti" "$id"
      done || true
      echo
    done
  } > "$out"
  printf '%s\n' "local/queue/index.md"
}

cmd_consume_completions() {
  "$POLL_BIN" --type='queue.item.completed' 2>/dev/null | while IFS= read -r line; do
    [ -n "$line" ] || continue
    local nid; nid="$(printf '%s' "$line" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("payload",{}).get("note_id",""))' 2>/dev/null || true)"
    [ -n "$nid" ] || continue
    cmd_terminal "$nid" "done" 2>/dev/null || true
  done || true
}

case "${1:-}" in
  add)    shift; cmd_add "$@";;
  list)   shift; cmd_list "$@";;
  start)  shift; cmd_start "$1";;
  "done") shift; cmd_terminal "$1" "done";;
  cancel)   shift; cmd_terminal "$1" cancelled;;
  dispatch) shift; cmd_dispatch "$@";;
  board) shift; cmd_board;;
  consume-completions) shift; cmd_consume_completions;;
  *) echo "usage: queue.sh {add|list|start|done|cancel|dispatch|board|consume-completions}" >&2; exit 2;;
esac
