#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-bash32.sh.
#
# The check must reject a bash 4 construct in a script that runs on an install,
# and must not count one in a comment. bash -n on bash 5 accepts both, which is
# why report-stale went red on every fresh Mac (macOS /bin/bash is 3.2) while
# every syntax check stayed green.
#
# It must also reject `. <(cmd)`, which is not a bash 4 construct at all: it
# parses and runs everywhere, and on 3.2 it defines nothing and says nothing.
# That arm was added and did not fire, because each hit is matched a second
# time on the "path:line:" form and the leading-context class did not admit the
# colon. An arm that never fires reads exactly like a clean tree.
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
printf '#!/usr/bin/env bash\n. <(echo "f(){ :; }")\n' > scripts/bad.sh
bash -n scripts/bad.sh || { echo "NEGATIVE CASE INVALID: bash -n should accept the fixture" >&2; exit 1; }
if bash scripts/checks/check-bash32.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-bash32 accepted sourcing from a process substitution" >&2
	exit 1
fi

# The same construct one level in, to prove the arm is not anchored to column 0.
printf '#!/usr/bin/env bash\nf() {\n\tsource <(echo x)\n}\n' > scripts/bad.sh
if bash scripts/checks/check-bash32.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-bash32 missed an indented source <(...)" >&2
	exit 1
fi

echo "negative case holds: check-bash32 rejects declare -A, \${x,,} and . <(...), ignores comments"
