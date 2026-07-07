#!/usr/bin/env bash
# Sanity-check the private agentBrain local/ repository before pushing to private storage.
# This is NOT a public-safety scan. It allows private notes/URLs, but blocks likely plaintext secrets.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"

if [[ ! -d "$LOCAL_DIR" ]]; then
	printf 'No local directory found: %s\n' "$LOCAL_DIR" >&2
	exit 1
fi

# High-confidence credential patterns only. Private URLs/project names are allowed in local/.
SECRET_PATTERN='(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|\bsk-[A-Za-z0-9_-]{20,}|\bsk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{20,}|[a-z]+://[^[:space:]/:@]+:[^[:space:]@]+@[^[:space:]/]+)|eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+'

hits="$({
	cd "$LOCAL_DIR"
	if command -v rg >/dev/null 2>&1; then
		rg -n -I --hidden --glob '!.git/**' --glob '!**/node_modules/**' --glob '!backups/**' --glob '!quarantine/**' --glob '!graphify-out/**' --glob '!skills/flux-design-system/scan-patterns.js' -e "$SECRET_PATTERN" . || true
	else
		grep -RInE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=backups --exclude-dir=quarantine --exclude=scan-patterns.js "$SECRET_PATTERN" . || true
	fi
})"

if [[ -n "$hits" ]]; then
	printf 'Private local check failed. Likely plaintext secret(s) found in local/:\n' >&2
	printf '%s\n' "$hits" >&2
	printf '\nMove the value to secrets-helper/keychain and keep only references in local notes.\n' >&2
	exit 1
fi

printf 'Private local check passed.\n'
