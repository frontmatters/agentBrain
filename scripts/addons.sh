#!/usr/bin/env bash
# agentBrain add-ons layer — one entry point for opt-in, agent-agnostic tools.
# Usage:
#   bash scripts/addons.sh status            # list add-ons + state
#   bash scripts/addons.sh install <id>      # detect→privacy→install→enable→configure→check→opt-in schedule
#   bash scripts/addons.sh uninstall <id>    # addon uninstall.sh + launchd teardown + disable
#   bash scripts/addons.sh enable <id>       # enable only (touch file)
#   bash scripts/addons.sh disable <id>      # remove enable touch file + uninstall schedule
#   bash scripts/addons.sh configure <id>    # open user config file in $EDITOR
#   bash scripts/addons.sh onboard <id>      # run an addon's interactive onboarding step
#   bash scripts/addons.sh check [<id>]      # runtime health of enabled add-ons
#   bash scripts/addons.sh test [<id>]       # validate manifest + health, per add-on or all
#   bash scripts/addons.sh clients [--write] # render/refresh the client capability matrix (clients.md)
#   bash scripts/addons.sh search [term]                  # merged view: bundled + local + registries
#   bash scripts/addons.sh install <registry>/<id>        # pin a specific registry (dupe override)
#   bash scripts/addons.sh update <id>                    # fetch newer version from registries (explicit)
#   bash scripts/addons.sh new <id> [name]                # scaffold own addon into local/addons/<id>/
#   bash scripts/addons.sh registry list|add <n> <url>|remove <n>   # manage registries (default built-in)
#   bash scripts/addons.sh registry default [<url>|reset]  # per-machine default registry (dev: point at Gitea)
#   bash scripts/addons.sh status --remote                # adds UPDATE column (fetches indexes)
# Env: ADDONS_REGISTRY, ADDONS_STATE (override roots, used by tests),
#      ADDONS_DRY_RUN=1 (echo install cmd), ADDONS_ASSUME_YES=1 (non-TTY enable),
#      ADDONS_PURGE=1 (uninstall also removes local/addons/<id>/ config dir),
#      ADDONS_REGISTRIES_FILE, ADDONS_DEFAULT_URL, ADDONS_FETCH_TIMEOUT.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REGISTRY="${ADDONS_REGISTRY:-system/addons}"
STATE="${ADDONS_STATE:-local/addons}"
REGISTRIES_FILE="${ADDONS_REGISTRIES_FILE:-local/addons/registries.json}"
DEFAULT_REGISTRY_NAME="default"
# Which registry is "default" on THIS machine. Precedence:
#   1. ADDONS_DEFAULT_URL env (one-shot override)
#   2. local/addons/default-url (per-machine preference; never shipped — local/
#      is excluded from releases, so this never changes the default for others)
#   3. the baked-in public GitHub default (what ships to everyone)
# Devs point this at their Gitea registry; the shipped default stays GitHub.
DEFAULT_URL_FILE="${ADDONS_DEFAULT_URL_FILE:-local/addons/default-url}"
BAKED_DEFAULT_URL="https://raw.githubusercontent.com/frontmatters/agentbrain-registry/main/index.json"
if [ -n "${ADDONS_DEFAULT_URL:-}" ]; then
	DEFAULT_REGISTRY_URL="$ADDONS_DEFAULT_URL"
elif [ -s "$DEFAULT_URL_FILE" ]; then
	DEFAULT_REGISTRY_URL="$(tr -d '[:space:]' <"$DEFAULT_URL_FILE")"
else
	DEFAULT_REGISTRY_URL="$BAKED_DEFAULT_URL"
fi
# Used by registry_candidates/search/install for TSV field splitting.
# shellcheck disable=SC2034
TAB="$(printf '\t')"

