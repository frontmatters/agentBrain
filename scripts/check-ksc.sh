#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-ksc.sh — Enforce the ksc triad's repo-side discipline (system/versioning.md):
# Keep a Changelog structure, the public versioning policy doc, and Conventional
# Commits on recent history. Structural parity (skills index, addon manifests) is
# covered by check-skills-index.sh and check-addons.sh; this check covers the
# release-hygiene half so `doctor` fails loudly when the changelog or commit
# discipline drifts. Cadence policy: releases are assembled, not streamed — a
# long-growing [Unreleased] block is healthy, a missing one is not.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

errors=0
warnings=0

# 1 — Keep a Changelog: CHANGELOG.md exists and carries an [Unreleased] section.
if [ ! -f CHANGELOG.md ]; then
	echo "check-ksc: FAIL — CHANGELOG.md missing" >&2
	errors=$((errors + 1))
elif ! grep -q '^## \[Unreleased\]' CHANGELOG.md; then
	echo "check-ksc: FAIL — CHANGELOG.md has no '## [Unreleased]' section (Keep a Changelog)" >&2
	errors=$((errors + 1))
fi

# 2 — The policy doc itself must exist (the checklist promote/demote depends on).
if [ ! -f system/versioning.md ]; then
	echo "check-ksc: FAIL — system/versioning.md missing (ksc policy doc)" >&2
	errors=$((errors + 1))
fi

# 3 — Conventional Commits on recent history. Warn-only: history may contain
#     merges and imported commits; the goal is drift detection, not archaeology.
conventional='^(feat|fix|docs|test|chore|refactor|perf|ci|build|style|revert|learn)(\([a-z0-9._/-]+\))?!?: '
bad_subjects="$(git log -20 --no-merges --format='%s' 2>/dev/null | grep -Ev "$conventional" || true)"
if [ -n "$bad_subjects" ]; then
	count="$(printf '%s\n' "$bad_subjects" | wc -l | tr -d ' ')"
	echo "check-ksc: WARN — $count of last 20 non-merge commits are not Conventional Commits:" >&2
	printf '%s\n' "$bad_subjects" | head -5 | sed 's/^/  - /' >&2
	warnings=$((warnings + 1))
fi

if [ "$errors" -gt 0 ]; then
	echo "check-ksc: $errors error(s), $warnings warning(s)" >&2
	exit 1
fi
echo "check-ksc: ok ($warnings warning(s))"
