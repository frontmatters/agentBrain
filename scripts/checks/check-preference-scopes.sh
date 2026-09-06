#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-preference-scopes.sh — Validate scoped preference model.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

failures=0
fail() {
	printf 'FAIL: %s\n' "$*" >&2
	failures=$((failures + 1))
}

require_grep() {
	local pattern="$1" file="$2" desc="$3"
	if [[ ! -f "$file" ]]; then
		fail "$desc: missing file $file"
		return
	fi
	if ! grep -Eq "$pattern" "$file"; then
		fail "$desc: expected pattern '$pattern' in $file"
	fi
}

# Like require_grep but matches if the pattern is in ANY of the given files.
# Tolerates the setup refactor: logic may be inline in setup.sh or in a setup-*.sh module.
require_grep_any() {
	local pattern="$1" desc="$2"; shift 2
	local f present=0
	for f in "$@"; do
		[[ -f "$f" ]] || continue
		present=1
		grep -Eq "$pattern" "$f" && return
	done
	if [[ "$present" -eq 0 ]]; then
		fail "$desc: none of the expected setup scripts exist ($*)"
	else
		fail "$desc: expected pattern '$pattern' in one of: $*"
	fi
}

# Setup/bootstrap must create and seed personal scope. setup.sh may inline this or
# delegate to modular setup-*.sh; accept the pattern in any of the setup scripts.
require_grep_any 'vault/preferences/personal' 'setup personal scope' \
	scripts/setup/setup.sh scripts/setup/setup-structure.sh scripts/setup/setup-templates.sh scripts/setup/setup-validation.sh
require_grep_any 'user-preferences.*README\.md|README\.md.*continue' 'setup excludes user-preferences README' \
	scripts/setup/setup.sh scripts/setup/setup-templates.sh
# bootstrap orchestrates setup.sh — verify the delegation exists
require_grep 'setup.sh' scripts/installer/bootstrap/macos.sh 'bootstrap delegates to setup.sh'

# Onboard docs must describe scopes and personal-first flow.
require_grep 'vault/preferences/personal' system/skills/onboard/SKILL.md 'onboard personal scope'
require_grep 'vault/preferences/organization' system/skills/onboard/SKILL.md 'onboard organization scope'
require_grep 'vault/preferences/team' system/skills/onboard/SKILL.md 'onboard team scope'
require_grep 'Personal first|personal/.*always' system/skills/onboard/SKILL.md 'onboard personal-first'
require_grep 'vault/preferences/organization/' system/agent-config/shared.md 'shared organization scope instruction'
require_grep 'vault/preferences/team/' system/agent-config/shared.md 'shared team scope instruction'
require_grep 'vault/preferences/personal/' system/agent-config/shared.md 'shared personal scope instruction'

# Public docs should not point real preferences to the legacy flat location.
if grep -R "real preferences → \`local/preferences/\`\|personalize them in \`local/preferences/\`" README.md user-preferences system .github 2>/dev/null; then
	fail 'legacy flat local/preferences/ documentation remains'
fi

# If local preferences exist, legacy flat markdown files should have been migrated.
if [[ -d vault/preferences ]]; then
	while IFS= read -r -d '' file; do
		fail "legacy flat preference file remains: $file"
	done < <(find vault/preferences -maxdepth 1 -type f -name '*.md' -print0)
fi

if [[ "$failures" -gt 0 ]]; then
	printf 'Preference scope check failed (%d issue(s)).\n' "$failures" >&2
	exit 1
fi

printf 'Preference scope check passed.\n'
