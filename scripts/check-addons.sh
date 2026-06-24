#!/usr/bin/env bash
# Static validation of add-on manifests. Doctor-wired. Fails on malformed manifests.
# Never inspects whether an external tool is installed (that is addons.sh check).
# Env: ADDONS_CHECK_REGISTRY overrides the registry root (tests).
# Intentional word-splitting: allow-lists (VALID_*) are passed to in_set as separate args.
# shellcheck disable=SC2086
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REGISTRY="${ADDONS_CHECK_REGISTRY:-system/addons}"
ONLY="${1:-}"   # optional: validate a single add-on by id
CLIENTS="claude gemini opencode pi cursor copilot windsurf cline hermes"
REQUIRED="id name privacy install_method"
VALID_PRIVACY="local local-only sends-docs sends-all"
VALID_SUPPORT="full rules none unknown"
VALID_METHOD="self ai-driven config-entry"
VALID_OS="macos linux windows any"

field() { awk -v k="$2" '/^---[[:space:]]*$/{fm++;next} fm==1 && $0 ~ "^"k":"{sub("^"k":[[:space:]]*","");sub(/[[:space:]]*#.*$/,"");print;exit}' "$1"; }
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
