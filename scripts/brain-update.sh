#!/usr/bin/env bash
# brain-update.sh — self-update agentBrain to the latest release on your channel.
#
# The consumer half of the release-channel system (channel.sh is the picker).
# Resolves your channel to a git ref, fetches, and — only if there is something
# genuinely newer — fast-forwards behind a doctor --fast gate, with an exact-ref
# rollback anchor. It never forces over uncommitted work or detaches you silently.
#
#   brain-update.sh            update to the newest release on your channel
#   brain-update.sh --check    report whether an update is available; change nothing
#   brain-update.sh --repo P   operate on repo P (default: AGENTBRAIN_DEV_DIR)
#   brain-update.sh --switch   allow switching branch / detaching to a tag
#
# Design notes (validated by the channels peer-review, 2026-06-14):
#   - record the EXACT current ref (tag or SHA) up front; rollback uses that, not
#     "the previous tag" (edge sits on an untagged commit).
#   - a failed/offline fetch aborts cleanly: no half-pull, nothing changed.
#   - doctor --fast gates EVERY channel, edge included; a broken HEAD is rejected.
set -euo pipefail

# Default repo: resolve the ~/agentBrain alias (the switchable symlink `brain use`
# maintains) to the ACTIVE checkout, so updates land where the user actually is.
# Falls back to the conventional dev path when the alias is absent or not a repo.
# An explicit AGENTBRAIN_DEV_DIR (or --repo) always wins.
_default_repo() {
  local alias_path="${AGENTBRAIN_HOME:-$HOME}/agentBrain" target
  if [ -L "$alias_path" ]; then
    target="$(readlink "$alias_path" 2>/dev/null || true)"
    case "$target" in
      /*) : ;;                                        # absolute — keep
      ?*) target="$(dirname "$alias_path")/$target" ;; # relative — anchor at the alias dir
    esac
    if [ -n "$target" ] && [ -d "$target/.git" ]; then
      printf '%s\n' "$target"
      return
    fi
  elif [ -d "$alias_path/.git" ]; then
    # Consumer layout: ~/agentBrain is a real single checkout (no dev/live
    # symlink flip) — e.g. a Linux host installed straight from the release.
    printf '%s\n' "$alias_path"
    return
  fi
  printf '%s\n' "$HOME/Developer/agentBrain-dev"
}
REPO="${AGENTBRAIN_DEV_DIR:-$(_default_repo)}"
CHECK_ONLY=0
ALLOW_SWITCH=0
SESSION=0
DOCTOR_CMD="${BRAIN_UPDATE_DOCTOR:-}"   # env override (inherited by --session subprocess); --doctor-cmd wins

while [ $# -gt 0 ]; do
  case "$1" in
    --check)        CHECK_ONLY=1 ;;
    --switch)       ALLOW_SWITCH=1 ;;
    --session)      SESSION=1 ;;
    --repo)         REPO="$2"; shift ;;
    --doctor-cmd)   DOCTOR_CMD="$2"; shift ;;
    -h|--help)      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "brain-update: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# --session: act on the configured auto_update mode, fail-safe. Called from the
# session-start flow, so it must NEVER abort a session — any error exits 0 quietly.
#   off    -> do nothing
#   notify -> report if an update is available, change nothing
#   ask    -> if an update is available, ASK before updating. Interactive shell
#             (TTY): y/N prompt. No TTY (agent session hook): print an agent-neutral
#             line so the consuming agent (any LLM/CLI) asks the user. (install default)
#   auto   -> update behind the gate; on any problem, just stay put
if [ "$SESSION" -eq 1 ]; then
  CFG="${AGENTBRAIN_DIR:-$HOME/agentBrain}/local/update/config.json"
  # auto_update default cascade (keep in sync with channel.sh, which seeds "ask"):
  #   config file missing  -> off  (never touch an unconfigured install)
  #   key missing in file  -> ask  (conservative: a config exists, so ask first)
  #   otherwise            -> the configured value
  m="$(python3 -c "import json,os;p='$CFG';print(json.load(open(p)).get('auto_update','ask') if os.path.exists(p) else 'off')" 2>/dev/null || echo off)"
  # Rate-limit: at most once per BRAIN_UPDATE_INTERVAL_H hours (default 12), so it
  # is cheap to call from every shell start / session hook. Stamp file per repo.
  stamp="${AGENTBRAIN_DIR:-$HOME/agentBrain}/local/update/.last-session-check"
  interval_h="${BRAIN_UPDATE_INTERVAL_H:-12}"
  if [ "$m" != "off" ] && [ -f "$stamp" ]; then
    now=$(date +%s); last=$(cat "$stamp" 2>/dev/null || echo 0)
    if [ $(( (now - last) / 3600 )) -lt "$interval_h" ]; then exit 0; fi
  fi
  [ "$m" != "off" ] && { mkdir -p "$(dirname "$stamp")"; date +%s > "$stamp" 2>/dev/null || true; }
  case "$m" in
    off)    exit 0 ;;
    notify) bash "$0" --check ${REPO:+--repo "$REPO"} || true ;;          # show msg, never block
    ask)
      # Only prompt when there is genuinely an update. --check exits 10 when yes;
      # capture so set -e can't trip on the non-zero "update available" signal.
      rc=0; out="$(bash "$0" --check ${REPO:+--repo "$REPO"} 2>&1)" || rc=$?
      if [ "$rc" -eq 10 ]; then
        printf '%s\n' "$out"
        if [ -t 0 ] && [ -t 1 ]; then            # interactive shell: ask the human directly
          printf 'Update agentBrain now? [y/N] '
          read -r ans || ans=n
          case "$ans" in [yY]*) bash "$0" ${REPO:+--repo "$REPO"} || true ;; esac
        else                                      # agent session hook: hand the decision to the agent
          printf '[agentBrain] An update is available. Ask the user whether to update; if yes, run: %s\n' "$REPO/scripts/brain-update.sh"
        fi
      fi
      ;;
    auto)
      # Update or stay put. Not fully silent: output goes to a log file so a
      # failed/rolled-back auto-update is inspectable afterwards.
      auto_log="${AGENTBRAIN_DIR:-$HOME/agentBrain}/local/update/last-auto.log"
      mkdir -p "$(dirname "$auto_log")" 2>/dev/null || true
      bash "$0" ${REPO:+--repo "$REPO"} >"$auto_log" 2>&1 || true
      ;;
  esac
  exit 0   # a session-start check must never fail the session
fi

c() { printf '\033[%sm' "$1"; }
ok()   { printf '%s✓%s %s\n' "$(c '1;32')" "$(c 0)" "$*"; }
info() { printf '%s·%s %s\n' "$(c 2)" "$(c 0)" "$*"; }
warn() { printf '%s⚠%s %s\n' "$(c '1;33')" "$(c 0)" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$(c '1;31')" "$(c 0)" "$*" >&2; exit 1; }

[ -d "$REPO/.git" ] || die "not a git repo: $REPO"
g() { git -C "$REPO" "$@"; }

CHANNEL_SH="$REPO/scripts/channel.sh"
[ -x "$CHANNEL_SH" ] || CHANNEL_SH="$(dirname "$0")/channel.sh"
[ "${DOCTOR_CMD:-}" = "" ] && DOCTOR_CMD="bash $REPO/scripts/doctor.sh --fast"

# Read channel config — same path resolution as channel.sh (honours AGENTBRAIN_DIR).
CFG="${AGENTBRAIN_DIR:-$HOME/agentBrain}/local/update/config.json"
cfg_val() {  # key default
  python3 -c "import json,os,sys
p='$CFG'
print(json.load(open(p)).get('$1','$2') if os.path.exists(p) else '$2')" 2>/dev/null || echo "$2"
}
chan="$(bash "$CHANNEL_SH" resolve 2>/dev/null || true)"   # resolved ref (branch or tag)
mode="$(cfg_val mode branch)"
remote="$(cfg_val source origin)"
channel_name="$(cfg_val channel prerelease)"

[ -n "$chan" ] || die "channel resolved to nothing — no release on '$channel_name' yet (mode=$mode)"

# tag-mode resolves a named release tag; 'edge' tracks a moving branch and has no
# tag to point at, so channel.sh hands back a branch name that the tag lookup
# below cannot resolve. Catch this config combo here with a clear message instead
# of the opaque "cannot resolve target ref '<branch>'" failure further down.
if [ "$mode" = "tag" ] && [ "$channel_name" = "edge" ]; then
  die "channel 'edge' is not valid in tag-mode (edge tracks a branch, not a release tag) — use channel 'prerelease' or 'stable', or set mode=branch"
fi

# 0. Rollback anchor: ALWAYS the exact SHA. The branch name is not safe — a
#    fast-forward moves the branch pointer, so "reset to <branch>" after an ff
#    would land back on the broken commit (finding #4). We keep cur_branch only
#    to know whether to land back on a branch or stay detached.
cur_branch="$(g rev-parse --abbrev-ref HEAD)"
cur_sha="$(g rev-parse HEAD)"
anchor="$cur_sha"

# 2. Fetch — failure aborts cleanly, nothing changed.
info "fetching $remote …"
if ! g fetch --quiet --tags "$remote" 2>/dev/null; then
  die "fetch from '$remote' failed (offline?) — nothing changed"
fi

# Resolve the target commit for the channel.
if [ "$mode" = "tag" ]; then
  target_ref="$chan"
  target="$(g rev-parse --verify "refs/tags/$chan^{commit}" 2>/dev/null || true)"
else
  target_ref="$remote/$chan"
  target="$(g rev-parse --verify "$target_ref" 2>/dev/null || true)"
fi
[ -n "$target" ] || die "cannot resolve target ref '$target_ref'"

short_t="$(g rev-parse --short "$target")"
short_h="$(g rev-parse --short HEAD)"

# 3. Compare by ancestry (robust; no version-string parsing).
if [ "$target" = "$cur_sha" ] || g merge-base --is-ancestor "$target" HEAD 2>/dev/null; then
  ok "up to date — '$channel_name' is at $short_t, you have it"
  exit 0
fi

# There is something newer.
if [ "$CHECK_ONLY" -eq 1 ]; then
  ver="$(g show "$target:VERSION" 2>/dev/null | head -1 || echo '?')"
  warn "update available on '$channel_name': $short_h → $short_t  (VERSION $ver)"
  echo "  run: brain-update.sh"
  exit 10
fi

# 4. Pre-flight: never force over uncommitted work.
[ -z "$(g status --porcelain)" ] || die "working tree not clean — commit/stash first, then update"

# Fast-forward only. If we cannot ff (diverged, or not on the channel branch in
# branch-mode, or a tag in tag-mode), do not detach/force unless --switch.
ff_possible=0
if [ "$mode" = "branch" ] && [ "$cur_branch" = "$chan" ]; then
  g merge-base --is-ancestor HEAD "$target" 2>/dev/null && ff_possible=1
fi

if [ "$ff_possible" -eq 1 ]; then
  info "fast-forward $cur_branch → $short_t"
  g merge --ff-only "$target" >/dev/null
else
  if [ "$ALLOW_SWITCH" -eq 0 ]; then
    warn "target $short_t ($target_ref) is newer, but a clean fast-forward isn't possible"
    info "you are on '$cur_branch'; channel '$channel_name' wants '$chan' ($mode mode)"
    info "re-run with --switch to check it out (detached for a tag)"
    exit 11
  fi
  info "switching to $target_ref ($short_t)"
  g checkout --quiet --detach "$target"
fi

# 5. Doctor gate — applies to EVERY channel, edge included.
info "validating with doctor --fast …"
doctor_log="$(mktemp "${TMPDIR:-/tmp}/brain-update-doctor.XXXXXX")"
if eval "$DOCTOR_CMD" >"$doctor_log" 2>&1; then
  rm -f "$doctor_log"
  new_ver="$(g show HEAD:VERSION 2>/dev/null | head -1 || echo '?')"
  ok "updated to $short_t on '$channel_name' (VERSION $new_ver)"
  info "rollback anchor was $anchor — discard with: git -C $REPO reset --hard $anchor"
  # Self-healing wiring: re-link skills into every detected agent so a skill or
  # addon added since the last install can never stay invisible (the original
  # cause of "no /commands on a fresh/updated machine"). Idempotent + best-effort:
  # setup-skills.sh = Claude Code/Copilot, configure-pi.sh = Pi. A wiring hiccup
  # must not fail an update the gate already accepted.
  if [ -f "$REPO/scripts/setup-skills.sh" ]; then
    if bash "$REPO/scripts/setup-skills.sh" >/dev/null 2>&1 </dev/null; then
      info "skills re-wired (Claude Code/Copilot)"
    else
      warn "skill re-wire skipped/failed — run: bash $REPO/scripts/setup-skills.sh"
    fi
  fi
  if [ -f "$REPO/scripts/configure-pi.sh" ] && { [ -d "${AGENTBRAIN_HOME:-$HOME}/.pi/agent" ] || command -v pi >/dev/null 2>&1; }; then
    if bash "$REPO/scripts/configure-pi.sh" >/dev/null 2>&1 </dev/null; then
      info "Pi re-wired"
    else
      warn "Pi re-wire skipped/failed — run: bash $REPO/scripts/configure-pi.sh"
    fi
  fi
else
  warn "doctor --fast FAILED on $short_t — rolling back to ${anchor:0:9}"
  tail -5 "$doctor_log" >&2 || true
  info "full doctor log: $doctor_log"
  if [ "$ff_possible" -eq 1 ]; then
    # We fast-forwarded the channel branch (HEAD still on it); the branch moved
    # forward, so reset it back to the exact pre-update commit.
    g reset --hard --quiet "$anchor"
  elif [ "$cur_branch" != "HEAD" ]; then
    # We detached via --switch but started on a real branch. The branch itself
    # never moved (detach only moved HEAD), so check it back out to land where
    # we were — NOT a detached reset, which would strand us on the old SHA.
    g checkout --quiet "$cur_branch"
  else
    # We started detached; return to the exact pre-update commit.
    g checkout --quiet --detach "$anchor"
  fi
  die "rolled back — '$channel_name' update rejected by the gate"
fi
