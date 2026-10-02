#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# ci.sh — the one CI entry point, for a source checkout and for a release.
#
# A source checkout carries the framework's test suites (scripts/tests/), so CI
# runs the full doctor there. A release leaves those out on purpose, and its
# full doctor refuses to run; what a release promises is that it installs and
# then passes the user doctor. So in a release CI does what a user does: install
# with `setup.sh --yes` into a throwaway home and vault, then run the user doctor
# and the brain command. The install runs on a copy of this tree, so running
# ci.sh never changes the checkout it is started from.
#
# The GitHub workflow and the factory's release check both call this script, so
# a release that is green in the release check is green on GitHub too.
#
# Usage: bash scripts/ci.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"

if [ -d "$ROOT/scripts/tests" ]; then
	echo "ci: source checkout: full doctor"
	exec bash "$ROOT/scripts/checks/doctor.sh" --ci
fi

echo "ci: release: install into a throwaway home, then the user doctor"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/agentBrain" "$T/sandbox-home/bin"
# A copy without the checkout's own vault link or install seed: the install
# makes its own.
(cd "$ROOT" && tar --exclude='./vault' --exclude='./local' --exclude='./brain.json' --exclude='./.git' -cf - .) | (cd "$T/agentBrain" && tar -xf -)
export GIT_CEILING_DIRECTORIES="$T"

run() { AGENTBRAIN_HOME="$T/sandbox-home" AGENTBRAIN_VAULT="$T/vault" AGENTBRAIN_SKIP_PI=1 "$@"; }

echo "ci: [1/3] setup.sh --yes"
if ! run bash "$T/agentBrain/setup.sh" --yes >"$T/install.log" 2>&1; then
	tail -30 "$T/install.log" >&2
	echo "ci: install failed" >&2
	exit 1
fi

echo "ci: [2/3] doctor --user"
(cd "$T/agentBrain" && run env AGENTBRAIN_ONBOARDING_PENDING_OK=1 bash scripts/checks/doctor.sh --user --summary)

echo "ci: [3/3] brain --version"
run "$T/sandbox-home/bin/brain" --version
echo "ci: release installs and passes the user doctor"
