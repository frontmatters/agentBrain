#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-sandbox-home.sh.
#
# The check must reject $HOME used to reach a path agentBrain owns, must accept
# the sanctioned ${AGENTBRAIN_HOME:-$HOME} form, and must leave a tool's own
# dotdir alone. The middle case is the one that matters: the first version of
# the check flagged all 28 call sites including the ones it had just fixed,
# because ${AGENTBRAIN_HOME:-$HOME} contains the literal "$HOME}" as well. A
# check that cannot tell right from wrong is worse than no check, because its
# output looks like work.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-sandbox-home.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# The check resolves its root from its own location, so run it against a copy.
mkdir -p "$TMP/scripts/checks" "$TMP/scripts/tests" "$TMP/scripts/lib"
cp "$CHECK" "$TMP/scripts/checks/"
cd "$TMP" || exit 1

run() { bash scripts/checks/check-sandbox-home.sh >/dev/null 2>&1; }

# 1. the defect: $HOME reaching agentBrain's own tree
printf '#!/usr/bin/env bash\nD="$HOME/agentBrain/vault"\n' > scripts/tests/probe.sh
if run; then
	echo "NEGATIVE CASE FAILED: accepted \$HOME/agentBrain in a test" >&2
	exit 1
fi

# 2. the same for an agent config directory the install writes
printf '#!/usr/bin/env bash\nS="$HOME/.claude/settings.json"\n' > scripts/tests/probe.sh
if run; then
	echo "NEGATIVE CASE FAILED: accepted \$HOME/.claude" >&2
	exit 1
fi

# 3. the sanctioned form must pass, even though it contains "$HOME}" itself
printf '#!/usr/bin/env bash\nD="${AGENTBRAIN_HOME:-$HOME}/agentBrain/vault"\n' > scripts/tests/probe.sh
if ! run; then
	echo "NEGATIVE CASE FAILED: rejected \${AGENTBRAIN_HOME:-\$HOME}, the form it asks for" >&2
	exit 1
fi

# 4. a tool's own dotdir is the machine's, not agentBrain's: it stays on $HOME
printf '#!/usr/bin/env bash\nexport NVM_DIR="${NVM_DIR:-$HOME/.nvm}"\nB="$HOME/.bun/bin"\n' > scripts/tests/probe.sh
if ! run; then
	echo "NEGATIVE CASE FAILED: flagged a tool location (~/.nvm, ~/.bun) that must stay on \$HOME" >&2
	exit 1
fi

# 5. a comment naming the defect is not the defect
printf '#!/usr/bin/env bash\n# never write "$HOME/agentBrain" here\necho ok\n' > scripts/tests/probe.sh
if ! run; then
	echo "NEGATIVE CASE FAILED: counted \$HOME/agentBrain named in a comment" >&2
	exit 1
fi

# 6. the state directory spelled in lower case, which is the same directory on a
# case-insensitive volume and a different string to every comparison
printf '#!/usr/bin/env bash\nS="${HOME_DIR}/.agentbrain"\n' > scripts/tests/probe.sh
if run; then
	echo "NEGATIVE CASE FAILED: accepted .agentbrain in lower case" >&2
	exit 1
fi

# 7. a launchd or systemd label is lower case by convention and is not a path
printf '#!/usr/bin/env bash\nLABEL="dev.agentbrain.loop"\nU="agentbrain-harness-web.service"\n' > scripts/tests/probe.sh
if ! run; then
	echo "NEGATIVE CASE FAILED: flagged a launchd label as a path" >&2
	exit 1
fi

# 8. an empty scope is an error, not a pass: a verdict needs a denominator
rm -rf scripts/tests scripts/lib
mkdir -p scripts/tests
if run; then
	echo "NEGATIVE CASE FAILED: reported a clean bill over an empty scope" >&2
	exit 1
fi

echo "negative case holds: check-sandbox-home rejects bare \$HOME and lower-case .agentbrain, accepts the override, spares tool dirs, labels and comments, and refuses an empty scope"
