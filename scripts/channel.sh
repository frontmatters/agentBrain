#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
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
# shellcheck disable=SC1091
. "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/installer/prompt-helper.sh"


BRAIN="${AGENTBRAIN_DIR:-$HOME/agentBrain}"
CFG="$BRAIN/vault/update/config.json"
# Repo the channel refs resolve against. Consumer layout first: when the brain
# alias itself is a real checkout (single-checkout install, no dev/live flip),
# use it — the Developer/agentBrain-dev fallback only exists on maintainer
# machines. Mirrors brain-update.sh's _default_repo.
_default_repo() {
	# Follow the ~/agentBrain alias — symlink OR real dir — to the ACTIVE checkout.
	# The alias is the switchable pointer every install has; excluding symlinks
	# sent fresh machines to a dev-only fallback path that does not exist there.
	if [ -e "$BRAIN/.git" ]; then
		(cd "$BRAIN" && pwd -P)
	else
		printf '%s\n' "$HOME/Developer/agentBrain-dev"
	fi
}
REPO="${AGENTBRAIN_DEV_DIR:-$(_default_repo)}"

CHANNELS=(edge prerelease stable)

c() { printf '\033[%sm' "$1"; }
dim() { printf '%s%s%s' "$(c 2)" "$*" "$(c 0)"; }

ensure_cfg() {
  if [ ! -f "$CFG" ]; then
    mkdir -p "$(dirname "$CFG")"
    # auto_update default cascade (keep in sync with brain-update.sh --session):
    #   config file missing  -> off  (brain-update never touches an unconfigured install)
    #   key missing in file  -> ask  (conservative: a config exists, so ask first)
    #   this seed            -> ask  (the install default)
    # tag mode (not branch): the public repo is a single-branch clean snapshot, so
    # channels resolve from tags (stable = latest vX.Y.Z) rather than per-channel
    # branches, which don't exist there. branches{} is kept for branch-mode users.
    cat > "$CFG" <<'JSON'
{
  "channel": "stable",
  "mode": "tag",
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

# The prerelease channel serves the leading edge, which is not always a
# prerelease tag. Shipping 1.10.8, 1.10.9 and 1.10.10 straight to stable left
# the newest prerelease tag at v1.10.7-prerelease-01, so following prerelease
# meant running older code than stable. That recurs after every stable release
# cut without a prerelease before it, so the resolver has to handle it.
#
# A prerelease only wins when it belongs to a HIGHER version than the newest
# stable: 1.10.11-prerelease-01 beats 1.10.10, but loses to 1.10.11, because
# semver puts a prerelease before its own release. `sort -V` gets that last
# case wrong, so the base versions are compared and the tie goes to stable.
newest_prerelease() {
  local pre sta base
  # `|| true`: with set -e a grep that matches nothing fails the pipeline and
  # aborts the script. No prerelease tag is a normal state, not an error.
  pre="$(git_q tag --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+-prerelease-[0-9]+$' | head -1 || true)"
  sta="$(git_q tag --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
  [ -z "$pre" ] && { printf '%s' "$sta"; return; }
  [ -z "$sta" ] && { printf '%s' "$pre"; return; }
  base="${pre%%-prerelease-*}"
  if [ "$base" != "$sta" ] && [ "$(printf '%s\n%s\n' "$base" "$sta" | sort -V | tail -1)" = "$base" ]; then
    printf '%s' "$pre"
  else
    printf '%s' "$sta"
  fi
}

# Resolve a channel to a concrete git ref, honouring mode.
resolve() {
  local chan="${1:-$(cfg_get channel)}"
  local mode; mode="$(cfg_get mode)"
  if [ "$mode" = "tag" ]; then
    # Strict patterns: prerelease matches ONLY our clean vX.Y.Z-prerelease-NN
    # form (not -beta/-rc or other hyphenated tags); stable matches a bare vX.Y.Z.
    case "$chan" in
      edge)       git_q rev-parse --abbrev-ref HEAD ;;
      prerelease) newest_prerelease ;;
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

# Guided flow: status first, then the onboarding question with the option texts
# from choices.json (single source with the wizard). Enter keeps the current
# channel; a number or name switches (edge auto-flips tag-mode via `set`).
guide() {
  ensure_cfg
  status
  printf '\n'
  local cur; cur="$(cfg_get channel)"
  local cjson; cjson="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/system/skills/onboard/choices.json"
  printf '%s? How eagerly do you want agentBrain updates?%s\n' "$(c 36)" "$(c 0)"
  if [ -f "$cjson" ]; then
    python3 - "$cjson" <<'PY'
import json, sys
opts = json.load(open(sys.argv[1]))["fields"]["channel"]["options"]
for i, o in enumerate(opts):
    print(f"   {i+1}) {o['value']:<12} \033[2m{o.get('desc','')}\033[0m")
PY
  else
    printf '   1) stable\n   2) prerelease\n   3) edge\n'
  fi
  local pick_opts=() ch
  for ch in stable prerelease edge; do
    if [ "$ch" = "$cur" ]; then pick_opts+=("$ch — current"); else pick_opts+=("$ch"); fi
  done
  if ab_prompt_select --default 1 "Release channel (current: $cur)?" "${pick_opts[@]}"; then
    case "$REPLY" in
      0) main set stable ;;
      1) main set prerelease ;;
      2) main set edge ;;
    esac
    printf '%s\n' "$(dim "next: brain update --check")"
    return 0
  fi
  echo "kept: $cur — nothing changed"
  printf '%s\n' "$(dim "next: brain update --check")"
}

usage() {
  cat <<EOF
channel.sh — agentBrain release channel

  channel.sh                       interactive: status + guided switch (on a terminal)
  channel.sh status                show current channel + where each one points
  channel.sh set <channel>         switch channel (edge | prerelease | stable)
  channel.sh mode <branch|tag>     switch resolution model
  channel.sh resolve [channel]     print the git ref for a channel (used by brain update)
  channel.sh list                  list channel names
EOF
}

main() {
  ensure_cfg
  case "${1:-}" in
    "")
      # Bare invocation on a real terminal guides; scripted use stays status.
      if [ -t 0 ] || { [ -e /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; }; then
        guide
      else
        status
      fi ;;
    status) status ;;
    guide) guide ;;
    set)
      [ -n "${2:-}" ] || { echo "usage: channel.sh set <edge|prerelease|stable>" >&2; exit 1; }
      case " ${CHANNELS[*]} " in *" $2 "*)
        cfg_set channel "$2"; echo "channel -> $2"
          # No mode flip here. Selecting edge used to force the whole install
          # to branch mode, because brain-update refused edge in tag mode.
          # That refusal is gone: edge resolves as a branch in either mode,
          # because what a channel resolves to is decided by the channel,
          # not by the mode. Rewriting a setting the user chose, as a side
          # effect of picking a channel, is its own defect.
          ;;
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
