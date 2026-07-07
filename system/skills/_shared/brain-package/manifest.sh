#!/usr/bin/env bash
# manifest.sh — load and validate a brain-package manifest YAML.

set -euo pipefail

MANIFEST_SUPPORTED_VERSIONS=(1)

manifest_validate() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "manifest_validate: file not found: $file" >&2
    return 2
  fi

  # version
  local version
  version=$(yq -r '.version // ""' "$file")
  if [ -z "$version" ]; then
    echo "manifest_validate: missing required field 'version'" >&2
    return 1
  fi
  local supported=0
  for v in "${MANIFEST_SUPPORTED_VERSIONS[@]}"; do
    [ "$v" = "$version" ] && supported=1
  done
  if [ "$supported" -eq 0 ]; then
    echo "manifest_validate: unsupported version: $version (supported: ${MANIFEST_SUPPORTED_VERSIONS[*]})" >&2
    return 1
  fi

  # project
  local project
  project=$(yq -r '.project // ""' "$file")
  if [ -z "$project" ]; then
    echo "manifest_validate: missing required field 'project'" >&2
    return 1
  fi

  # include paths: must be vault-relative
  local includes
  includes=$(yq -r '.include[]?' "$file")
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [[ "$p" == /* ]]; then
      echo "manifest_validate: include path is absolute (must be vault-relative): $p" >&2
      return 1
    fi
  done <<< "$includes"

  return 0
}

# Helper: get a field, with default
manifest_get() {
  local file="$1"
  local path="$2"
  local default="${3:-}"
  local val
  val=$(yq -r "$path // \"\"" "$file" 2>/dev/null || echo "")
  if [ -z "$val" ] && [ -n "$default" ]; then
    echo "$default"
  else
    echo "$val"
  fi
}
