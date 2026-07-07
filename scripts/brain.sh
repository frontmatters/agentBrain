#!/usr/bin/env bash
# brain — switch the active agentBrain framework (dev|live) and show status.
#
# Agents read through the alias $AGENTBRAIN_HOME/agentBrain (default ~/agentBrain).
# `brain use` flips that one symlink, so Claude (CLAUDE.md → alias) and Pi
# (extensions resolve via that alias since brain-paths.ts patch 2026-05-25; the
# earlier ~/.agentbrain hidden symlink chain was removed in the namespace cleanup
# of the same date) all follow without re-running setup. Knowledge (shared local/)
# is never touched by a switch.
set -euo pipefail

AGENTBRAIN_HOME="${AGENTBRAIN_HOME:-$HOME}"
ALIAS="$AGENTBRAIN_HOME/agentBrain"

# Resolve this script's real checkout (portable — macOS readlink has no -f).
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
	dir="$(cd -P "$(dirname "$src")" && pwd)"
	src="$(readlink "$src")"
	[[ "$src" != /* ]] && src="$dir/$src"
done
HERE="$(cd -P "$(dirname "$src")/.." && pwd)" # the checkout this script lives in

# Convention: <base> = live, <base>-dev = dev. Override with BRAIN_LIVE/BRAIN_DEV.
BASE="${HERE%-dev}"
BRAIN_LIVE="${BRAIN_LIVE:-$BASE}"
BRAIN_DEV="${BRAIN_DEV:-${BASE}-dev}"
# Read a checkout's version. VERSION ships everywhere now; README is a fallback.
ver_of() {
	local d="$1"
	if [ -f "$d/VERSION" ]; then
		tr -d '[:space:]' <"$d/VERSION"
	elif [ -f "$d/README.md" ] && grep -qm1 'agentBrain v' "$d/README.md"; then
		grep -m1 -oE 'agentBrain v[^ ]+' "$d/README.md" | sed 's/agentBrain v//'
	else
		echo unknown
	fi
}
BRAIN_VERSION="$(ver_of "$HERE")"

resolved() { [ -e "$ALIAS" ] && (cd "$ALIAS" && pwd -P); }

label_for() {
	case "$1" in
	"$BRAIN_DEV") echo "dev" ;;
	"$BRAIN_LIVE") echo "live" ;;
	*) echo "?" ;;
	esac
}

usage() {
	cat <<EOF
brain v$BRAIN_VERSION — switch the active agentBrain framework

USAGE
  brain [command]

COMMANDS
  status            Show the active checkout (default when no command)
  use dev           Point agents at the dev checkout  ($BRAIN_DEV)
  use live          Point agents at the live checkout ($BRAIN_LIVE)
  version           Show the active framework version (alias: -v, --version)

OPTIONS
  -v, --version     Show version
  -h, --help        Show this help

  To check for a newer release on your channel: brain-update.sh --check

EXAMPLES
  brain                 # same as 'brain status'
  brain use dev         # develop: agents read the in-progress dev framework
  brain use live        # stable: agents read the deployed framework
  brain status          # which one is active right now?
  brain voice chat      # proxy to the voice addon CLI

HOW IT WORKS
  Agents read through the alias $ALIAS.
  'use' flips that single symlink, so Claude + Pi follow without re-running setup.
  Knowledge (shared local/) is never touched by a switch.
  Restart a running agent to pick up a switch.
EOF
}

case "${1:-status}" in
status)
	r="$(resolved || true)"
	if [ -z "$r" ]; then
		echo "brain: no active alias at $ALIAS — run 'brain use dev|live'" >&2
		exit 1
	fi
	echo "active: $(label_for "$r") ($r)"
	echo "alias : $ALIAS"
	dv="$(ver_of "$BRAIN_DEV")"
	lv="$(ver_of "$BRAIN_LIVE")"
	if [ "$dv" = "$lv" ]; then state="in sync"; else state="differ — run deploy-dev-to-live"; fi
	echo "dev   : v$dv"
	echo "live  : v$lv   ($state)"
	;;
use)
	case "${2:-}" in
	dev) target="$BRAIN_DEV" ;;
	live) target="$BRAIN_LIVE" ;;
	"")
		echo "brain: 'use' needs a target — 'brain use dev' or 'brain use live'" >&2
		exit 1
		;;
	*)
		echo "brain: unknown target '$2' — use 'dev' or 'live'" >&2
		exit 1
		;;
	esac
	if [ ! -d "$target" ]; then
		echo "brain: '$2' checkout not found at $target" >&2
		exit 1
	fi
	ln -sfn "$target" "$ALIAS"
	echo "brain: now using $2 ($target)"
	echo "  Claude + Pi follow via the alias; restart a running agent to pick it up."
	;;
version | -v | --version) echo "brain (agentBrain) v$BRAIN_VERSION" ;;
-h | --help | help) usage ;;
voice)
	shift
	VOICE_BIN="$HERE/system/addons/voice/bin/brain-voice"
	if [ ! -f "$VOICE_BIN" ]; then
		echo "brain: voice addon not found at $VOICE_BIN" >&2
		exit 1
	fi
	exec bun "$VOICE_BIN" "$@"
	;;
*)
	echo "brain: unknown command '${1:-}'" >&2
	echo "Run 'brain --help' for usage." >&2
	exit 1
	;;
esac