# Read a top-level frontmatter scalar from a manifest.
_field() {
	awk -v key="$2" '
		/^---[[:space:]]*$/ { fm++; next }
		fm==1 && $0 ~ "^"key":" {
			sub("^"key":[[:space:]]*", ""); sub(/[[:space:]]*#.*$/, ""); print; exit
		}
	' "$1"
}

# Read support level for a client (full|rules|none|unknown).
_support() {
	local lvl
	lvl=$(awk -v c="$2" '
		/^---[[:space:]]*$/ { fm++; next }
		fm==1 && /^support:[[:space:]]*$/ { insup=1; next }
		fm==1 && insup && /^[^[:space:]]/ { insup=0 }
		fm==1 && insup && $0 ~ "^[[:space:]]+"c":" {
			sub("^[[:space:]]+"c":[[:space:]]*",""); sub(/[[:space:]]*#.*$/,""); print; exit
		}
	' "$1")
	echo "${lvl:-unknown}"
}

# Read a frontmatter list field. Supports inline ([a, b]) and block (- a) YAML.
# Prints items space-separated on one line.
_list() {
	awk -v key="$2" '
		/^---[[:space:]]*$/ { fm++; next }
		fm==1 && $0 ~ "^"key":[[:space:]]*\\[" {
			line=$0; sub("^"key":[[:space:]]*\\[","",line); sub("\\].*$","",line);
			gsub(/[[:space:]]/,"",line); gsub(/,/," ",line); print line; exit
		}
		fm==1 && $0 ~ "^"key":[[:space:]]*$" { inblk=1; next }
		fm==1 && inblk && /^[[:space:]]*-[[:space:]]/ {
			sub(/^[[:space:]]*-[[:space:]]*/,""); sub(/[[:space:]]*#.*$/,""); out=(out==""?$0:out" "$0); next
		}
		fm==1 && inblk && /^[^[:space:]-]/ { inblk=0 }
		END { if (out != "") print out }
	' "$1"
}

is_enabled() { [ -f "$STATE/$1/enabled" ]; }

# ---- dual-root discovery ----
# Bundled addons live in $REGISTRY (system/addons); user-installed/downloaded
# and self-made addons live in $STATE (local/addons). A directory is an addon
# iff it contains a manifest.md. For the same id the local copy wins: it is
# the user's installed version, and a framework update can never clobber it.

manifest_path() {
	if [ -f "$STATE/$1/manifest.md" ]; then
		echo "$STATE/$1/manifest.md"
	else
		echo "$REGISTRY/$1/manifest.md"
	fi
}

addon_dir() { dirname "$(manifest_path "$1")"; }

# Source label for an id: local | bundled.
addon_source() {
	if [ -f "$STATE/$1/manifest.md" ]; then echo local; else echo bundled; fi
}

# Bare hex SHA-256 of a file. Portable: shasum (always on macOS) or sha256sum
# (the GNU coreutils name, common on Linux). Errors loudly if neither exists.
sha256_hex() {
	if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
	else echo "no sha256 tool (need shasum or sha256sum)" >&2; return 1; fi
}

# Emit every addon id exactly once (local overrides bundled), skipping _template.
all_addon_ids() {
	local m
	for m in "$STATE"/*/manifest.md "$REGISTRY"/*/manifest.md; do
		[ -f "$m" ] || continue
		basename "$(dirname "$m")"
	done | grep -v '^_template$' | sort -u
}

require_addon() {
	local id="$1"
	if [ ! -f "$(manifest_path "$id")" ]; then
		echo "Unknown add-on: $id (no $(manifest_path "$id"))" >&2
		return 1
	fi
}

# Plain status is offline by design (no network on every call). --remote
# additionally fetches all registry indexes once and fills the UPDATE column.
cmd_status() {
	local remote=0 cands=""
	[ "${1:-}" = "--remote" ] && remote=1
	if [ "$remote" -eq 1 ]; then
		need_jq || return 1
		cands="$(registry_candidates "")"
	fi
	local id m name state ver src upd best bver breg
	if [ "$remote" -eq 1 ]; then
		printf '%-22s %-9s %-10s %-8s %-22s %s\n' "ID" "VERSION" "STATE" "SOURCE" "UPDATE" "NAME"
	else
		printf '%-22s %-9s %-10s %-8s %s\n' "ID" "VERSION" "STATE" "SOURCE" "NAME"
	fi
	for id in $(all_addon_ids); do
		m="$(manifest_path "$id")"
		if [ -z "$(_field "$m" id)" ]; then
			echo "WARN: malformed manifest: $m — run scripts/check-addons.sh" >&2
			continue
		fi
		name="$(_field "$m" name)"
		ver="$(_field "$m" version)"
		src="$(addon_source "$id")"
		if is_enabled "$id"; then state="enabled"; else state="available"; fi
		if [ "$remote" -eq 1 ]; then
			upd="-"
			best="$(printf '%s\n' "$cands" | awk -F'\t' -v i="$id" '$2 == i' | sort -t"$TAB" -k3,3V | tail -1)"
			if [ -n "$best" ]; then
				bver="$(printf '%s' "$best" | cut -f3)"
				breg="$(printf '%s' "$best" | cut -f1)"
				if [ -n "$ver" ] && [ "$(printf '%s\n%s\n' "$ver" "$bver" | sort -V | tail -1)" != "$ver" ]; then
					upd="$bver ($breg)"
				fi
			fi
			printf '%-22s %-9s %-10s %-8s %-22s %s\n' "$id" "${ver:--}" "$state" "$src" "$upd" "$name"
		else
			printf '%-22s %-9s %-10s %-8s %s\n' "$id" "${ver:--}" "$state" "$src" "$name"
		fi
	done
}

# Re-sync addon-provided skills into each detected agent's skills dir. An addon
# that ships a SKILL.md becomes a usable skill while enabled, and is unlinked on
# disable. Best-effort: never let a skill-sync hiccup fail enable/disable itself.
sync_addon_skills() {
	# Surface failures (broken symlink, permissions, disk full) instead of
	# hiding them — an enabled addon whose skill silently failed to link is a
	# trap. Never fail enable/disable itself over a sync hiccup, though.
	local err
	if ! err="$(ADDONS_STATE="$STATE" bash "$ROOT_DIR/scripts/setup-skills.sh" sync-addons 2>&1 >/dev/null)"; then
		echo "WARN: addon skill sync had issues${err:+: $err}" >&2
	fi
}

cmd_enable() {
	local id="${1:?usage: enable <id>}"
	require_addon "$id" || return 1
	mkdir -p "$STATE/$id"
	: > "$STATE/$id/enabled"
	echo "Enabled $id"
	sync_addon_skills
}

cmd_disable() {
	local id="${1:?usage: disable <id>}"
	rm -f "$STATE/$id/enabled"
	echo "Disabled $id"
	sync_addon_skills
	# If this addon had a scheduled launchd job, tear it down too.
	if [ -f "$(manifest_path "$id" 2>/dev/null)" ] && has_schedule "$id" 2>/dev/null \
			&& [ "$(uname -s)" = "Darwin" ]; then
		bash "$ROOT_DIR/scripts/setup-addon-launchd.sh" uninstall "$id" 2>/dev/null || true
	fi
}

privacy_text() {
	case "$1" in
		local)
			echo "Nothing leaves your machine (incl. localhost services like Ollama/MCP)." ;;
		local-only)
			echo "Strict-local: outputs stay on this machine AND are not synced across devices (gitea-sync excludes them). Use for per-machine state, secrets, or recordings that shouldn't propagate." ;;
		sends-docs)
			echo "Docs and images are sent to your configured LLM. Code is processed locally." ;;
		sends-all)
			echo "Docs, images AND code are sent to your configured LLM." ;;
		*)
			echo "Unknown privacy level: $1" ;;
	esac
}

