#!/usr/bin/env bash
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
		--arg url "$url" --arg sha "$sha" --arg privacy "$privacy" \
		'. += [{id: $id, name: $name, version: $version, url: $url, sha256: $sha, privacy: $privacy}]' \
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
