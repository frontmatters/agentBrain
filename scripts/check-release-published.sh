#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-release-published.sh — advisory: is the current VERSION published as a
# Gitea release? NON-BLOCKING by design — during development VERSION legitimately
# runs ahead of the last release, so this never hard-fails a push/build. It is a
# reminder at deploy time so a bumped version is not silently left unreleased.
#
# Exit codes: 0 = published OR cannot determine (Gitea unreachable / no token),
#             3 = confirmed unpublished (caller may surface a reminder).
# Test hook: RELEASE_TAGS_OVERRIDE="v1.5.6 v1.6.0 ..." injects the tag set,
#            bypassing the network.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION" 2>/dev/null)"
[ -n "$VERSION" ] || { echo "check-release-published: no VERSION" >&2; exit 0; }
TAG="v${VERSION}"
GITEA_OWNER="${GITEA_OWNER:-frontmatters}"
GITEA_REPO="${GITEA_REPO:-agentBrain-dev}"

# ── Public-channel parity (the version-jump-disco guard) ──────────────────────
# Every canonical release tag (vX.Y.Z) from PUBLIC_BASELINE up must exist on
# the public GitHub repo: a tag that only lives in the private dev repo is a
# release nobody could install — exactly how v1.7.0 sat missing publicly for
# nine days (found 2026-08-11). Unreachable network = skip (advisory).
# PARITY_STRICT=1 (the publisher's post-publish verify) makes a gap fatal;
# the default (doctor/deploy) warns loudly but does not block — a freshly cut
# tag is legitimately unpublished for the minutes the release pipeline runs.
PUBLIC_URL="${AGENTBRAIN_GITHUB_URL:-https://github.com/frontmatters/agentBrain.git}"
PUBLIC_BASELINE="${PUBLIC_BASELINE:-1.6.0}" # first version ever published publicly
_pub_tmp="$(mktemp -t ab-pub-tags.XXXXXX)"
GIT_TERMINAL_PROMPT=0 git ls-remote --tags "$PUBLIC_URL" 'refs/tags/v*' >"$_pub_tmp" 2>/dev/null &
_pub_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
	kill -0 "$_pub_pid" 2>/dev/null || break
	sleep 0.5
done
kill "$_pub_pid" 2>/dev/null
wait "$_pub_pid" 2>/dev/null
pub_tags="$(awk -F/ '{print $NF}' "$_pub_tmp" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)"
rm -f "$_pub_tmp"
if [ -n "$pub_tags" ]; then
	missing=""
	for t in $(git -C "$ROOT" tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'); do
		ver="${t#v}"
		[ "$(printf '%s\n%s\n' "$PUBLIC_BASELINE" "$ver" | sort -V | head -1)" = "$PUBLIC_BASELINE" ] || continue
		printf '%s\n' "$pub_tags" | grep -qx "$t" || missing="$missing $t"
	done
	if [ -n "$missing" ]; then
		echo "⚠ check-release-published: release tag(s) NOT on the public channel:$missing" >&2
		echo "  A dev-only tag is a release nobody can install. Publish: bash scripts/publish-agentbrain-github.sh" >&2
		[ "${PARITY_STRICT:-0}" = "1" ] && exit 4
	else
		echo "check-release-published: public parity ok (canonical tags ≥ v$PUBLIC_BASELINE all on GitHub)"
	fi
else
	echo "check-release-published: public repo unreachable — parity skipped (advisory)."
fi

tags=""
if [ -n "${RELEASE_TAGS_OVERRIDE:-}" ]; then
	tags="$RELEASE_TAGS_OVERRIDE"
elif [ -n "${GITEA_URL:-}" ] && command -v jq >/dev/null 2>&1; then
	if [ -z "${GITEA_TOKEN:-}" ] && [ -f "$HOME/bin/gitea-helper.sh" ]; then
		# shellcheck disable=SC1091
		source "$HOME/bin/gitea-helper.sh" >/dev/null 2>&1 && GITEA_TOKEN="$(get_gitea_token 2>/dev/null)"
	fi
	api="$GITEA_URL/api/v1/repos/$GITEA_OWNER/$GITEA_REPO/releases?limit=50"
	resp="$(curl -fsS --max-time 8 ${GITEA_TOKEN:+-H "Authorization: token $GITEA_TOKEN"} "$api" 2>/dev/null)" || resp=""
	[ -n "$resp" ] && tags="$(printf '%s' "$resp" | jq -r '.[].tag_name' 2>/dev/null)"
fi

if [ -z "$tags" ]; then
	echo "check-release-published: cannot determine published releases — skipped (advisory)."
	exit 0
fi

# shellcheck disable=SC2086  # intentional split of the space/newline tag list
if printf '%s\n' $tags | grep -qx "$TAG"; then
	echo "check-release-published: v$VERSION is published ✅"
	exit 0
fi

echo "⚠ check-release-published: VERSION is $VERSION but no published release '$TAG' exists." >&2
echo "  Cut it:  bash scripts/release.sh && GITEA_URL=<gitea> bash scripts/publish-gitea-release.sh --prerelease" >&2
exit 3
