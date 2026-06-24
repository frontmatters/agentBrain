#!/usr/bin/env bash
# channel.sh — pick and resolve the release channel agentBrain follows.
#
# Two parallel models, configurable (mode = branch | tag):
#   branch  — each channel maps to a git branch (edge->main, prerelease->next,
#             stable->stable). Following a channel = tracking its branch.
#   tag     — channels filter the tag stream by semver suffix:
#             stable = tag without a -suffix, prerelease = tag with -prerelease/-beta,
#             edge = the branch HEAD (no tag).
#
# Config lives at local/update/config.json (machine-local — each machine can
# sit on a different channel). This script only *reads/sets the channel* and
# *resolves the ref*; the actual self-update (brain update) consumes resolve().
set -euo pipefail

BRAIN="${AGENTBRAIN_DIR:-$HOME/agentBrain}"
CFG="$BRAIN/local/update/config.json"
REPO="${AGENTBRAIN_DEV_DIR:-$HOME/Developer/agentBrain-dev}"

CHANNELS=(edge prerelease stable)

c() { printf '\033[%sm' "$1"; }
dim() { printf '%s%s%s' "$(c 2)" "$*" "$(c 0)"; }

ensure_cfg() {
  if [ ! -f "$CFG" ]; then
    mkdir -p "$(dirname "$CFG")"
    cat > "$CFG" <<'JSON'
{
  "channel": "stable",
  "mode": "branch",
  "source": "origin",
  "auto_update": "ask",
  "branches": { "edge": "main", "prerelease": "next", "stable": "stable" }
}
JSON
  fi
}

cfg_get() { python3 -c "import json,sys; print(json.load(open('$CFG')).get('$1',''))"; }
cfg_branch() { python3 -c "import json; print(json.load(open('$CFG'))['branches'].get('$1','$1'))"; }

cfg_set() { # key value
  python3 - "$1" "$2" <<PY
import json, sys
k, v = sys.argv[1], sys.argv[2]
d = json.load(open("$CFG"))
d[k] = v
json.dump(d, open("$CFG", "w"), indent=2)
open("$CFG", "a").write("\n")
PY
}

git_q() { git -C "$REPO" "$@" 2>/dev/null; }

# Resolve a channel to a concrete git ref, honouring mode.
resolve() {
  local chan="${1:-$(cfg_get channel)}"
  local mode; mode="$(cfg_get mode)"
  if [ "$mode" = "tag" ]; then
    # Strict patterns: prerelease matches ONLY our clean vX.Y.Z-prerelease-NN
    # form (not -beta/-rc or other hyphenated tags); stable matches a bare vX.Y.Z.
    case "$chan" in
      edge)       git_q rev-parse --abbrev-ref HEAD ;;
      prerelease) git_q tag --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+-prerelease-[0-9]+$' | head -1 ;;
      stable)     git_q tag --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1 ;;
    esac
  else
    cfg_branch "$chan"
  fi
}

status() {
  ensure_cfg
  local chan mode src; chan="$(cfg_get channel)"; mode="$(cfg_get mode)"; src="$(cfg_get source)"
  printf '%sagentBrain release channel%s\n\n' "$(c 1)" "$(c 0)"
  printf '  channel : %s%s%s\n' "$(c 36)" "$chan" "$(c 0)"
  printf '  mode    : %s   %s\n' "$mode" "$(dim "(branch = track a branch · tag = filter tags by suffix)")"
  printf '  source  : %s\n\n' "$src"
  printf '  %-12s %-10s %s\n' "CHANNEL" "REF" "AT"
  for ch in "${CHANNELS[@]}"; do
    local ref at marker=""
    ref="$(resolve "$ch")"
    if [ "$mode" = "branch" ]; then
      at="$(git_q rev-parse --short "origin/$ref" 2>/dev/null || git_q rev-parse --short "$ref" 2>/dev/null || echo '—')"
    else
      at="$ref"; ref="(tag)"
    fi
    [ "$ch" = "$chan" ] && marker="$(c 36)●$(c 0)" || marker=" "
    printf '  %s %-10s %-10s %s\n' "$marker" "$ch" "$ref" "$(dim "$at")"
  done
  printf '\n  %s\n' "$(dim "brain channel set <edge|prerelease|stable> · brain channel mode <branch|tag>")"
}

usage() {
  cat <<EOF
channel.sh — agentBrain release channel

  channel.sh [status]              show current channel + where each one points
  channel.sh set <channel>         switch channel (edge | prerelease | stable)
  channel.sh mode <branch|tag>     switch resolution model
  channel.sh resolve [channel]     print the git ref for a channel (used by brain update)
  channel.sh list                  list channel names
EOF
}

main() {
  ensure_cfg
  case "${1:-status}" in
    status|"") status ;;
    set)
      [ -n "${2:-}" ] || { echo "usage: channel.sh set <edge|prerelease|stable>" >&2; exit 1; }
      case " ${CHANNELS[*]} " in *" $2 "*) cfg_set channel "$2"; echo "channel -> $2" ;;
        *) echo "unknown channel: $2 (edge|prerelease|stable)" >&2; exit 1 ;; esac ;;
    mode)
      case "${2:-}" in branch|tag) cfg_set mode "$2"; echo "mode -> $2" ;;
        *) echo "usage: channel.sh mode <branch|tag>" >&2; exit 1 ;; esac ;;
    resolve) resolve "${2:-}" ;;
    list) printf '%s\n' "${CHANNELS[@]}" ;;
    -h|--help|help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
