#!/usr/bin/env bash
# Report non-lowercase paths. Public layer intentionally keeps legacy Title Case folders;
# local active content should gradually move toward lowercase/kebab-case.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STRICT=0
if [[ "${1:-}" == "--strict" ]]; then
	STRICT=1
fi

printf 'Path naming audit\n'
printf '=================\n'

public_hits="$(git ls-files | grep -E '[A-Z]| ' || true)"
if [[ -n "$public_hits" ]]; then
	printf '\nPublic legacy mixed-case paths: %s\n' "$(printf '%s\n' "$public_hits" | wc -l | tr -d ' ')"
	printf '%s\n' "$public_hits" | sed -n '1,30p' | sed 's/^/  /'
	if (($(printf '%s\n' "$public_hits" | wc -l | tr -d ' ') > 30)); then
		printf '  ...\n'
	fi
	printf 'Note: public Title Case folders are legacy/stable API; do not rename casually.\n'
fi

local_hits=""
if [[ -d local ]]; then
	local_hits="$(find local \
		-path 'local/.git' -prune -o \
		-path 'local/backups' -prune -o \
		-path 'local/public-private-split-*' -prune -o \
		-name '.DS_Store' -prune -o \
		-name 'README.md' -prune -o \
		-print | sed 's#^local/##' | grep -E '[A-Z]| ' || true)"
fi

if [[ -n "$local_hits" ]]; then
	printf '\nActive local non-lowercase paths: %s\n' "$(printf '%s\n' "$local_hits" | wc -l | tr -d ' ')"
	printf '%s\n' "$local_hits" | sed -n '1,80p' | sed 's/^/  /'
	if ((STRICT)); then
		printf '\nPath naming check failed in strict mode.\n' >&2
		exit 1
	fi
	printf '\nWarning only: run with --strict to fail on active local naming drift.\n'
else
	printf '\nActive local paths are lowercase/kebab-case clean.\n'
fi

shared_hits=""
if [[ -d shared ]]; then
	shared_hits="$(find shared \
		-path 'shared/.git' -prune -o \
		-name '.DS_Store' -prune -o \
		-name 'README.md' -prune -o \
		-print | sed 's#^shared/##' | grep -E '[A-Z]| ' || true)"
fi

if [[ -n "$shared_hits" ]]; then
	printf '\nActive shared non-lowercase paths: %s\n' "$(printf '%s\n' "$shared_hits" | wc -l | tr -d ' ')"
	printf '%s\n' "$shared_hits" | sed -n '1,80p' | sed 's/^/  /'
	if ((STRICT)); then
		printf '\nPath naming check failed in strict mode.\n' >&2
		exit 1
	fi
	printf '\nWarning only: run with --strict to fail on active shared naming drift.\n'
else
	printf '\nActive shared paths are lowercase/kebab-case clean.\n'
fi
