#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# brain — the agentBrain CLI: switch the active framework (dev|live), self-update,
# pick the release channel, (re)wire agents, health-check, and onboard — one entry
# point that proxies the underlying scripts/*.sh (which all keep working standalone).
# Installed on PATH as both 'brain' and the 'agentbrain' alias.
#
# Agents read through the alias $AGENTBRAIN_HOME/agentBrain (default ~/agentBrain).
# `brain use` flips that one symlink, so Claude (CLAUDE.md → alias) and Pi
# (extensions resolve via that alias since brain-paths.ts patch 2026-05-25; the
# earlier ~/.agentbrain hidden symlink chain was removed in the namespace cleanup
# of the same date) all follow without re-running setup. Knowledge (shared local/)
# is never touched by a switch.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/installer/prompt-helper.sh"


AGENTBRAIN_HOME="${AGENTBRAIN_HOME:-$HOME}"
ALIAS="$AGENTBRAIN_HOME/agentBrain"

# Resolve this script's real checkout (portable — macOS readlink has no -f).
# MUST come before sourcing lib/: invoked via the ~/bin/brain (or agentbrain)
# symlink, dirname BASH_SOURCE is ~/bin — the lib only exists in the checkout.
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
	dir="$(cd -P "$(dirname "$src")" && pwd)"
	src="$(readlink "$src")"
	[[ "$src" != /* ]] && src="$dir/$src"
done
HERE="$(cd -P "$(dirname "$src")/.." && pwd)" # the checkout this script lives in

# Tools (npm/node/bun) live in user-scoped installs — load them before probing.
# shellcheck disable=SC1091
source "$HERE/scripts/lib/_toolpaths.sh"

# Convention: <base> = live, <base>-dev = dev, <base>-next = prerelease.
# Override with BRAIN_LIVE/BRAIN_DEV/BRAIN_NEXT.
#
# The three checkouts mirror the three release channels that channel.sh already
# defines (edge->main, prerelease->next, stable->stable), so the maintainer's
# working copies and what a consumer can follow use the same vocabulary:
#   dev   -> branch main    -> channel edge       (trying things out)
#   next  -> branch next    -> channel prerelease (the next production version)
#   live  -> published      -> channel stable     (what is online)
#
# factory.json is consulted first. The suffix convention below only holds while
# the checkouts sit side by side and end in -dev / -next: give it a nested path
# like framework/dev and the suffix strips nothing, so BRAIN_LIVE silently
# becomes the dev checkout itself. Reading the paths from a file makes a move a
# one-file change instead of a rename that redefines what "live" means.
# shellcheck source=scripts/lib/factory.sh disable=SC1091
source "$HERE/scripts/lib/factory.sh"

BASE="${HERE%-dev}"
BASE="${BASE%-next}"
BRAIN_LIVE="${BRAIN_LIVE:-$(factory_path framework.live)}"
BRAIN_DEV="${BRAIN_DEV:-$(factory_path framework.dev)}"
BRAIN_NEXT="${BRAIN_NEXT:-$(factory_path framework.next)}"
# Fall back to the convention so a checkout without factory.json keeps working.
BRAIN_LIVE="${BRAIN_LIVE:-$BASE}"
BRAIN_DEV="${BRAIN_DEV:-${BASE}-dev}"
BRAIN_NEXT="${BRAIN_NEXT:-${BASE}-next}"
# Branch that `next` is measured against in `brain status`.
BRAIN_DEV_BRANCH="${BRAIN_DEV_BRANCH:-main}"
# Read a checkout's version. VERSION ships everywhere now; README is a fallback.
# drift_of <dir> — hoe ver de checkout voorbij zijn laatste tag staat.
# Leeg wanneer hij er precies op staat, of wanneer er geen tags zijn.
# VERSION is een verklaring; dit is de meting, en alleen die kan niet afdrijven.
drift_of() {
	local d="$1" desc n sha
	desc="$(git -C "$d" describe --tags --match 'v*' --always --dirty 2>/dev/null)" || return 0
	[ -n "$desc" ] || return 0
	# describe geeft <tag>-<n>-g<sha> zodra je voorbij de tag staat.
	if [[ "$desc" =~ -([0-9]+)-g([0-9a-f]+)(-dirty)?$ ]]; then
		n="${BASH_REMATCH[1]}"; sha="${BASH_REMATCH[2]}"
		printf '%s commit(s) past the tag, at %s%s' "$n" "$sha" \
			"$([ -n "${BASH_REMATCH[3]}" ] && echo ', uncommitted changes')"
	elif [[ "$desc" == *-dirty ]]; then
		printf 'on the tag, uncommitted changes'
	fi
}

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
	"$BRAIN_NEXT") echo "next" ;;
	"$BRAIN_LIVE") echo "live" ;;
	*) echo "?" ;;
	esac
}

usage() {
	cat <<EOF
brain v$BRAIN_VERSION — the agentBrain CLI (also installed as 'agentbrain')

USAGE
  brain [command]

COMMANDS
  (none)            On a terminal: a small menu of the tasks below.
                    Scripted (no TTY): same as 'brain status'.
  status            Show the active checkout
  use dev|live      Point agents at the dev / live checkout
  update [...]      Self-update to the newest release on your channel
                    (proxies brain-update.sh: --check, --switch, ...)
  channel [...]     Release channel. Bare 'brain channel' on a terminal is a
                    guided flow (status + switch question); scripted subcommands:
                    status, set <edge|prerelease|stable>, mode <branch|tag>, resolve
  wire [--skills|--pi] [--quiet]
                    (Re)wire this brain into every detected agent: skills for
                    all agents + the Pi deep integration. Idempotent.
  doctor [...]      Health check (proxies doctor.sh: --fast, --summary, ...)
  onboard [--defaults]
                    Model-free personalization wizard (onboard-wizard.sh)
  addons [...]      Add-ons layer (proxies addons.sh: status, install, ...)
  harness           Start the agentBrain Harness web UI; when already running,
                    opens the browser instead. (start is the explicit alias;
                    stop also stops the autostart login-service first, so it
                    stays stopped)
  sandbox [...]     Disposable install-testbed in the browser (start|stop|status)
                    — fresh container per connection; needs docker + ttyd
  uninstall [...]   Symmetric removal of what setup added (pointers, symlinks,
                    env) — your knowledge stays; deleting the checkout needs an
                    explicit --delete-checkout (proxies uninstall.sh)
  version           Show the active framework version (alias: -v, --version)

OPTIONS
  -v, --version     Show version
  -h, --help        Show this help

EXAMPLES
  brain                 # same as 'brain status'
  brain use dev         # develop: agents read the in-progress dev framework
  brain update --check  # is there a newer release on my channel?
  brain channel set edge# follow the moving edge (auto-switches mode to branch)
  brain wire            # after an update/rename: re-link skills + Pi everywhere
  brain harness         # start the agentBrain Harness web UI (alias: brain harness web)

HOW IT WORKS
  Agents read through the alias $ALIAS.
  'use' flips that single symlink, so Claude + Pi follow without re-running setup.
  Knowledge (shared vault/) is never touched by a switch.
  Restart a running agent to pick up a switch.
EOF
}

# Bare `brain` on a real terminal: a small menu-flow for the day-2 tasks.
# Scripted use (no TTY) keeps the old contract: bare `brain` prints status.
brain_menu() {
	echo "brain v$BRAIN_VERSION"
	if ! ab_prompt_select --default 1 "What next?" "status — what's connected" "update — pull the latest" "wire — re-link skills + Pi" "onboard — personalization questions" "doctor — health check (fast)"; then
		exit 0
	fi
	case "$REPLY" in
		0) exec bash "$HERE/scripts/brain.sh" status ;;
		1) exec bash "$HERE/scripts/brain.sh" update ;;
		2) exec bash "$HERE/scripts/brain.sh" wire ;;
		3) exec bash "$HERE/scripts/brain.sh" onboard ;;
		4) exec bash "$HERE/scripts/brain.sh" doctor --fast ;;
	esac
}

case "${1:-}" in
"")
	if [ -t 0 ] || { [ -e /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; }; then
		brain_menu
	fi
	exec bash "$HERE/scripts/brain.sh" status
	;;
status)
	r="$(resolved || true)"
	if [ -z "$r" ]; then
		echo "brain: no active alias at $ALIAS — run 'brain use dev|next|live'" >&2
		exit 1
	fi
	if [ -d "$BRAIN_DEV" ] && [ -d "$BRAIN_LIVE" ] && [ "$BRAIN_DEV" != "$BRAIN_LIVE" ]; then
		# Maintainer layout: a dev/live pair to compare.
		echo "active: $(label_for "$r") ($r)"
		echo "alias : $ALIAS"
		dv="$(ver_of "$BRAIN_DEV")"
		lv="$(ver_of "$BRAIN_LIVE")"
		if [ "$dv" = "$lv" ]; then state="in sync"; else state="differ — run deploy-dev-to-live"; fi
		dd="$(drift_of "$BRAIN_DEV")"
		echo "dev   : v$dv${dd:+   ($dd)}"
		# The prerelease checkout is optional; only report it when it exists,
		# so a two-checkout maintainer layout keeps its previous output.
		if [ -d "$BRAIN_NEXT" ] && [ "$BRAIN_NEXT" != "$BRAIN_DEV" ]; then
			nb="$(git -C "$BRAIN_NEXT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
			behind="$(git -C "$BRAIN_NEXT" rev-list --count "HEAD..$BRAIN_DEV_BRANCH" 2>/dev/null || echo '')"
			if [ -n "$behind" ] && [ "$behind" != "0" ]; then
				echo "next  : v$(ver_of "$BRAIN_NEXT")   (branch $nb, $behind commit(s) behind dev)"
			else
				echo "next  : v$(ver_of "$BRAIN_NEXT")   (branch $nb)"
			fi
		fi
		ld="$(drift_of "$BRAIN_LIVE")"
		echo "live  : v$lv   ($state)${ld:+, $ld}"
	else
		# Consumer layout: one checkout, nothing to compare — show what matters:
		# where it is, the honest version (describe), and the update channel.
		echo "active : $r"
		echo "alias  : $ALIAS"
		desc="$(git -C "$r" describe --tags --match 'v*' 2>/dev/null || echo "v$(ver_of "$r")")"
		echo "version: $desc"
		cfg="${AGENTBRAIN_DIR:-$ALIAS}/vault/update/config.json"
		if [ -f "$cfg" ]; then
			ch="$(python3 -c "import json;d=json.load(open('$cfg'));print(d.get('channel','?'),'('+d.get('mode','?')+' mode)')" 2>/dev/null || true)"
			[ -n "$ch" ] && echo "channel: $ch — check for updates: brain update --check"
		fi
	fi
	;;
use)
	case "${2:-}" in
	dev) target="$BRAIN_DEV" ;;
	next) target="$BRAIN_NEXT" ;;
	live) target="$BRAIN_LIVE" ;;
	"")
		echo "brain: 'use' needs a target — 'dev', 'next' or 'live'" >&2
		exit 1
		;;
	*)
		echo "brain: unknown target '$2' — use 'dev', 'next' or 'live'" >&2
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
version | -v | --version)
	# Between releases, be honest: show release + distance + sha (git describe).
	# $HERE, not dirname BASH_SOURCE — via the ~/bin symlink the latter is ~/bin.
	_desc="$(git -C "$HERE" describe --tags --match 'v*' 2>/dev/null || true)"
	if [ -n "$_desc" ] && [ "$_desc" != "v$BRAIN_VERSION" ]; then
		echo "brain (agentBrain) $_desc"
	else
		echo "brain (agentBrain) v$BRAIN_VERSION"
	fi ;;
-h | --help | help) usage ;;
update)
	shift
	exec bash "$HERE/scripts/brain-update.sh" "$@"
	;;
channel)
	shift
	exec bash "$HERE/scripts/channel.sh" "$@"
	;;
doctor)
	shift
	exec bash "$HERE/scripts/checks/doctor.sh" "$@"
	;;
onboard)
	shift
	if [ "${1:-}" = "--defaults" ]; then
		AB_WIZARD_DEFAULTS=1 exec bash "$HERE/scripts/onboard-wizard.sh"
	fi
	exec bash "$HERE/scripts/onboard-wizard.sh" "$@"
	;;
addons)
	shift
	exec bash "$HERE/scripts/addons.sh" "$@"
	;;
harness)
	shift
	command -v abh >/dev/null 2>&1 || { echo "brain: agentBrain Harness is not installed — install @agentbrain-harness/abh first" >&2; exit 1; }
	abh_web_url() {
		local pid port
		pid="$(pgrep -f "abh.*web" | head -1)" || return 1
		[ -n "$pid" ] || return 1
		port="$(lsof -nP -iTCP -sTCP:LISTEN -a -p "$pid" 2>/dev/null | awk 'NR>1 {sub(".*:","",$9); print $9; exit}')"
		[ -n "$port" ] || return 1
		echo "http://localhost:$port"
	}
	open_url() {
		case "$(uname -s)" in
			Darwin) open "$1" 2>/dev/null || echo "  $1" ;;
			*) command -v xdg-open >/dev/null 2>&1 && xdg-open "$1" || echo "  $1" ;;
		esac
	}
	case "${1:-start}" in
	start|"")
		if url="$(abh_web_url)"; then
			echo "agentBrain Harness Web is already running — opening $url"
			open_url "$url"
		else
			exec abh web "${@:2}"
		fi ;;
	stop)
		pids="$(pgrep -f "abh.*web" || true)"
		[ -n "$pids" ] || { echo "agentBrain Harness Web is not running."; exit 0; }
		# Graceful: with autostart enabled, launchd/systemd (KeepAlive) restarts
		# the service instantly — stop the login service first.
		_st="$(bash "$HERE/scripts/setup/setup-abh-autostart.sh" status 2>/dev/null || true)"
		case "$_st" in
			*enabled*)
				echo "Autostart is ON — stopping the login service first."
				bash "$HERE/scripts/setup/setup-abh-autostart.sh" disable ;;
		esac
		# Deliberately unquoted: $pids may hold several PIDs at once.
		# shellcheck disable=SC2086
		kill $pids 2>/dev/null || true
		i=0
		while pgrep -f "abh.*web" >/dev/null 2>&1 && [ "$i" -lt 10 ]; do
			sleep 0.3; i=$((i + 1))
		done
		if pgrep -f "abh.*web" >/dev/null 2>&1; then
			# shellcheck disable=SC2086
			kill -9 $pids 2>/dev/null || true
		fi
		echo "agentBrain Harness Web stopped."
		echo "note: brain harness (or autostart) starts it again when you want it" ;;
	autostart)
		shift
		exec bash "$HERE/scripts/setup/setup-abh-autostart.sh" "${1:-status}"
		;;
	*) echo "brain: usage: brain harness [start|stop] — start/stop the running UI | brain harness autostart enable|disable|status — the login service" >&2; exit 2 ;;
	esac
	;;
sandbox)
	shift
	exec bash "$HERE/scripts/installer/sandbox.sh" "$@"
	;;
uninstall)
	shift
	exec bash "$HERE/scripts/uninstall.sh" "$@"
	;;
wire)
	# THE wiring primitive — one implementation, three callers (setup.sh's Pi
	# step, brain-update.sh's rewire(), and you after a rename/move). Links the
	# brain's skills into every detected agent and runs the Pi deep integration.
	# Exit code reports failures; --quiet keeps it terse for scripted callers
	# (which decide their own tolerance — brain-update treats it best-effort).
	shift
	WIRE_QUIET=0
	WIRE_ONLY=""
	for _a in "$@"; do
		case "$_a" in
		--quiet | -q) WIRE_QUIET=1 ;;
		--skills) WIRE_ONLY=skills ;;
		--pi) WIRE_ONLY=pi ;;
		*)
			echo "brain: unknown wire option '$_a' (--skills | --pi | --quiet)" >&2
			exit 2
			;;
		esac
	done
	_wire_failed=0
	wire_part() { # <label> <script> — run one wiring step, tolerate failure
		local label="$1" script="$2"
		if [ "$WIRE_QUIET" -eq 1 ]; then
			# Keep the real error: /dev/null made failures undiagnosable.
			local qlog="${TMPDIR:-/tmp}/brain-wire-$$.log"
			if ! bash "$script" >"$qlog" 2>&1 </dev/null; then
				_wire_failed=1
				echo "brain wire: $label failed — log: $qlog · run: bash $script" >&2
			else
				rm -f "$qlog"
			fi
		else
			echo "→ $label"
			bash "$script" || {
				_wire_failed=1
				echo "! $label had issues — re-run: bash $script" >&2
			}
		fi
	}
	if [ "$WIRE_ONLY" != "pi" ]; then
		wire_part "skills (all detected agents)" "$HERE/scripts/setup/setup-skills.sh"
	fi
	if [ "$WIRE_ONLY" != "skills" ]; then
		if [ -d "$AGENTBRAIN_HOME/.pi/agent" ] || command -v pi >/dev/null 2>&1; then
			wire_part "Pi deep integration (extensions + skills + tsconfig)" "$HERE/scripts/configure-pi.sh"
		elif [ "$WIRE_QUIET" -eq 0 ]; then
			echo "· Pi not detected — skipped (install Pi, then: brain wire --pi)"
		fi
	fi
	exit "$_wire_failed"
	;;
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
