#!/usr/bin/env bats

setup() {
  SHARED_LIB="$BATS_TEST_DIRNAME/../manifest.sh"
  source "$SHARED_LIB"
  export TMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "manifest_validate accepts minimal valid manifest" {
  cat > "$TMP_DIR/m.yml" <<EOF
version: 1
project: demo-project
include:
  - projects/demo-project/index.md
exclude: []
transformations: {}
EOF
  run manifest_validate "$TMP_DIR/m.yml"
  [ "$status" -eq 0 ]
}

@test "manifest_validate rejects missing version" {
  cat > "$TMP_DIR/m.yml" <<EOF
project: demo
include: []
EOF
  run manifest_validate "$TMP_DIR/m.yml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version"* ]]
}

@test "manifest_validate rejects unknown version" {
  cat > "$TMP_DIR/m.yml" <<EOF
version: 99
project: demo
include: []
EOF
  run manifest_validate "$TMP_DIR/m.yml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported version"* ]]
}

@test "manifest_validate rejects absolute paths in include" {
  cat > "$TMP_DIR/m.yml" <<EOF
version: 1
project: demo
include:
  - /absolute/path/notes.md
EOF
  run manifest_validate "$TMP_DIR/m.yml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute"* ]]
}

@test "manifest_validate rejects missing project field" {
  cat > "$TMP_DIR/m.yml" <<EOF
version: 1
include: []
EOF
  run manifest_validate "$TMP_DIR/m.yml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"project"* ]]
}