# Returns 0 to proceed, 3 to abort. Honours ADDONS_ASSUME_YES and TTY.
cmd_privacy() {
	local id="${1:?usage: _privacy <id>}"
	require_addon "$id" || return 1
	local level; level="$(_field "$(manifest_path "$id")" privacy)"
	echo "privacy: $level"
	echo "  $(privacy_text "$level")"
	if [ "${ADDONS_ASSUME_YES:-0}" = "1" ]; then return 0; fi
	if [ ! -t 0 ]; then
		echo "Refusing to enable non-interactively. Re-run in a terminal or set ADDONS_ASSUME_YES=1." >&2
		return 3
	fi
	read -r -p "Enable $id? [y/N] " ans
	case "$ans" in y|Y|yes|YES) return 0 ;; *) echo "Aborted."; return 3 ;; esac
}

run_install_cmd() {
	local id="$1" cmd="$2"
	# Downloaded/own addons live under local/addons; their manifests reference
	# the canonical system/addons path — rewrite to the addon's real dir.
	local dir; dir="$(addon_dir "$id")"
	cmd="${cmd//system\/addons\/$id/$dir}"
	if [ "${ADDONS_DRY_RUN:-0}" = "1" ]; then
		echo "[dry-run] $cmd"
	else
		bash -c "$cmd"
	fi
}

# Local/bundled install lifecycle (privacy gate → install cmd → enable → check).
# Run the install step for an addon's install_method. Idempotent by contract.
# Shared by first-install (install_local) and post-download update (cmd_update),
# so the two paths can never diverge on how an addon gets installed.
_run_install_step() {
	local id="$1"
	local m; m="$(manifest_path "$id")"
	local method; method="$(_field "$m" install_method)"
	local cmd; cmd="$(_field "$m" install)"
	case "$method" in
		self)
			[ -n "$cmd" ] && run_install_cmd "$id" "$cmd" ;;
		ai-driven)
			echo "ai-driven install: open the per-client INSTALL.md and follow it:"
			echo "  $cmd" ;;
		config-entry)
			echo "config-entry install: addons.sh will add a config entry (see SKILL.md)."
			[ -n "$cmd" ] && run_install_cmd "$id" "$cmd" ;;
		*) echo "Unknown install_method: $method" >&2; return 1 ;;
	esac
}

install_local() {
	local id="$1"
	require_addon "$id" || return 1

	cmd_privacy "$id" || return $?      # privacy gate (may abort with 3)
	_run_install_step "$id" || return 1

	cmd_enable "$id"
	cmd_check "$id" || echo "Note: $id enabled but health check reported issues (see above)."

	# Schedule (opt-in): if manifest declares one, offer to install the launchd job.
	_schedule_install_prompt "$id"

	# Onboarding (opt-in): if manifest declares an onboard: step, offer to run it.
	_onboard_install_prompt "$id"
}

# Download a packaged addon zip, verify sha256, unpack into local/addons/<id>/.
download_addon() {
	local id="$1" ver="$2" url="$3" sha="$4"
	local tmp; tmp="$(mktemp -d)"
	local zip="$tmp/addon.zip"
	if ! curl -fsSL --max-time "${ADDONS_FETCH_TIMEOUT:-60}" -o "$zip" "$url"; then
		echo "Download failed: $url" >&2
		rm -rf "$tmp"; return 1
	fi
	local got; got="$(sha256_hex "$zip")"
	if [ "$got" != "$sha" ]; then
		echo "sha256 mismatch for $id ($url)" >&2
		echo "  expected: $sha" >&2
		echo "  got:      $got" >&2
		rm -rf "$tmp"; return 1
	fi
	(cd "$tmp" && unzip -q addon.zip)
	if [ ! -f "$tmp/$id/manifest.md" ]; then
		echo "Archive does not contain $id/manifest.md" >&2
		rm -rf "$tmp"; return 1
	fi
	mkdir -p "$STATE/$id"
	cp -R "$tmp/$id/." "$STATE/$id/"
	rm -rf "$tmp"
	echo "Unpacked $id $ver into $STATE/$id"
}

# Resolve an id across registries and download it. Rules (see spec §5):
# newest version wins within one registry; the default registry wins over
# third-party for the same id (dependency-confusion guard); an explicit
# <registry>/<id> pin overrides everything.
install_from_registry() {
	local id="$1" pin="${2:-}"
	need_jq || return 1
	local cands
	cands="$(registry_candidates "$id")"
	if [ -n "$pin" ]; then
		cands="$(printf '%s\n' "$cands" | awk -F'\t' -v r="$pin" '$1 == r')"
	fi
	if [ -z "$cands" ]; then
		echo "Add-on '$id' not found${pin:+ in registry \"$pin\"} in any configured registry" >&2
		echo "  (addons.sh search $id / addons.sh registry list)" >&2
		return 1
	fi
	if [ -z "$pin" ] && printf '%s\n' "$cands" | \
			awk -F'\t' -v r="$DEFAULT_REGISTRY_NAME" '$1 == r { f = 1 } END { exit !f }'; then
		cands="$(printf '%s\n' "$cands" | awk -F'\t' -v r="$DEFAULT_REGISTRY_NAME" '$1 == r')"
	fi
	local chosen
	chosen="$(printf '%s\n' "$cands" | sort -t"$TAB" -k3,3V | tail -1)"
	local reg ver name url sha
	IFS="$TAB" read -r reg id ver name url sha <<EOF2
$chosen
EOF2
	echo "Installing $id $ver from registry '$reg'"
	download_addon "$id" "$ver" "$url" "$sha"
}

