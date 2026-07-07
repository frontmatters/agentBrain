#!/usr/bin/env bash
# check-node-bootstrap.sh — Ensure Pi bootstrap uses nvm-managed Node, not Homebrew Node.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0
fail() {
	printf 'FAIL: %s\n' "$*" >&2
	failures=$((failures + 1))
}

BREWFILE="system/pi-config/setup/Brewfile"
BOOTSTRAP="scripts/bootstrap-macos.sh"
PREREQS="scripts/install-prerequisites.sh"
CONFIGURE_PI="scripts/configure-pi.sh"

if grep -Eq '^[[:space:]]*brew[[:space:]]+"node(@[^"]*)?"' "$BREWFILE"; then
	fail 'Brewfile installs Homebrew Node; Node/npm should be managed via nvm'
fi

# nvm/npm logic lives in install-prerequisites.sh; bootstrap orchestrates it
for pattern in 'load_nvm\(\)' 'install_nvm\(\)' 'nvm install --lts' 'nvm use --lts'; do
	if ! grep -Eq "$pattern" "$PREREQS"; then
		fail "install-prerequisites.sh missing required nvm/npm pattern: $pattern"
	fi
done

# Pi install lives in configure-pi.sh
grep -q 'npm install -g @earendil-works/pi-coding-agent' "$CONFIGURE_PI" ||
	fail 'configure-pi.sh missing Pi install command'

# bootstrap must delegate to install-prerequisites.sh
grep -q 'install-prerequisites.sh' "$BOOTSTRAP" || fail 'bootstrap-macos.sh does not call install-prerequisites.sh'

if grep -R "brew install node\|brew \"node\"" README.md system scripts .github 2>/dev/null | grep -v 'not Homebrew\|not install Homebrew\|managed via nvm'; then
	fail 'documentation still appears to recommend Homebrew Node'
fi

if ! grep -q 'nvm-managed Node' README.md; then
	fail 'README does not document nvm-managed Node for Pi bootstrap'
fi

if [[ "$failures" -gt 0 ]]; then
	printf 'Node bootstrap check failed (%d issue(s)).\n' "$failures" >&2
	exit 1
fi

printf 'Node bootstrap check passed.\n'
