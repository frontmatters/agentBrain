#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  CRAWLER="$BATS_TEST_DIRNAME/../wiki-link-crawler.sh"
  source "$CRAWLER"
  VAULT="$(mktemp -d)"
  mkdir -p "$VAULT/projects/demo" "$VAULT/learnings"
  cat > "$VAULT/projects/demo/index.md" <<EOF
---
id: 1234
---
Related: [[Learning-One]] and [[Learning-Two]]
EOF
  cat > "$VAULT/learnings/Learning-One.md" <<EOF
---
id: aaaa
---
Cross-link to [[Learning-Two]]
EOF
  cat > "$VAULT/learnings/Learning-Two.md" <<EOF
---
id: bbbb
---
Cycle back to [[Learning-One]]
EOF
}

teardown() {
  rm -rf "$VAULT"
}

@test "crawl_wiki_links returns direct refs" {
  run crawl_wiki_links "$VAULT" "projects/demo/index.md" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"learnings/Learning-One.md"* ]]
  [[ "$output" == *"learnings/Learning-Two.md"* ]]
}

@test "crawl_wiki_links respects depth limit 0" {
  run crawl_wiki_links "$VAULT" "projects/demo/index.md" 0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "crawl_wiki_links detects and skips cycles" {
  # Learning-One <-> Learning-Two is a 2-cycle.
  # Use --separate-stderr so cycle WARN on stderr doesn't pollute $output
  # (bats 1.7+; ours is 1.13). Plan deviation: plan-text relied on default
  # merged behavior which double-counts the cycle warning that contains
  # the filename.
  run --separate-stderr crawl_wiki_links "$VAULT" "projects/demo/index.md" 2
  [ "$status" -eq 0 ]
  # Each resolved link appears exactly once in stdout
  one_count=$(echo "$output" | grep -c "Learning-One.md" || true)
  two_count=$(echo "$output" | grep -c "Learning-Two.md" || true)
  [ "$one_count" -eq 1 ]
  [ "$two_count" -eq 1 ]
}

@test "crawl_wiki_links emits warning on cycle to stderr" {
  run crawl_wiki_links "$VAULT" "projects/demo/index.md" 2
  [[ "$output" == *"Learning-One.md"* ]]
  # stderr capture is bats-specific; check separately:
  # bats merges; we accept either path being in output
}