# Explicitly fetch a newer version from the registries. Never automatic.
cmd_update() {
	local id="${1:?usage: update <id>}"
	need_jq || return 1
	require_addon "$id" || return 1
	local cur; cur="$(_field "$(manifest_path "$id")" version)"
	local cands
	cands="$(registry_candidates "$id")"
	[ -n "$cands" ] || { echo "No configured registry carries '$id'" >&2; return 1; }
	if printf '%s\n' "$cands" | awk -F'\t' -v r="$DEFAULT_REGISTRY_NAME" '$1 == r { f = 1 } END { exit !f }'; then
		cands="$(printf '%s\n' "$cands" | awk -F'\t' -v r="$DEFAULT_REGISTRY_NAME" '$1 == r')"
	fi
	local chosen reg ver name url sha
	chosen="$(printf '%s\n' "$cands" | sort -t"$TAB" -k3,3V | tail -1)"
	IFS="$TAB" read -r reg id ver name url sha <<EOF2
$chosen
EOF2
	if [ "$(printf '%s\n%s\n' "$cur" "$ver" | sort -V | tail -1)" = "$cur" ]; then
		echo "$id is up-to-date ($cur; registry '$reg' has $ver)"
		return 0
	fi
	echo "Updating $id $cur -> $ver (registry '$reg')"
	download_addon "$id" "$ver" "$url" "$sha"
	# New files alone can leave install hooks/config stale and the skill links
	# pointing at the old version — re-run the new version's install step
	# (idempotent by contract) and restore enabled state (re-enable resyncs skills).
	local was_enabled=0
	if is_enabled "$id"; then was_enabled=1; fi
	_run_install_step "$id" || { echo "WARN: $id install step failed after update" >&2; return 1; }
	if [ "$was_enabled" = 1 ]; then cmd_enable "$id"; fi
	echo "Updated $id to $ver"
}

cmd_install() {
	local spec="${1:?usage: install <id> | install <registry>/<id>}"
	local pin="" id="$spec"
	case "$spec" in
		*/*) pin="${spec%%/*}"; id="${spec#*/}" ;;
	esac
	# Resolution order: local/bundled first; registries only when unknown here.
	# An explicit <registry>/<id> pin always goes to that registry.
	if [ -z "$pin" ] && [ -f "$(manifest_path "$id")" ]; then
		install_local "$id"
		return $?
	fi
	install_from_registry "$id" "$pin" || return $?
	install_local "$id"
}

# Returns 0 if manifest has a `schedule:` block, 1 otherwise.
has_schedule() {
	local m; m="$(manifest_path "$1")"
	grep -qE "^schedule:[[:space:]]*$" "$m"
}

# Prompt + (opt-in) install of the launchd job for an addon with a `schedule:` block.
# Idempotent: skips silently when no schedule, when not on macOS, or when user declines.
# Respects ADDONS_ASSUME_YES=1 for non-interactive flows (CI, scripts).
_schedule_install_prompt() {
	local id="$1"
	has_schedule "$id" || return 0
	[ "$(uname -s)" = "Darwin" ] || {
		echo "$id has a schedule but launchd is macOS-only — skipping" >&2
		return 0
	}
	local m; m="$(manifest_path "$id")"
	local cron
	cron=$(awk '
		/^---[[:space:]]*$/{fm++;next}
		fm==1 && /^schedule:[[:space:]]*$/{ins=1;next}
		fm==1 && ins && /^[^[:space:]]/{ins=0}
		fm==1 && ins && /^[[:space:]]+cron:/{
			sub(/.*cron:[[:space:]]*"?/,""); sub(/"[[:space:]]*$/,""); print; exit
		}' "$m")
	echo
	echo "$id declares a schedule (cron: '$cron')."
	local ans
	if [ "${ADDONS_ASSUME_YES:-0}" = "1" ]; then
		ans=y
	elif [ ! -t 0 ]; then
		echo "  Non-interactive shell — skipping. Install later with:" >&2
		echo "    bash scripts/setup-addon-launchd.sh install $id" >&2
		return 0
	else
		read -r -p "Install the launchd job now? [y/N] " ans
	fi
	case "$ans" in
		y|Y|yes|YES)
			bash "$ROOT_DIR/scripts/setup-addon-launchd.sh" install "$id"
			;;
		*)
			echo "  Skipped. Install later with:"
			echo "    bash scripts/setup-addon-launchd.sh install $id"
			;;
	esac
}

# Returns 0 if manifest has an `onboard:` block, 1 otherwise.
has_onboard() {
	local m; m="$(manifest_path "$1")"
	grep -qE "^onboard:[[:space:]]*$" "$m"
}

