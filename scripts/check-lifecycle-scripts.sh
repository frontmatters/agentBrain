#!/usr/bin/env bash
# check-lifecycle-scripts.sh — Validate lifecycle script contracts.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0
fail() {
	printf 'FAIL: %s\n' "$*" >&2
	failures=$((failures + 1))
}

require_file() {
	local file="$1"
	[[ -f "$file" ]] || fail "missing lifecycle script: $file"
	[[ -x "$file" ]] || fail "lifecycle script not executable: $file"
	grep -q 'set -euo pipefail' "$file" || fail "script missing set -euo pipefail: $file"
}

scripts=(
	scripts/setup.sh
	scripts/install-prerequisites.sh
	scripts/setup-agent-integrations.sh
	scripts/configure-pi.sh
	scripts/bootstrap-macos.sh
	scripts/ensure-daily-note.sh
	scripts/offboard.sh
	scripts/import-offboard.sh
	scripts/uninstall.sh
	scripts/move-agentbrain.sh
)

for script in "${scripts[@]}"; do
	require_file "$script"
done

# Contract checks for key behavior.
grep -q -- '--move-to' scripts/setup.sh || fail 'setup.sh missing --move-to relocation entrypoint'
grep -q 'move-agentbrain.sh' scripts/setup.sh || fail 'setup.sh does not delegate relocation to move-agentbrain.sh'

grep -q -- '--all' scripts/offboard.sh || fail 'offboard.sh missing --all option'
grep -q -- '--include-team' scripts/offboard.sh || fail 'offboard.sh missing --include-team option'
grep -q 'preferences/personal' scripts/offboard.sh || fail 'offboard.sh does not export personal preference scope'

grep -q 'preferences/personal' scripts/import-offboard.sh || fail 'import-offboard.sh does not import personal preference scope'
grep -q 'legacy flat exports import as personal' scripts/import-offboard.sh || fail 'import-offboard.sh missing legacy flat preference compatibility'

grep -q 'offboard.sh' scripts/uninstall.sh || fail 'uninstall.sh does not suggest offboarding before uninstall'
grep -q 'local files' scripts/uninstall.sh || fail 'uninstall.sh does not inspect local content before uninstall'

grep -q 'Backup' scripts/move-agentbrain.sh || fail 'move-agentbrain.sh missing backup step'
grep -q 'doctor.sh' scripts/move-agentbrain.sh || fail 'move-agentbrain.sh does not validate with doctor after move'
grep -q 'Relinked' scripts/move-agentbrain.sh || fail 'move-agentbrain.sh missing Pi symlink relink behavior'

grep -q 'local/daily-notes' scripts/ensure-daily-note.sh || fail 'ensure-daily-note.sh missing daily note target'
grep -q 'templates/daily.md' scripts/ensure-daily-note.sh || fail 'ensure-daily-note.sh missing template usage'

if [[ "$failures" -gt 0 ]]; then
	printf 'Lifecycle script check failed (%d issue(s)).\n' "$failures" >&2
	exit 1
fi

printf 'Lifecycle script check passed.\n'
