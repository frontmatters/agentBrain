#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Contract test for the ABH integration setup (no real npm/network required).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agentbrain-abh-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/abh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ABH_TEST_LOG"
case "$*" in
  *--dump-config) printf '%s\n' 'agentbrain-context agentbrain-memory skill-filesystem' ;;
esac
SH
chmod +x "$TMP/bin/abh"
ABH_TEST_LOG="$TMP/calls.log" ABH_HOME="$TMP/.abh" PATH="$TMP/bin:$PATH" \
  AGENTBRAIN_ASSUME_YES=1 bash "$ROOT/scripts/setup/setup-abh.sh" >/dev/null
PATCH="$TMP/.abh/profiles/web/cordis.patch.yml"
if [ -f "$PATCH" ]; then
  for package in agentbrain-context agentbrain-memory skill-filesystem; do
    grep -q "@agentbrain-harness/$package" "$PATCH" || { echo "missing $package" >&2; exit 1; }
  done
else
  grep -q -- '--profile web --dump-config' "$TMP/calls.log" || { echo "base provider verification missing" >&2; exit 1; }
fi
# A second run must not duplicate or refuse the managed patch.
ABH_TEST_LOG="$TMP/calls.log" ABH_HOME="$TMP/.abh" PATH="$TMP/bin:$PATH" \
  AGENTBRAIN_ASSUME_YES=1 bash "$ROOT/scripts/setup/setup-abh.sh" >/dev/null
printf 'test-abh-integration: PASS\n'