# Read a scalar (run/requires/prompt) from the onboard: block.
_onboard_field() {
	local m="$1" key="$2"
	awk -v k="$key" '
		/^---[[:space:]]*$/{fm++;next}
		fm==1 && /^onboard:[[:space:]]*$/{o=1;next}
		fm==1 && o && /^[^[:space:]]/{o=0}
		fm==1 && o && $0 ~ "^[[:space:]]+"k":"{
			sub("^[[:space:]]+"k":[[:space:]]*",""); sub(/[[:space:]]*#.*$/,""); gsub(/"/,""); print; exit
		}' "$m"
}

# Offer to run an addon's onboarding step. Mirrors _schedule_install_prompt:
# declarative manifest hook + TTY-gated prompt + graceful skip with a run-later hint.
# Optional `requires:` gates the offer via platform_has (must be a known capability).
# Honours ADDONS_ASSUME_YES=1 for non-interactive flows.
_onboard_install_prompt() {
	local id="$1"
	has_onboard "$id" || return 0
	local m; m="$(manifest_path "$id")"
	local run req prompt
	run="$(_onboard_field "$m" run)"
	req="$(_onboard_field "$m" requires)"
	prompt="$(_onboard_field "$m" prompt)"
	[ -n "$run" ] || return 0
	if [ -n "$req" ]; then
		if [ ! -f "$ROOT_DIR/scripts/platform.sh" ]; then
			echo "$id onboarding: cannot verify '$req' (platform.sh missing) — skipping. Run later: bash scripts/addons.sh onboard $id" >&2
			return 0
		fi
		# shellcheck source=/dev/null
		. "$ROOT_DIR/scripts/platform.sh"
		if ! platform_has "$req"; then
			echo "$id onboarding needs '$req' (not available) — skipping. Run later: bash scripts/addons.sh onboard $id" >&2
			return 0
		fi
	fi
	echo
	echo "${prompt:-$id offers an onboarding step.}"
	local ans
	if [ "${ADDONS_ASSUME_YES:-0}" = "1" ]; then
		ans=y
	elif [ ! -t 0 ]; then
		echo "  Non-interactive shell — skipping. Run later with:" >&2
		echo "    bash scripts/addons.sh onboard $id" >&2
		return 0
	else
		read -r -p "Run it now? [y/N] " ans
	fi
	case "$ans" in
		y|Y|yes|YES) run_install_cmd "$id" "$run" ;;
		*) echo "  Skipped. Run later with: bash scripts/addons.sh onboard $id" ;;
	esac
}

# Runtime health of one or all enabled add-ons. Returns 1 if any enabled add-on is broken.
cmd_check() {
	local only="${1:-}"
	local rc=0 m id cmd _id
	for _id in $(all_addon_ids); do
		m="$(manifest_path "$_id")"
		[ -f "$m" ] || continue
		id="$(_field "$m" id)"
		[ -n "$id" ] || id="$_id"
		[ -n "$only" ] && [ "$only" != "$id" ] && continue
		is_enabled "$id" || continue
		cmd="$(_field "$m" command)"
		if [ -z "$cmd" ]; then
			# ai-driven/plugin add-ons have no CLI binary to probe — nothing to fail on.
			echo "ok   $id (no CLI command to check; plugin/ai-driven add-on)"
		elif command -v "$cmd" >/dev/null 2>&1; then
			echo "ok   $id ($cmd found)"
		else
			echo "FAIL $id (command '$cmd' not found but add-on is enabled)" >&2
			rc=1
		fi
	done
	return $rc
}

# Run an add-on's own test suite (its manifest `test:` field) from the add-on dir.
# Skips (returns 0) when no `test:` field or when the suite runtime is unavailable.
# Returns the suite's exit code otherwise.
run_addon_suite() {
	local m="$1" id="$2"
	local suite runtime addon_dir
	suite="$(_field "$m" test)"
	[ -n "$suite" ] || return 0
	runtime="${suite%% *}"
	if ! command -v "$runtime" >/dev/null 2>&1; then
		echo "info $id: test suite present but '$runtime' not installed — skipping suite"
		return 0
	fi
	addon_dir="$(dirname "$m")"
	echo "-- running $id suite: $suite"
	if ( cd "$addon_dir" && bash -c "$suite" ); then
		echo "ok   $id: test suite passed"
		return 0
	else
		echo "FAIL $id: test suite failed" >&2
		return 1
	fi
}

# Test one add-on (or all): static manifest validation + runtime health.
# Static validation always runs. Runtime health runs when enabled; otherwise it is
# informational so a manifest can be validated without installing the tool.
cmd_test() {
	local only="${1:-}"
	local rc=0 m id cmd _id
	for _id in $(all_addon_ids); do
		m="$(manifest_path "$_id")"
		[ -f "$m" ] || continue
		id="$(_field "$m" id)"
		[ -n "$id" ] || id="$_id"
		[ -n "$only" ] && [ "$only" != "$id" ] && continue
		echo "== test $id =="
		# Validate against the addon's OWN registry root (system/addons or
		# local/addons) so local/downloaded addons aren't silently skipped.
		if ADDONS_CHECK_REGISTRY="$(dirname "$(addon_dir "$_id")")" bash scripts/check-addons.sh "$id"; then
			echo "ok   $id: manifest valid"
		else
			echo "FAIL $id: manifest invalid" >&2; rc=1
		fi
		cmd="$(_field "$m" command)"
		if is_enabled "$id"; then
			cmd_check "$id" || rc=1
		elif [ -z "$cmd" ]; then
			echo "info $id: ai-driven/plugin add-on, no CLI to probe — static validation only"
		elif command -v "$cmd" >/dev/null 2>&1; then
			echo "ok   $id: '$cmd' available (not enabled)"
		else
			echo "info $id: not enabled and '$cmd' not installed — static validation only"
		fi
		# Optional per-add-on test suite (`test:` field). Run it from the add-on dir
		# when the suite's runtime (first token of the command) is on PATH; otherwise
		# fall back to the static validation above.
		run_addon_suite "$m" "$id" || rc=1
	done
	[ "$rc" -eq 0 ] && echo "PASS" || echo "FAIL (see above)" >&2
	return $rc
}

