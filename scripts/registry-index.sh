#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# registry-index.sh — Generate a registry index.json from packaged addon zips.
# Usage:
#   bash scripts/registry-index.sh --url-template <tpl> [--dir <zips>] [--name <reg>] [--out <file>]
# The template knows {id}, {version}, {tag} (= addon-<id>-v<version>) and {file}:
#   GitHub releases: 'https://github.com/OWNER/REPO/releases/download/{tag}/{file}'
#   static hosting:  'https://example.com/addons/{file}'
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/../agentBrain-releases/addons"
NAME="agentbrain"
TEMPLATE=""
OUT=""

while [ $# -gt 0 ]; do
	case "$1" in
		--url-template) TEMPLATE="$2"; shift 2 ;;
		--dir)  DIR="$2"; shift 2 ;;
		--name) NAME="$2"; shift 2 ;;
		--out)  OUT="$2"; shift 2 ;;
		*) echo "Unknown arg: $1" >&2; exit 2 ;;
	esac
done
[ -n "$TEMPLATE" ] || { echo "--url-template is required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

mani_field() { printf '%s' "$1" | awk -v key="$2" '/^---[[:space:]]*$/{fm++;next} fm==1 && $0 ~ "^"key":" {sub("^"key":[[:space:]]*",""); sub(/[[:space:]]*#.*$/,""); print; exit}'; }

# Default author for addons without an explicit `author:` — the publishing vault's
# maintainer from brain.json (never hardcoded).
DEFAULT_MAINTAINER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("maintainer") or "unknown")' "$ROOT/brain.json" 2>/dev/null || echo unknown)"

entries="[]"
for zipf in "$DIR"/addon-*.zip; do
	[ -f "$zipf" ] || continue
	base="$(basename "$zipf")"
	stem="${base%.zip}"               # addon-<id>-v<version>
	version="${stem##*-v}"
	id="${stem#addon-}"; id="${id%-v"$version"}"
	# Keep-highest: if a newer version zip for this id is also present in DIR
	# (e.g. a stale older build left after a version bump), skip the older one so
	# it can never win the index entry. bash 3.2 safe (no assoc arrays).
	highest="$(printf '%s\n' "$DIR"/addon-"$id"-v*.zip | sed "s|.*/addon-${id}-v||; s|\.zip$||" | sort -V | tail -1)"
	[ "$version" = "$highest" ] || continue
	sha="$(awk '{print $1}' "$zipf.sha256")"
	manifest="$(unzip -p "$zipf" "$id/manifest.md")"
	name="$(mani_field "$manifest" name)"
	privacy="$(mani_field "$manifest" privacy)"
	# Attribution: explicit `author:` in the manifest, else the first-party default.
	author="$(mani_field "$manifest" author)"; [ -n "$author" ] || author="$DEFAULT_MAINTAINER"
	# License: explicit SPDX `license:`, else the framework default (Apache-2.0).
	license="$(mani_field "$manifest" license)"; [ -n "$license" ] || license="Apache-2.0"
	# Dependencies: `requires:` (space/comma-separated addon ids) -> JSON array.
	# Empty input must yield `[]`: `jq -R` reads line-by-line and emits nothing for
	# an empty stream, which would make --argjson choke on an empty string.
	requires="$(mani_field "$manifest" requires)"
	if [ -n "$requires" ]; then
		requires_json="$(printf '%s' "${requires//,/ }" | jq -Rc 'split(" ")|map(select(length>0))')"
	else
		requires_json="[]"
	fi
	tag="addon-$id-v$version"
	url="$TEMPLATE"
	url="${url//\{tag\}/$tag}"
	url="${url//\{file\}/$base}"
	url="${url//\{id\}/$id}"
	url="${url//\{version\}/$version}"
	# Guard: a malformed template (e.g. the brace-eating ${VAR:-...{file}} bug)
	# leaves unsubstituted braces or a non-http scheme. Refuse to emit such a
	# URL — a broken link must never reach a published index.
	case "$url" in
		*'{'* | *'}'*) echo "ERROR: unsubstituted placeholder in URL for $id: $url" >&2; exit 1 ;;
	esac
	case "$url" in
		http://* | https://* | file://*) ;;
		*) echo "ERROR: URL for $id has an unsupported scheme (need http/https/file): $url" >&2; exit 1 ;;
	esac
	entries="$(jq --arg id "$id" --arg name "$name" --arg version "$version" \
		--arg url "$url" --arg sha "$sha" --arg privacy "$privacy" --arg author "$author" \
		--arg license "$license" --argjson requires "$requires_json" \
		'. += [{id: $id, name: $name, version: $version, url: $url, sha256: $sha, privacy: $privacy, author: $author, license: $license, requires: $requires}]' \
		<<<"$entries")"
done

index="$(jq -n --arg name "$NAME" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--argjson addons "$entries" '{registry: $name, updated: $updated, addons: $addons}')"
if [ -n "$OUT" ]; then
	printf '%s\n' "$index" > "$OUT"
	echo "Wrote $OUT ($(printf '%s' "$index" | jq '.addons | length') addons)"
else
	printf '%s\n' "$index"
fi
