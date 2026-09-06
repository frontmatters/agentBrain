#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for run-negative-cases.sh: a case that stops rejecting must be
# reported, not skipped. Without this, the runner could pass by finding nothing.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks/negative"
cp "$ROOT_DIR/scripts/checks/run-negative-cases.sh" "$TMP/scripts/checks/"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/scripts/checks/negative/broken.sh"
cd "$TMP" || exit 1
if bash scripts/checks/run-negative-cases.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: the runner passed while a case was failing" >&2
	exit 1
fi
echo "negative/run-negative-cases: a failing case is reported"
