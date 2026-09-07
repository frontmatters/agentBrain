#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-bash32.sh.
#
# The check must reject a bash 4 construct in a script that runs on an install,
# and must not count one in a comment. bash -n on bash 5 accepts both, which is
# why report-stale went red on every fresh Mac (macOS /bin/bash is 3.2) while
# every syntax check stayed green.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-bash32.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# The check resolves its root from its own location, so run it against a copy.
mkdir -p "$TMP/scripts/checks" "$TMP/system"
cp "$CHECK" "$TMP/scripts/checks/"
cd "$TMP" || exit 1

printf '#!/usr/bin/env bash\ndeclare -A seen\nseen[a]=1\n' > scripts/bad.sh
bash -n scripts/bad.sh || { echo "NEGATIVE CASE INVALID: bash -n should accept the fixture (that is the point)" >&2; exit 1; }
if bash scripts/checks/check-bash32.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-bash32 accepted declare -A in scripts/bad.sh" >&2
	exit 1
fi

printf '#!/usr/bin/env bash\n# no mapfile here, bash 3.2\necho ok\n' > scripts/bad.sh
if ! bash scripts/checks/check-bash32.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-bash32 counted a construct named in a comment" >&2
	exit 1
fi

printf '#!/usr/bin/env bash\nx="$(echo A)"\ncase "${x,,}" in a) ;; esac\n' > scripts/bad.sh
if bash scripts/checks/check-bash32.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-bash32 accepted \${x,,}" >&2
	exit 1
fi
echo "negative case holds: check-bash32 rejects declare -A and \${x,,}, ignores comments"
