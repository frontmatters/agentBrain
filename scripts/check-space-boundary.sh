#!/usr/bin/env bash
# check-space-boundary.sh — boundary guard for sealed spaces (local/spaces/<slug>/).
#
# Spaces are confidential compartments. Each paspoort local/spaces/<slug>/index.md
# carries a `space-id:` (the provenance watermark brain-extract stamps onto a
# deliverable) and an `owner:`. This guard FAILS the build (non-zero) when a
# compartment crosses its boundary in either of two ways:
#
#   (a) Seal breach — a spaces/ path is staged in the PERSONAL vault index.
#       The personal sync (scripts/sync-agentbrain-local.sh) runs `git add -A`
#       in local/; spaces/ is gitignored, so a staged spaces/ path means the seal
#       was bypassed (force-add / edited ignore) and the compartment is about to
#       enter the personal remote.
#
#   (b) Confidential leak — a space's space-id or owner literal appears in a
#       public/tracked artifact outside local/spaces/ (system/, scripts/, docs/,
#       …) or in a file staged for the personal sync. The space-id is unique, so
#       it is scanned everywhere; the owner is a business name, so it is matched
#       whole-word (case-insensitive) and an allowlist skips the framework files
#       that legitimately reference it (its own regex, this guard + test, and
#       code-root path references).
#
# On success: prints "check-space-boundary: ok" and exits 0.
#
# Mirrors scripts/privacy-scan.sh in scan style, reporting, and exit conventions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"
SPACES_DIR="$LOCAL_DIR/spaces"
cd "$ROOT_DIR"

fail=0
err() { printf '%s\n' "$*" >&2; }
vault_is_git() { git -C "$LOCAL_DIR" rev-parse --git-dir >/dev/null 2>&1; }
root_is_git() { git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; }

# Scan the public surface (tracked + untracked, excluding the sealed local/
# tree) for a fixed-string literal. Falls back to plain grep when the checkout
# is not a git repo (release payloads, install sandboxes) so the leak scan
# never fails open. $1 = extra grep flags ("" or "iw"), $2 = literal.
scan_public() {
	local flags="$1" lit="$2"
	if root_is_git; then
		git grep --untracked -nI"$flags" -F -e "$lit" -- . ':(exclude)local/**' 2>/dev/null || true
	else
		grep -rnI"$flags" -F -e "$lit" . \
			--exclude-dir=local --exclude-dir=shared --exclude-dir=.git 2>/dev/null |
			sed 's|^\./||' || true
	fi
}

# Drop public files where a confidential literal legitimately appears.
allow() {
	grep -v '^$' |
		grep -v '^scripts/check-space-boundary\.sh:' |
		grep -v '^scripts/test-space-boundary\.sh:' |
		grep -v '^scripts/privacy-scan\.sh:' |
		grep -vE '_work/' || true
}

# ── (a) Seal breach: spaces/ staged in the personal vault index ──────────────
if vault_is_git; then
	breach="$(git -C "$LOCAL_DIR" diff --cached --name-only 2>/dev/null | grep -E '^spaces/' || true)"
	if [ -n "$breach" ]; then
		err "Space seal breach: sealed space path(s) staged in the personal vault index:"
		printf '%s\n' "$breach" | sed 's/^/  /' >&2
		err "These must never enter the personal sync. Unstage: git -C local reset -- spaces/"
		fail=1
	fi
fi

# ── Collect confidential literals from the space paspoorten ──────────────────
space_ids=()
owners=()
if [ -d "$SPACES_DIR" ]; then
	while IFS= read -r paspoort; do
		[ -f "$paspoort" ] || continue
		sid="$(sed -n 's/^space-id:[[:space:]]*//p' "$paspoort" | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//')"
		own="$(sed -n 's/^owner:[[:space:]]*//p' "$paspoort" | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//')"
		[ -n "$sid" ] && space_ids+=("$sid")
		[ -n "$own" ] && owners+=("$own")
	done < <(find "$SPACES_DIR" -mindepth 2 -maxdepth 2 -name index.md 2>/dev/null)
fi

# ── (b) Confidential leak into public artifacts ──────────────────────────────
# space-id: unique provenance watermark — scan the whole public surface
# (tracked + untracked, excluding the sealed local/ tree).
if [ "${#space_ids[@]}" -gt 0 ]; then
	for sid in "${space_ids[@]}"; do
		hits="$(scan_public "" "$sid" | allow)"
		if [ -n "$hits" ]; then
			err "Confidential leak: space-id '$sid' found in public artifact(s):"
			printf '%s\n' "$hits" | sed 's/^/  /' >&2
			fail=1
		fi
	done
fi

# owner: business name — whole-word, case-insensitive, with the allowlist.
if [ "${#owners[@]}" -gt 0 ]; then
	for own in "${owners[@]}"; do
		hits="$(scan_public "iw" "$own" | allow)"
		if [ -n "$hits" ]; then
			err "Confidential leak: space owner '$own' found in public artifact(s):"
			printf '%s\n' "$hits" | sed 's/^/  /' >&2
			fail=1
		fi
	done
fi

# space-id leak into files staged for the personal sync (outside spaces/).
if vault_is_git && [ "${#space_ids[@]}" -gt 0 ]; then
	staged_nonspace="$(git -C "$LOCAL_DIR" diff --cached --name-only 2>/dev/null | grep -vE '^spaces/' || true)"
	if [ -n "$staged_nonspace" ]; then
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			for sid in "${space_ids[@]}"; do
				vhit="$(git -C "$LOCAL_DIR" grep --cached -nI -F -e "$sid" -- "$f" 2>/dev/null || true)"
				if [ -n "$vhit" ]; then
					err "Confidential leak: space-id '$sid' staged for the personal sync:"
					printf '%s\n' "$vhit" | sed "s|^|  $f: |" >&2
					fail=1
				fi
			done
		done <<<"$staged_nonspace"
	fi
fi

if [ "$fail" -ne 0 ]; then
	err "check-space-boundary: FAILED"
	exit 1
fi

echo "check-space-boundary: ok"
