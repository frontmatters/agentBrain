#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-toolpaths.sh: a script that probes a user-scoped tool
# without loading the paths is rejected, and one that loads them passes.
#
# The guard exists because the opposite went unnoticed for months: shorthand's
# installer probed bun raw while its check probed with the paths loaded, so the
# install skipped its own setup step and the check called the result drift.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-toolpaths.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts/checks" "$TMP/scripts/lib" "$TMP/system/addons/demo"
cp "$CHECK" "$TMP/scripts/checks/"
printf '# loader fixture\n' > "$TMP/scripts/lib/_toolpaths.sh"
cd "$TMP" || exit 1

probe_raw() { printf '#!/usr/bin/env bash\ncommand -v bun >/dev/null 2>&1 || exit 1\n' > system/addons/demo/install.sh; }
probe_loaded() {
	printf '#!/usr/bin/env bash\n_ab_tp="x/scripts/lib/_toolpaths.sh"\n. "$_ab_tp"\ncommand -v bun >/dev/null 2>&1 || exit 1\n' \
		> system/addons/demo/install.sh
}

# 1. A raw probe is rejected.
probe_raw
if bash scripts/checks/check-toolpaths.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-toolpaths accepted a raw 'command -v bun'" >&2; exit 1
fi

# 2. The same script passes once it loads the paths.
probe_loaded
if ! bash scripts/checks/check-toolpaths.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-toolpaths rejected a script that loads the paths" >&2; exit 1
fi

# 3. A registered exemption is honoured, so a documented exception is possible.
probe_raw
printf 'toolpaths\tsystem/addons/demo/install.sh\tstructural\tFixture row proving a registered exemption is honoured by the check.\n' \
	> scripts/lib/exemptions.tsv
if ! bash scripts/checks/check-toolpaths.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-toolpaths ignored a registered exemption" >&2; exit 1
fi

# 4. A sweep that examines nothing must fail, not report a clean bill.
: > scripts/lib/exemptions.tsv
printf '#!/usr/bin/env bash\necho nothing to probe\n' > system/addons/demo/install.sh
if bash scripts/checks/check-toolpaths.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-toolpaths passed with nothing examined" >&2; exit 1
fi

echo "negative case holds: check-toolpaths rejects raw probes, honours exemptions, and refuses an empty sweep"
