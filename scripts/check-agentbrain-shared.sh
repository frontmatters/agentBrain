#!/usr/bin/env bash
# Secret-gate for the shared/ layer. Blocks plaintext secrets before they reach a
# remote that others can read. Two modes:
#   (default)    scan the SHARED_DIR working tree  -> pre-push gate
#   --incoming   scan added lines in HEAD..FETCH_HEAD -> pre-merge gate (run after git fetch)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_DIR="${AGENTBRAIN_SHARED_DIR:-$ROOT_DIR/shared}"
MODE="${1:-tree}"

# Identical high-confidence pattern as check-agentbrain-local.sh (keep in sync).
SECRET_PATTERN='(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|\bsk-[A-Za-z0-9_-]{20,}|\bsk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{20,}|[a-z]+://[^[:space:]/:@]+:[^[:space:]@]+@[^[:space:]/]+)|eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+'

if [[ ! -d "$SHARED_DIR" ]]; then
	printf 'No shared/ layer configured — skipping shared secret-gate.\n'
	exit 0
fi

if [[ "$MODE" == "--incoming" ]]; then
	cd "$SHARED_DIR"
	hits="$(git diff --no-color HEAD..FETCH_HEAD 2>/dev/null | grep -E '^\+' | grep -En "$SECRET_PATTERN" || true)"
else
	hits="$({
		cd "$SHARED_DIR"
		if command -v rg >/dev/null 2>&1; then
			rg -n -I --hidden --glob '!.git/**' -e "$SECRET_PATTERN" . || true
		else
			grep -RInE --exclude-dir=.git "$SECRET_PATTERN" . || true
		fi
	})"
fi

if [[ -n "$hits" ]]; then
	printf 'Shared secret-gate FAILED. Likely plaintext secret(s) in shared/ (%s):\n' "$MODE" >&2
	printf '%s\n' "$hits" >&2
	printf '\nMove the value to secrets-helper/keychain; shared/ is visible to others.\n' >&2
	exit 1
fi
printf 'Shared secret-gate passed (%s).\n' "$MODE"
