#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-verifiability.sh: a check with no negative case and no
# baseline entry must be refused. Without this the ratchet could silently accept
# everything, which is the failure it exists to prevent, one level up.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks/negative"
cp "$ROOT_DIR/scripts/checks/check-verifiability.sh" "$TMP/scripts/checks/"
printf '#!/usr/bin/env bash\necho ok\n' > "$TMP/scripts/checks/check-unbaselined.sh"
: > "$TMP/scripts/checks/negative/.baseline"
cd "$TMP" || exit 1
if bash scripts/checks/check-verifiability.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: accepted a check with no negative case and no baseline" >&2
	exit 1
fi
echo "negative/check-verifiability: an unbaselined check without a case is refused"
