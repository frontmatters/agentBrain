#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-function-exit.sh: the ratchet must refuse a NEW branch
# that ends on a bare && chain, and must stay silent about one that has a
# fallback. Without this, a check that never fires looks identical to a clean
# tree.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts/checks"
cp "$ROOT_DIR/scripts/checks/check-function-exit.sh" "$TMP/scripts/checks/"
printf '{ "unguarded": 0 }\n' > "$TMP/scripts/checks/.function-exit-ratchet.json"

# The offender: the && is the last statement of the taken branch.
cat > "$TMP/offender.sh" <<'SH'
#!/usr/bin/env bash
recipe() {
	if [ "$1" = darwin ]; then
		command -v brew >/dev/null 2>&1 && echo "brew install thing"
	fi
}
SH

# The guarded twin: same shape, explicit fallback, must NOT be flagged.
cat > "$TMP/guarded.sh" <<'SH'
#!/usr/bin/env bash
recipe() {
	if [ "$1" = darwin ]; then
		command -v brew >/dev/null 2>&1 && echo "brew install thing" || true
	fi
}
SH

cd "$TMP" || exit 1
git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm t

out="$(bash scripts/checks/check-function-exit.sh 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
	echo "NEGATIVE CASE FAILED: the ratchet accepted a new unguarded && chain" >&2
	echo "$out" >&2
	exit 1
fi
if printf '%s' "$out" | grep -q 'guarded\.sh'; then
	echo "NEGATIVE CASE FAILED: flagged the branch that has a || fallback" >&2
	exit 1
fi
echo "negative case holds: check-function-exit refuses a new unguarded && chain"
