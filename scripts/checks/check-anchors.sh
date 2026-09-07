#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-anchors.sh — guard the three anchors everything else hangs on:
#
#   1. brain.json        — UUID5 namespace source; loss = unrecoverable ids.
#                          Must exist, parse, and have a fresh backup inside
#                          vault/ (the private repo) so it rides private git.
#   2. vault/ symlink    — the entire private layer; a dangling link makes the
#                          vault silently invisible to every agent.
#   3. ~/agentBrain      — the alias all agents resolve through.
#   4. git hooks         — core.hooksPath must point at .githooks, or the
#                          privacy-scan/doctor gates silently never run.
#
# Detect-only (doctor); `fix.sh` (doctor --fix) repairs 1's backup and 3.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

errors=0

# ── 1. brain.json + namespace backup ──
# Only the namespace is compared: brain.json's path/created differ per checkout
# (dev/live share the same vault/), the namespace is the unrecoverable part.
if [ ! -f brain.json ]; then
	echo "FAIL brain.json missing — UUID5 namespace source is gone (restore namespace from vault/brain-namespace.backup)" >&2
	errors=$((errors + 1))
elif ! python3 -c 'import json;json.load(open("brain.json"))' 2>/dev/null; then
	echo "FAIL brain.json does not parse — fix it NOW before any new note is created" >&2
	errors=$((errors + 1))
elif [ -d vault ]; then
	ns="$(python3 -c 'import json;print(json.load(open("brain.json")).get("namespace",""))' 2>/dev/null || true)"
	backup="$(cat vault/brain-namespace.backup 2>/dev/null || true)"
	if [ -z "$backup" ]; then
		echo "FAIL vault/brain-namespace.backup missing — namespace has no private-repo backup (run: bash scripts/fix.sh)" >&2
		errors=$((errors + 1))
	elif [ "$backup" != "$ns" ]; then
		echo "FAIL namespace mismatch: brain.json has '$ns' but vault/brain-namespace.backup has '$backup' — investigate BEFORE creating new notes" >&2
		errors=$((errors + 1))
	fi
fi

# ── 2. vault/ symlink health ──
if [ -L vault ] && [ ! -e vault ]; then
	echo "FAIL vault/ is a dangling symlink -> $(readlink vault) — your vault is unreachable" >&2
	errors=$((errors + 1))
elif [ ! -d vault ]; then
	echo "FAIL vault/ missing — there is no vault at all" >&2
	errors=$((errors + 1))
fi
if [ -L local ] && [ "$(readlink local)" = "vault" ]; then
	echo "WARN local/ is still an alias of vault/ (the old name); retire it with: bash scripts/setup/drop-local-alias.sh"
fi

# ── 3. ~/agentBrain alias ──
ALIAS="${AGENTBRAIN_ALIAS:-$HOME/agentBrain}"
if [ -L "$ALIAS" ] && [ ! -e "$ALIAS" ]; then
	echo "FAIL $ALIAS is a dangling symlink -> $(readlink "$ALIAS") — agents are blind (run: bash scripts/brain.sh use dev|live)" >&2
	errors=$((errors + 1))
elif [ ! -e "$ALIAS" ]; then
	echo "WARN $ALIAS does not exist — agents that resolve via the alias will not find the brain" >&2
fi

# ── 4. git hooks active ──
if git rev-parse --git-dir >/dev/null 2>&1; then
	hooks_path="$(git config core.hooksPath 2>/dev/null || true)"
	if [ "$hooks_path" != ".githooks" ]; then
		echo "FAIL git core.hooksPath is '${hooks_path:-unset}' (expected .githooks) — privacy-scan/doctor gates are NOT active (run: bash scripts/setup/setup-git-hooks.sh)" >&2
		errors=$((errors + 1))
	fi
fi

if [ "$errors" -gt 0 ]; then
	echo "check-anchors: $errors anchor problem(s)" >&2
	exit 1
fi
echo "check-anchors: brain.json (+backup), vault/, alias and git hooks healthy"
