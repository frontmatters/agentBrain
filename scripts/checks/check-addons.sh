#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Static validation of add-on manifests. Doctor-wired. Fails on malformed manifests.
# Never inspects whether an external tool is installed (that is addons.sh check).
# Env: ADDONS_CHECK_REGISTRY overrides the registry root (tests).
# Intentional word-splitting: allow-lists (VALID_*) are passed to in_set as separate args.
# shellcheck disable=SC2086
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/lib/platform.sh
. "$ROOT_DIR/scripts/lib/platform.sh"

REGISTRY="${ADDONS_CHECK_REGISTRY:-system/addons}"
ONLY="${1:-}"   # optional: validate a single add-on by id
# Same list as the matrix columns and the same one the declared-client guard
# validates against. It was a third hand-kept copy; keeping three in step by
# hand is how abh ended up declared by 34 manifests with no column anywhere.
CLIENTS="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT_DIR/scripts/lib/clients.txt" 2>/dev/null | tr '\n' ' ')"
REQUIRED="id name privacy install_method author"
VALID_PRIVACY="local local-only sends-docs sends-all"
VALID_SUPPORT="full rules none unknown"
# Every client a manifest declares must have a column, or the matrix silently
# omits it and reads as "no add-on supports this". The list is declared rather
# than derived from the manifests, because a release ships a slim core and a
# derived list differs between a full checkout and a fresh install.
KNOWN_CLIENTS="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT_DIR/scripts/lib/clients.txt" 2>/dev/null | tr '\n' ' ')"
VALID_METHOD="self ai-driven config-entry"
VALID_OS="macos linux windows any"
VALID_DEPRECATED_REASON="renamed replaced merged discontinued"

field() { awk -v k="$2" '/^---[[:space:]]*$/{fm++;next} fm==1 && $0 ~ "^"k":"{sub("^"k":[[:space:]]*","");sub(/[[:space:]]*#.*$/,"");print;exit}' "$1"; }
# Extract a subfield of the nested `deprecated:` block (reason/replaced_by/since/remove_after).
dep_sub() { awk -v k="$2" '/^---[[:space:]]*$/{fm++;next} fm==1&&/^deprecated:[[:space:]]*$/{s=1;next} fm==1&&s&&/^[^[:space:]]/{s=0} fm==1&&s&&$0 ~ "^[[:space:]]+"k":"{sub("^[[:space:]]+"k":[[:space:]]*","");sub(/[[:space:]]*#.*$/,"");gsub(/"/,"");print;exit}' "$1"; }
support() { awk -v c="$2" '/^---[[:space:]]*$/{fm++;next} fm==1&&/^support:[[:space:]]*$/{s=1;next} fm==1&&s&&/^[^[:space:]]/{s=0} fm==1&&s&&$0 ~ "^[[:space:]]+"c":"{sub("^[[:space:]]+"c":[[:space:]]*","");sub(/[[:space:]]*#.*$/,"");print;exit}' "$1"; }
in_set() { local x="$1"; shift; for v in "$@"; do [ "$x" = "$v" ] && return 0; done; return 1; }
# Extract schedule.entrypoint (a relative path under the addon dir) from a manifest.
schedule_entrypoint() { awk '/^---[[:space:]]*$/{fm++;next} fm==1&&/^schedule:[[:space:]]*$/{s=1;next} fm==1&&s&&/^[^[:space:]]/{s=0} fm==1&&s&&/^[[:space:]]+entrypoint:/{sub(/^[[:space:]]+entrypoint:[[:space:]]*/,"");sub(/[[:space:]]*#.*$/,"");gsub(/"/,"");print;exit}' "$1"; }
# Extract onboard.run (a command string) from a manifest.
onboard_run() { awk '/^---[[:space:]]*$/{fm++;next} fm==1&&/^onboard:[[:space:]]*$/{s=1;next} fm==1&&s&&/^[^[:space:]]/{s=0} fm==1&&s&&/^[[:space:]]+run:/{sub(/^[[:space:]]+run:[[:space:]]*/,"");sub(/[[:space:]]*#.*$/,"");gsub(/"/,"");print;exit}' "$1"; }

