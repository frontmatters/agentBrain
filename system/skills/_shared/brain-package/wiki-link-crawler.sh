#!/usr/bin/env bash
# wiki-link-crawler.sh — transitive [[wiki-link]] crawler with cycle detect + depth limit.

set -euo pipefail

# Usage: crawl_wiki_links <vault-root> <start-rel-path> <max-depth>
# Prints each resolved vault-relative path on its own line.
# Skips cycles (seen-set), emits WARN to stderr on detected cycle.
crawl_wiki_links() {
  local vault="$1"
  local start="$2"
  local max_depth="$3"

  # seen-set: associative array of vault-rel paths
  declare -A seen
  declare -a queue
  declare -a depths

  queue+=("$start")
  depths+=(0)
  seen["$start"]=1

  while [ ${#queue[@]} -gt 0 ]; do
    local current="${queue[0]}"
    local depth="${depths[0]}"
    queue=("${queue[@]:1}")
    depths=("${depths[@]:1}")

    [ "$depth" -ge "$max_depth" ] && continue

    local file="$vault/$current"
    [ -f "$file" ] || continue

    # Extract [[Link-Name]] patterns
    local links
    links=$(grep -oE '\[\[[^]]+\]\]' "$file" 2>/dev/null | sed 's/^\[\[//; s/\]\]$//' || true)

    while IFS= read -r link; do
      [ -z "$link" ] && continue

      # Resolve link to a vault path:
      # 1. Try learnings/<link>.md
      # 2. Try projects/<link>/index.md
      # 3. Try <link>.md anywhere (by basename match — Obsidian style)
      local resolved=""
      if [ -f "$vault/learnings/${link}.md" ]; then
        resolved="learnings/${link}.md"
      elif [ -f "$vault/projects/${link}/index.md" ]; then
        resolved="projects/${link}/index.md"
      else
        # Basename search (limited)
        local match
        match=$(find "$vault" -name "${link}.md" -type f 2>/dev/null | head -n 1 || true)
        if [ -n "$match" ]; then
          resolved="${match#$vault/}"
        fi
      fi

      [ -z "$resolved" ] && continue

      if [ -n "${seen[$resolved]:-}" ]; then
        echo "crawl_wiki_links: cycle skipped at $current -> $resolved" >&2
        continue
      fi

      seen["$resolved"]=1
      echo "$resolved"
      queue+=("$resolved")
      depths+=("$((depth + 1))")
    done <<< "$links"
  done
}
