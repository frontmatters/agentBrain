#!/usr/bin/env bash
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