# Run an addon's onboarding step directly (re-run, or first-run from the CLI).
cmd_onboard() {
	local id="${1:?usage: onboard <id>}"
	require_addon "$id" || return 1
	if ! has_onboard "$id"; then
		echo "$id has no onboard: step"
		return 0
	fi
	local m run; m="$(manifest_path "$id")"; run="$(_onboard_field "$m" run)"
	[ -n "$run" ] || { echo "$id onboard: block has no run: command" >&2; return 1; }
	run_install_cmd "$id" "$run"
}

# Open the user's config file for an addon in $EDITOR (fallback: vi).
# Convention: user config lives at local/addons/<id>/, file name varies per addon
# (config.json, channels.json, etc.). We auto-detect; if multiple, prompt.
cmd_configure() {
	local id="${1:?usage: configure <id>}"
	require_addon "$id" || return 1
	local cfg_dir="$STATE/$id"
	if [ ! -d "$cfg_dir" ]; then
		echo "No config dir for $id at $cfg_dir — install the addon first" >&2
		return 1
	fi
	# Match common config file extensions; ignore dot-files like enabled/state,
	# plus by-name runtime artefacts (state/stats/cache/lock/log) that share the
	# .json extension with config but aren't user-editable.
	local files
	files=$(find "$cfg_dir" -maxdepth 1 -type f \
		\( -name "*.json" -o -name "*.yaml" -o -name "*.yml" \
		   -o -name "*.toml" -o -name "*.conf" -o -name "*.ini" \) \
		-not -name "state.*" -not -name "stats.*" \
		-not -name "*.lock" -not -name "*.log" -not -name "*.cache" \
		2>/dev/null)
	if [ -z "$files" ]; then
		echo "No config file found in $cfg_dir for $id" >&2
		echo "  (the addon may not have user config, or it lives elsewhere — see manifest)" >&2
		return 1
	fi
	local target
	local count
	count=$(printf "%s\n" "$files" | wc -l | tr -d ' ')
	if [ "$count" = "1" ]; then
		target="$files"
	else
		echo "Multiple config files for $id:"
		printf "%s\n" "$files" | nl
		if [ ! -t 0 ]; then
			echo "Non-interactive shell — specify file explicitly via \$EDITOR" >&2
			return 1
		fi
		read -r -p "Which one to edit? (number) " choice
		[[ "$choice" =~ ^[0-9]+$ ]] || { echo "Not a number: $choice" >&2; return 1; }
		target=$(printf "%s\n" "$files" | sed -n "${choice}p")
	fi
	[ -f "$target" ] || { echo "Not a file: $target" >&2; return 1; }
	echo "Opening $target in ${EDITOR:-vi}…"
	"${EDITOR:-vi}" "$target"
}

# Generate the client capability matrix (clients.md) from all manifests' support:
# blocks. Columns are the canonical client set (kept in sync with check-addons.sh).
# Frontmatter of the existing clients.md is preserved verbatim (its `id:` is
# validated by a note-id hook and must never be regenerated). With --write the
# file is rewritten in place; otherwise the rendered content is printed (used by
# check-addons.sh as a drift check).
CLIENTS_FILE="$REGISTRY/clients.md"
CLIENTS_COLS="claude gemini opencode pi cursor copilot windsurf cline hermes"

