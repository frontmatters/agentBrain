#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# CLI safety tests: help and dry-run must never commit or push.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
SYNC="$ROOT_DIR/scripts/sync/sync-vault.sh"
# A test states what it needs. sync-vault reports change status through
# changes.sh, which fetches every repository it finds; that reached a LAN server
# over SSH from inside the release sandbox and made the run depend on a machine
# the test never mentions.
export AGENTBRAIN_NO_FETCH=1
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-sync-local-cli-XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

help_out="$(bash "$SYNC" --help)"
grep -q '^Usage:' <<<"$help_out" || fail "--help did not print usage"

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.name test
git -C "$FIXTURE" config user.email test@example.invalid
printf 'baseline\n' > "$FIXTURE/tracked.txt"
git -C "$FIXTURE" add tracked.txt
git -C "$FIXTURE" commit -qm baseline
before="$(git -C "$FIXTURE" rev-parse HEAD)"
printf 'pending\n' >> "$FIXTURE/tracked.txt"
printf 'untracked\n' > "$FIXTURE/pending.txt"

out="$(
	AGENTBRAIN_LOCAL_DIR="$FIXTURE" \
	GITEA_HELPER_PATH="$FIXTURE/does-not-exist" \
	bash "$SYNC" --dry-run
)"
after="$(git -C "$FIXTURE" rev-parse HEAD)"

[ "$before" = "$after" ] || fail "--dry-run created a commit"
[ -f "$FIXTURE/pending.txt" ] || fail "--dry-run changed working-tree files"
grep -q 'tracked.txt' <<<"$out" || fail "--dry-run did not report tracked changes"
grep -q 'pending.txt' <<<"$out" || fail "--dry-run did not report untracked changes"

if bash "$SYNC" --not-an-option >/dev/null 2>&1; then
	fail "unknown option was accepted"
fi

echo "PASS test-sync-vault-cli"