# Resolve a manifest-referenced path token against the add-on directory.
# Manifest tokens can be vault-root-relative (`system/addons/<id>/install.sh`) or
# bare/relative to the add-on dir (`install.sh`, `bin/foo` after a `cd`). Returns 0
# if the token resolves to an existing file under the add-on dir; 1 otherwise.
ref_file_exists() {
	local addon_dir="$1" dir_id="$2" tok="$3" tail
	# Strip an optional leading `system/addons/<dir_id>/` so the remainder is
	# relative to the add-on dir; this keeps the check correct under a test
	# registry whose path differs from the literal `system/addons` in the token.
	tail="${tok#system/addons/"$dir_id"/}"
	[ -f "$addon_dir/$tail" ] && return 0
	# Fall back to the bare basename (covers `cd <dir> && bash install.sh`).
	[ -f "$addon_dir/$(basename "$tok")" ] && return 0
	return 1
}

errors=0
[ -d "$REGISTRY" ] || { echo "ok: no add-ons registry ($REGISTRY) — nothing to validate"; exit 0; }

SEEN_SHORTS=""
for m in "$REGISTRY"/*/manifest.md; do
	[ -f "$m" ] || continue
	dir_id="$(basename "$(dirname "$m")")"
	addon_dir="$(dirname "$m")"
	# `_template/` carries intentional placeholder content (`id: your-addon-id`) —
	# it is a scaffold for new addons, not an addon itself.
	[ "$dir_id" = "_template" ] && continue
	[ -n "$ONLY" ] && [ "$ONLY" != "$dir_id" ] && continue
	[ -f "$(dirname "$m")/README.md" ] || { echo "FAIL $m: missing README.md (every add-on must document itself)" >&2; errors=$((errors+1)); }
	# Install/uninstall symmetry: any add-on shipping an install.sh must also ship a
	# matching uninstall.sh — the "true inverse" contract (see README "Add-on types").
	# This keeps newly-added install scripts from silently lacking a removal path.
	[ -f "$addon_dir/install.sh" ] && [ ! -f "$addon_dir/uninstall.sh" ] && { echo "FAIL $m: has install.sh but no uninstall.sh (every install needs a true inverse)" >&2; errors=$((errors+1)); }
	for key in $REQUIRED; do
		if [ -z "$(field "$m" "$key")" ]; then
			echo "FAIL $m: missing required field '$key'" >&2; errors=$((errors+1))
		fi
	done
	id="$(field "$m" id)"
	[ -n "$id" ] && [ "$id" != "$dir_id" ] && { echo "FAIL $m: id '$id' != directory '$dir_id'" >&2; errors=$((errors+1)); }
	# Optional `shorthand:` — lowercase handle, unique across addons.
	sh="$(field "$m" shorthand)"
	if [ -n "$sh" ]; then
		case "$sh" in
			*[!a-z0-9-]*) echo "FAIL $m: shorthand '$sh' must be lowercase [a-z0-9-]" >&2; errors=$((errors+1)) ;;
		esac
		if [ -n "$SEEN_SHORTS" ] && printf '%s\n' "$SEEN_SHORTS" | grep -qx "$sh"; then
			echo "WARN $m: shorthand '$sh' already declared by another addon (alphabetically-first id wins)" >&2
		fi
		SEEN_SHORTS="$(printf '%s\n%s' "$SEEN_SHORTS" "$sh")"
	fi
	# Optional `license:` — SPDX identifier (e.g. Apache-2.0, MIT,
	# PolyForm-Noncommercial-1.0.0). Absent = the framework default (Apache-2.0),
	# applied at index time by registry-index.sh; here we only validate the shape.
	lic="$(field "$m" license)"
	if [ -n "$lic" ]; then
		case "$lic" in
			*[!A-Za-z0-9.+-]*) echo "FAIL $m: license '$lic' is not a plain SPDX identifier ([A-Za-z0-9.+-])" >&2; errors=$((errors+1)) ;;
		esac
	fi
	# Optional `requires:` — space/comma-separated addon ids this add-on depends on.
	# Each must resolve to a known add-on (in this registry or the canonical
	# system/addons) — a typo-guard. Enforcement at runtime is soft (addons.sh check
	# warns when a dependency isn't enabled); it never blocks install.
	req_val="$(field "$m" requires)"
	if [ -n "$req_val" ]; then
		for req in ${req_val//,/ }; do
			if [ ! -d "$REGISTRY/$req" ] && [ ! -d "system/addons/$req" ]; then
				echo "FAIL $m: requires '$req' — no such add-on in $REGISTRY or system/addons" >&2; errors=$((errors+1))
			fi
		done
	fi
	# Optional `runtime_requires:` — external runtime capabilities (space/comma
	# list). Each must be a known platform_has capability (typo-guard), mirroring
	# how `requires:` validates against known add-ons. Runtime is soft (addons.sh
	# check warns); this is the static gate.
	rtreq="$(field "$m" runtime_requires)"
	if [ -n "$rtreq" ]; then
		known=" $(platform_capabilities) "
		for cap in ${rtreq//,/ }; do
			case "$known" in
				*" $cap "*) : ;;
				*) echo "FAIL $m: runtime_requires '$cap' is not a known capability (see platform_capabilities)" >&2; errors=$((errors+1)) ;;
			esac
		done
	fi
	# Version parity (ksc): if the addon ships a CHANGELOG.md, its top versioned
	# heading (`## [x.y.z]`) must equal the manifest `version:`. Enforces the
	# SemVer + Keep-a-Changelog half of the ksc triad at the addon level — a manifest
	# that drifts from its own changelog is a release-hygiene bug (see
	# system/versioning.md). Adopted addons version the *wrapper*, not upstream.
	ver="$(field "$m" version)"
	cl="$addon_dir/CHANGELOG.md"
	if [ -n "$ver" ] && [ -f "$cl" ]; then
		cl_ver="$(grep -oE '^##[[:space:]]*\[[0-9]+\.[0-9]+\.[0-9]+\]' "$cl" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
		if [ -n "$cl_ver" ] && [ "$ver" != "$cl_ver" ]; then
			echo "FAIL $m: manifest version '$ver' != CHANGELOG top '[$cl_ver]' (ksc parity)" >&2; errors=$((errors+1))
		fi
	fi
	priv="$(field "$m" privacy)"
	[ -n "$priv" ] && ! in_set "$priv" $VALID_PRIVACY && { echo "FAIL $m: invalid privacy '$priv'" >&2; errors=$((errors+1)); }
	method="$(field "$m" install_method)"
	[ -n "$method" ] && ! in_set "$method" $VALID_METHOD && { echo "FAIL $m: invalid install_method '$method'" >&2; errors=$((errors+1)); }
	[ "$method" = "self" ] && [ -z "$(field "$m" install)" ] && { echo "FAIL $m: install_method=self requires a non-empty 'install:' field" >&2; errors=$((errors+1)); }
	# Optional OS constraint: space/comma-separated. Absent = cross-platform (any).
	os_val="$(field "$m" os)"
	if [ -n "$os_val" ]; then
		for o in ${os_val//,/ }; do
			in_set "$o" $VALID_OS || { echo "FAIL $m: invalid os '$o' (allowed: $VALID_OS)" >&2; errors=$((errors+1)); }
		done
	fi
	# Referenced-file existence: every script path named in the manifest must exist.
	# The contract: "A manifest that references a missing file is a FAIL."
	# We only validate local script paths (`.sh` tokens under system/addons, or a
	# bare install.sh) — not external commands (npm/git URLs) or non-script args.
	install_cmd="$(field "$m" install)"
	for tok in $install_cmd; do
		case "$tok" in
			*.sh)
				# Only treat it as a local-script reference when it is plausibly
				# inside the add-on (vault-relative system/addons path or bare name).
				case "$tok" in
					system/addons/*|install.sh|*/install.sh|uninstall.sh)
						if ! ref_file_exists "$addon_dir" "$dir_id" "$tok"; then
							echo "FAIL $m: install references missing file '$tok'" >&2; errors=$((errors+1))
						fi ;;
				esac ;;
		esac
	done
	entrypoint="$(schedule_entrypoint "$m")"
	if [ -n "$entrypoint" ] && ! ref_file_exists "$addon_dir" "$dir_id" "$entrypoint"; then
		echo "FAIL $m: schedule.entrypoint references missing file '$entrypoint'" >&2; errors=$((errors+1))
	fi
	# Optional onboard.run: validate any local .sh token it names (mirrors install:).
	onboard_cmd="$(onboard_run "$m")"
	for tok in $onboard_cmd; do
		case "$tok" in
			*.sh)
				case "$tok" in
					system/addons/*|*/onboard.sh|onboard.sh)
						if ! ref_file_exists "$addon_dir" "$dir_id" "$tok"; then
							echo "FAIL $m: onboard.run references missing file '$tok'" >&2; errors=$((errors+1))
						fi ;;
				esac ;;
		esac
	done
	for c in $CLIENTS; do
		lvl="$(support "$m" "$c")"
		[ -z "$lvl" ] && lvl="unknown"   # client absent from manifest = untested = ok
		[ "$lvl" = "unknown" ] && continue
		in_set "$lvl" $VALID_SUPPORT || { echo "FAIL $m: client '$c' has invalid support '$lvl'" >&2; errors=$((errors+1)); }
	done
	# default_enabled: the addon is switched on by a fresh install unless the
	# user unticks it. That is a promise about what a new machine does without
	# being asked, so three kinds of addon may never carry it:
	#
	#   - one whose install.sh fetches software. A fresh install must not pull
	#     packages nobody asked for.
	#   - one whose privacy is sends-docs or sends-all. Sending a user's notes
	#     anywhere is a decision they make, not a default they discover.
	#   - one with runtime_requires, which would switch on and then not work.
	#
	# Bundling and enabling are separate fields on purpose: event-bus ships in
	# the slim core and installs software, extract-learnings ships and sends
	# documents out. Both belong in a release; neither belongs switched on.
	if grep -qE '^default_enabled:[[:space:]]*(true|yes)[[:space:]]*$' "$m"; then
		_ad="$(dirname "$m")"
		# Match a fetcher as a COMMAND, not as a word anywhere in the file. The
		# first version listed six ways to fetch software and eleven common ones
		# walked past it, `apt install` without the hyphen and `curl | sh`
		# among them: a denylist is only as good as the author's imagination and
		# weakens silently as package managers are invented. Matching the word
		# anywhere went too far the other way and flagged an echo.
		#
		# A command starts a line or follows a pipe, && or ;. Narrow enough to
		# ignore prose, wide enough that a new package manager still trips it.
		if [ -f "$_ad/install.sh" ]; then
			_fetch='brew|apt|apt-get|dnf|yum|pacman|zypper|apk|snap|flatpak|pip|pip3|pipx|cargo|gem|composer|choco|winget|npm|pnpm|yarn|deno|curl|wget'
			# `go` and `bun` are too generic as bare commands (go build, bun run),
			# so they are matched in the two-word form that actually fetches.
			_fetch2='go[[:space:]]+(install|get)|bun[[:space:]]+(add|install)|uv[[:space:]]+(tool|pip)|deno[[:space:]]+install'
			_hit="$(grep -nE "(^|[&|;])[[:space:]]*(sudo[[:space:]]+)?(($_fetch)([[:space:]]|\$)|($_fetch2))" "$_ad/install.sh" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 || true)"
			if [ -n "$_hit" ]; then
				echo "FAIL $m: default_enabled, but install.sh runs a fetcher: $_hit" >&2
				echo "       A default-on addon installs on a fresh machine with nobody watching." >&2
				errors=$((errors+1))
			fi
		fi
		_priv="$(sed -n 's/^privacy:[[:space:]]*//p' "$m" | head -1 | tr -d '\r')"
		case "$_priv" in
			sends-docs|sends-all)
				echo "FAIL $m: default_enabled with privacy '$_priv'; sending content out is a choice, not a default" >&2
				errors=$((errors+1)) ;;
		esac
		if sed -n 's/^runtime_requires:[[:space:]]*//p' "$m" | head -1 | grep -q '[^[:space:]]'; then
			echo "FAIL $m: default_enabled on an addon with runtime_requires" >&2
			errors=$((errors+1))
		fi
		# `command:` is a runtime dependency too. An addon needing bun either
		# fails to install where bun is absent, or installs and skips its own
		# setup step and leaves a state its health check then calls drift. Only
		# interpreters every system has may carry default_enabled.
		_cmd="$(sed -n 's/^command:[[:space:]]*//p' "$m" | head -1 | awk '{print $1}')"
		case "${_cmd:-}" in
			''|bash|sh|python3) ;;
			*)
				echo "FAIL $m: default_enabled with command '$_cmd'; only bash, sh and python3 are present everywhere" >&2
				errors=$((errors+1)) ;;
		esac
		# On by default means present: a release ships a slim core, and a fresh
		# install cannot switch on an addon whose payload never arrived.
		if ! grep -qx "$(basename "$_ad")" "$ROOT_DIR/scripts/lib/essential-addons.txt" 2>/dev/null; then
			echo "FAIL $m: default_enabled but not in essential-addons.txt; it would not ship" >&2
			errors=$((errors+1))
		fi
	fi

	# Every client the manifest DECLARES must have a column. The loop above walks
	# a fixed list, so it can only ever see clients that already have one; a key
	# nobody listed slips past it and then vanishes from the matrix, which reads
	# as "no add-on supports this".
	while IFS= read -r c; do
		[ -n "$c" ] || continue
		in_set "$c" $KNOWN_CLIENTS || {
			echo "FAIL $m: client '$c' has no column; add it to scripts/lib/clients.txt and run 'bash scripts/addons.sh clients --write'" >&2
			errors=$((errors+1))
		}
	done < <(awk '/^---[[:space:]]*$/{fm++;next} fm==1&&/^support:[[:space:]]*$/{s=1;next} fm==1&&s&&/^[^[:space:]]/{s=0} fm==1&&s&&/^[[:space:]]+[a-z][a-z0-9-]*:/{sub(/^[[:space:]]+/,"");sub(/:.*$/,"");print}' "$m")

	# Optional `deprecated:` block. If present: `reason` is required + enum;
	# `replaced_by` is required UNLESS reason=discontinued (the no-successor case).
	if grep -qE "^deprecated:[[:space:]]*$" "$m"; then
		dreason="$(dep_sub "$m" reason)"; drepl="$(dep_sub "$m" replaced_by)"
		if [ -z "$dreason" ]; then
			echo "FAIL $m: deprecated block missing required 'reason'" >&2; errors=$((errors+1))
		elif ! in_set "$dreason" $VALID_DEPRECATED_REASON; then
			echo "FAIL $m: invalid deprecated.reason '$dreason' (use: $VALID_DEPRECATED_REASON)" >&2; errors=$((errors+1))
		fi
		if [ "$dreason" != "discontinued" ] && [ -z "$drepl" ]; then
			echo "FAIL $m: deprecated.replaced_by required unless reason=discontinued" >&2; errors=$((errors+1))
		fi
	fi
	# Optional `schedule:` block. If present, must have a 5-field cron expression
	# with numeric-or-wildcard fields. `args:` is optional (YAML list).
	if grep -qE "^schedule:[[:space:]]*$" "$m"; then
		cron=$(awk '
			/^---[[:space:]]*$/{fm++;next}
			fm==1 && /^schedule:[[:space:]]*$/{ins=1;next}
			fm==1 && ins && /^[^[:space:]]/{ins=0}
			fm==1 && ins && /^[[:space:]]+cron:/{
				sub(/.*cron:[[:space:]]*"?/,""); sub(/"[[:space:]]*$/,""); print; exit
			}' "$m")
		if [ -z "$cron" ]; then
			echo "FAIL $m: schedule block missing required 'cron:'" >&2; errors=$((errors+1))
		else
			# read -r is safe (no glob expansion); set -- $cron expands '*'.
			read -r c_min c_hour c_dom c_mon c_dow rest <<< "$cron"
			if [ -z "$c_dow" ] || [ -n "$rest" ]; then
				echo "FAIL $m: schedule.cron must be 5 fields (got: '$cron')" >&2; errors=$((errors+1))
			else
				for f in "$c_min" "$c_hour" "$c_dom" "$c_mon" "$c_dow"; do
					# Accept '*', a positive integer, or '*/N' (step value).
					if [ "$f" != "*" ] && ! echo "$f" | grep -qE "^([0-9]+|\*/[0-9]+)$"; then
						echo "FAIL $m: schedule.cron field '$f' must be numeric, '*', or '*/N' (got: '$cron')" >&2
						errors=$((errors+1))
						break
					fi
				done
			fi
		fi
	fi
done

# Client capability matrix drift-check: clients.md is generated from the manifests'
# support: blocks (scripts/addons.sh clients --write). Fail if it is stale.
# Only meaningful for a full-registry run that actually has a clients.md.
if [ -z "$ONLY" ] && [ -f "$REGISTRY/clients.md" ]; then
	if command -v diff >/dev/null 2>&1; then
		if ! ADDONS_REGISTRY="$REGISTRY" bash scripts/addons.sh clients 2>/dev/null \
				| diff -q - "$REGISTRY/clients.md" >/dev/null; then
			echo "FAIL $REGISTRY/clients.md: out of sync with manifests — run 'bash scripts/addons.sh clients --write'" >&2
			errors=$((errors+1))
		fi
	fi
fi

if [ "$errors" -gt 0 ]; then
	echo "check-addons: $errors error(s)" >&2; exit 1
fi
echo "check-addons: all manifests valid"