# Literal backticks in the printf format strings are intentional markdown.
# shellcheck disable=SC2016
cmd_clients() {
	local write=0
	[ "${1:-}" = "--write" ] && write=1
	local m id col lvl row
	# Preserve the existing frontmatter block (everything up to and incl. the
	# second '---'). The id field is hook-validated and must stay byte-identical.
	local front
	front="$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; print; if(n==2) exit; next} n>=1{print}' "$CLIENTS_FILE")"
	{
		printf '%s\n\n' "$front"
		printf '# Add-on Client Capability Matrix\n\n'
		printf "Support levels per client (from each add-on's \`manifest.md\` \`support:\` block).\n"
		printf "The \`os\` column is the platform axis (\`os:\` field); absent = \`any\` (cross-platform).\n\n"
		printf '> Generated by `bash scripts/addons.sh clients --write`. Do not edit by hand.\n\n'
		printf '| Add-on | os'
		for col in $CLIENTS_COLS; do printf ' | %s' "$col"; done
		printf ' |\n'
		printf '| --- | ---'
		for col in $CLIENTS_COLS; do printf ' | ---'; done
		printf ' |\n'
		for m in "$REGISTRY"/*/manifest.md; do
			[ -f "$m" ] || continue
			[ "$(basename "$(dirname "$m")")" = "_template" ] && continue
			id="$(_field "$m" id)"
			[ -n "$id" ] || continue
			row="| $id"
			osv="$(_field "$m" os)"; [ -n "$osv" ] || osv="any"
			row="$row | $osv"
			for col in $CLIENTS_COLS; do
				lvl="$(_support "$m" "$col")"
				row="$row | $lvl"
			done
			printf '%s |\n' "$row"
		done | sort
		printf '\n'
		printf 'Legend: `full` = skill + hooks · `rules` = mention in rules/shared config ·\n'
		printf '`none` = unsupported · `unknown` = untested.\n\n'
		printf 'Windsurf and Cline have no skill mechanism, so they are always `rules`.\n'
	} > "$REGISTRY/.clients.gen.$$"

	if [ "$write" -eq 1 ]; then
		mv "$REGISTRY/.clients.gen.$$" "$CLIENTS_FILE"
		echo "Wrote $CLIENTS_FILE"
	else
		cat "$REGISTRY/.clients.gen.$$"
		rm -f "$REGISTRY/.clients.gen.$$"
	fi
}

# Fully uninstall an addon: run its own uninstall.sh (if present), tear down
# any launchd job, and remove the enabled marker. With ADDONS_PURGE=1 also
# removes the local/addons/<id>/ config directory.
cmd_uninstall() {
	local id="${1:?usage: uninstall <id>}"
	require_addon "$id" || return 1

	local addon_dir; addon_dir="$(addon_dir "$id")"

	# Run the addon's own uninstall script if it exists.
	if [ -f "$addon_dir/uninstall.sh" ]; then
		echo "Running $id/uninstall.sh…"
		bash "$addon_dir/uninstall.sh" || echo "WARN: $id/uninstall.sh exited non-zero (continuing)" >&2
	fi

	# Tear down launchd job on macOS when the addon declares a schedule.
	if has_schedule "$id" && [ "$(uname -s)" = "Darwin" ]; then
		bash "$ROOT_DIR/scripts/setup-addon-launchd.sh" uninstall "$id" 2>/dev/null || true
	fi

	# Remove enabled marker, then unlink any skill this addon had installed
	# (true inverse of install/enable, which links it).
	rm -f "$STATE/$id/enabled"
	sync_addon_skills

	# With ADDONS_PURGE=1: also remove the entire local config directory.
	if [ "${ADDONS_PURGE:-0}" = "1" ] && [ -d "$STATE/$id" ]; then
		rm -rf "${STATE:?}/$id"
		echo "Purged $id config from $STATE/$id"
	fi

	echo "Uninstalled $id"
}

# Scaffold a brand-new addon into local/addons/<id>/ from the _template.
# Own/experimental addons live in the local layer: outside git and releases,
# promotable to system/addons later via the promote flow.
cmd_new() {
	local id="${1:?usage: new <id> [name]}"; shift || true
	local name="${*:-$id}"
	if ! printf '%s' "$id" | grep -qE '^[a-z0-9-]+$'; then
		echo "Addon id must be lowercase kebab-case: $id" >&2
		return 1
	fi
	local target="$STATE/$id"
	if [ -f "$target/manifest.md" ] || [ -f "$REGISTRY/$id/manifest.md" ]; then
		echo "Addon already exists: $id" >&2
		return 1
	fi
	mkdir -p "$target"
	cp -R "$REGISTRY/_template/." "$target/"
	local f
	for f in "$target/manifest.md" "$target/README.md"; do
		[ -f "$f" ] || continue
		sed -i.bak "s/your-addon-id/$id/g; s/Your Addon Name/$name/g" "$f"
	done
	rm -f "$target"/*.bak
	echo "Scaffolded $target — edit manifest.md and README.md, then: addons.sh install $id"
}

# ---- registries (Docker-style: default built-in, own registries addable) ----
need_jq() {
	command -v jq >/dev/null 2>&1 && return 0
	echo "jq is required for registry commands (install: brew install jq)" >&2
	return 1
}

# Seed the registries file with an empty named-registry list on first mutation.
# The default registry is NOT stored here — it is always resolved dynamically
# (see registries_list), so re-pointing it always takes effect and never goes
# stale once you add other registries.
_registries_init() {
	[ -f "$REGISTRIES_FILE" ] && return 0
	mkdir -p "$(dirname "$REGISTRIES_FILE")"
	jq -n '{registries: []}' > "$REGISTRIES_FILE"
}

# Print "name<TAB>url" per registry: the dynamic default FIRST, then the named
# registries from the file (excluding any legacy "default" entry). Default is
# always present (it has env/file/default fallbacks), so this never yields zero.
registries_list() {
	printf '%s\t%s\n' "$DEFAULT_REGISTRY_NAME" "$DEFAULT_REGISTRY_URL"
	if [ -s "$REGISTRIES_FILE" ] && jq -e '.registries | type == "array"' "$REGISTRIES_FILE" >/dev/null 2>&1; then
		jq -r --arg off "$DEFAULT_REGISTRY_NAME" \
			'.registries[] | select(.name != $off) | "\(.name)\t\(.url)"' "$REGISTRIES_FILE"
	elif [ -f "$REGISTRIES_FILE" ]; then
		echo "WARN: $REGISTRIES_FILE is empty/invalid — ignoring (using default only)" >&2
	fi
}

cmd_registry() {
	need_jq || return 1
	local sub="${1:-list}"; shift || true
	local tmp
	case "$sub" in
		list)
			printf '%-16s %s\n' "NAME" "URL"
			registries_list | awk -F'\t' '{ printf "%-16s %s\n", $1, $2 }'
			;;
		add)
			local name="${1:?usage: registry add <name> <url>}"
			local url="${2:?usage: registry add <name> <url>}"
			if [ "$name" = "$DEFAULT_REGISTRY_NAME" ]; then
				echo "'$DEFAULT_REGISTRY_NAME' is managed separately — use 'registry default <url>'." >&2
				return 1
			fi
			if ! printf '%s' "$name" | grep -qE '^[a-z0-9-]+$'; then
				echo "Invalid registry name (lowercase kebab-case): $name" >&2
				return 1
			fi
			_registries_init
			if registries_list | cut -f1 | grep -qx "$name"; then
				echo "Registry '$name' already exists (remove it first)" >&2
				return 1
			fi
			tmp="$(mktemp)"
			jq --arg n "$name" --arg u "$url" '.registries += [{name: $n, url: $u}]' \
				"$REGISTRIES_FILE" > "$tmp" && mv "$tmp" "$REGISTRIES_FILE"
			echo "Added registry $name -> $url"
			;;
		remove)
			local name="${1:?usage: registry remove <name>}"
			if [ "$name" = "$DEFAULT_REGISTRY_NAME" ]; then
				echo "Cannot remove '$DEFAULT_REGISTRY_NAME' — use 'registry default reset' to restore the default." >&2
				return 1
			fi
			_registries_init
			tmp="$(mktemp)"
			jq --arg n "$name" '.registries |= map(select(.name != $n))' \
				"$REGISTRIES_FILE" > "$tmp" && mv "$tmp" "$REGISTRIES_FILE"
			echo "Removed registry $name"
			;;
		default)
			# Show or set the per-machine "default" registry URL. Persisted to
			# local/addons/default-url (never shipped). With no arg, prints the
			# active URL and where it comes from. 'reset' restores the default.
			if [ $# -eq 0 ]; then
				local origin="baked default (GitHub)"
				[ -s "$DEFAULT_URL_FILE" ] && origin="$DEFAULT_URL_FILE"
				[ -n "${ADDONS_DEFAULT_URL:-}" ] && origin="ADDONS_DEFAULT_URL env"
				echo "default: $DEFAULT_REGISTRY_URL"
				echo "  source: $origin"
				return 0
			fi
			if [ "$1" = "reset" ]; then
				rm -f "$DEFAULT_URL_FILE"
				echo "Reset default registry to the baked default: $BAKED_DEFAULT_URL"
				return 0
			fi
			mkdir -p "$(dirname "$DEFAULT_URL_FILE")"
			printf '%s\n' "$1" > "$DEFAULT_URL_FILE"
			echo "Set default registry (this machine) -> $1"
			echo "  stored in $DEFAULT_URL_FILE (per-machine; the shipped default stays GitHub)"
			;;
		*) echo "usage: registry list | add <name> <url> | remove <name> | default [<url>|reset]" >&2; return 2 ;;
	esac
}

# Fetch a registry index over https:// or file:// (curl handles both).
fetch_index() {
	curl -fsSL --max-time "${ADDONS_FETCH_TIMEOUT:-10}" "$1"
}

# Emit candidates across all configured registries, one line per match:
# "registry<TAB>id<TAB>version<TAB>name<TAB>url<TAB>sha256"
# $1: addon id filter ("" = all). Unreachable registries warn and are skipped.
registry_candidates() {
	local want="${1:-}"
	local name url idx
	while IFS="$TAB" read -r name url; do
		[ -n "$name" ] || continue
		if ! idx="$(fetch_index "$url" 2>/dev/null)"; then
			echo "WARN: registry '$name' unreachable: $url" >&2
			continue
		fi
		printf '%s' "$idx" | jq -r --arg reg "$name" --arg want "$want" '
			.addons[] | select($want == "" or .id == $want) |
			[$reg, .id, .version, .name, .url, .sha256] | @tsv' 2>/dev/null \
			|| echo "WARN: registry '$name' has a malformed index" >&2
	done < <(registries_list)
}

# Merged view: local + bundled addons first, then registry hits.
# Dupes across registries sort newest-first; the newest of a dupe group is marked.
cmd_search() {
	need_jq || return 1
	local term="${1:-}"
	local id m ver name
	printf '%-22s %-9s %-12s %s\n' "ID" "VERSION" "SOURCE" "NAME"
	for id in $(all_addon_ids); do
		if [ -n "$term" ] && ! printf '%s' "$id" | grep -qi "$term"; then continue; fi
		m="$(manifest_path "$id")"
		ver="$(_field "$m" version)"
		name="$(_field "$m" name)"
		printf '%-22s %-9s %-12s %s\n' "$id" "${ver:--}" "$(addon_source "$id")" "$name"
	done
	registry_candidates "" | {
		if [ -n "$term" ]; then grep -i "$term" || true; else cat; fi
	} | sort -t"$TAB" -k2,2 -k3,3rV | awk -F'\t' '
		{ rows[NR] = $0; ids[NR] = $2; cnt[$2]++ }
		END {
			for (i = 1; i <= NR; i++) {
				split(rows[i], f, "\t")
				mark = (cnt[ids[i]] > 1 && !(seen[ids[i]]++)) ? "  ← newest" : ""
				printf "%-22s %-9s %-12s %s%s\n", f[2], f[3], f[1], f[4], mark
			}
		}'
}

main() {
	local cmd="${1:-status}"; shift || true
	case "$cmd" in
		_field)    _field "$@" ;;
		_support)  _support "$@" ;;
		_sha256)   sha256_hex "$@" ;;
		_list)     _list "$@" ;;
		_privacy)  cmd_privacy "$@" ;;
		status)    cmd_status "$@" ;;
		update)    cmd_update "$@" ;;
		enable)    cmd_enable "$@" ;;
		disable)   cmd_disable "$@" ;;
		install)   cmd_install "$@" ;;
		uninstall) cmd_uninstall "$@" ;;
		new)       cmd_new "$@" ;;
		registry)  cmd_registry "$@" ;;
		search)    cmd_search "$@" ;;
		configure) cmd_configure "$@" ;;
		onboard)   cmd_onboard "$@" ;;
		check)     cmd_check "$@" ;;
		test)      cmd_test "$@" ;;
		clients)   cmd_clients "$@" ;;
		*) echo "Unknown command: $cmd" >&2; exit 2 ;;
	esac
}
main "$@"
