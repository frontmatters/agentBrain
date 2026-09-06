#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-installer-version.sh: the installer banner names the installer, not the cwd.
#
# Piped through `curl | bash`, BASH_SOURCE is empty and dirname of nothing is
# ".": the old lookup read ./VERSION from wherever the shell stood. On a machine
# with an older checkout as cwd the banner said "installer v1.10.2-prerelease-69".
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
FN="$(sed -n '/^_ab_installer_version() {/,/^}/p' "$ROOT/scripts/installer/install.sh")"
[ -n "$FN" ] || { bad "present" "no _ab_installer_version in install.sh"; echo "FAIL test-installer-version" >&2; exit 1; }
WANT="$(tr -d '[:space:]' < "$ROOT/scripts/installer/VERSION")"

# 1. On disk: the VERSION beside the script.
# Run the function from a real file named install.sh, as the installer is when
# it sits on disk (bash -c has no script file, so BASH_SOURCE would be empty).
D="$(mktemp -d)"; printf '%s\n' "$FN" > "$D/install.sh"; printf '%s\n' "$WANT" > "$D/VERSION"
printf 'echo "$(_ab_installer_version)"\n' >> "$D/install.sh"
got="$(AB_INSTALLER_VERSION_URL=file:///nonexistent bash "$D/install.sh")"; rm -rf "$D"
[ "$got" = "$WANT" ] && ok "on-disk" "reads VERSION beside the script ($got)" || bad "on-disk" "got '$got', want '$WANT'"

# 2. Piped, standing in a directory with a foreign VERSION: never that file.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '9.9.9-prerelease-99\n' > "$T/VERSION"
printf '%s\n' "$FN" > "$T/fn.sh"
got="$(cd "$T" && printf 'AB_INSTALLER_VERSION_URL=file://%s/served; . ./fn.sh; _ab_installer_version\n' "$T" | bash)"
printf '0.0.7\n' > "$T/served"
got="$(cd "$T" && printf 'AB_INSTALLER_VERSION_URL=file://%s/served; . ./fn.sh; _ab_installer_version\n' "$T" | bash)"
[ "$got" = "0.0.7" ] && ok "piped" "fetches the served VERSION, ignores ./VERSION ($got)" || bad "piped" "got '$got' (./VERSION says 9.9.9-prerelease-99)"

# 3. Piped and offline: says so, never a number from the cwd.
got="$(cd "$T" && printf 'AB_INSTALLER_VERSION_URL=file://%s/absent; . ./fn.sh; _ab_installer_version\n' "$T" | bash)"
[ "$got" = "unknown" ] && ok "offline" "reports unknown" || bad "offline" "got '$got'"

[ "$fail" -ne 0 ] && { echo "FAIL test-installer-version" >&2; exit 1; }
echo "PASS test-installer-version"
