#!/usr/bin/env bash
# scanman-init.sh — create a canonical scanman workspace.
#
# Modes:
#   focused              (default, back-compat) — produces 00..05 + index.md
#   reproduction-spec    (v0.6)                 — adds DISTILLATE/ and LEARNINGS.md
#
# Delegates to the Rust binary when available; otherwise falls back to a
# pure-bash implementation that mirrors rust-impl/src/init.rs behavior.
#
# Usage:
#   scanman-init.sh [--mode=focused|reproduction-spec] <slug> [repo-path] [goal...]
#   scanman-init.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_scanman-lib.sh
. "${SCRIPT_DIR}/_scanman-lib.sh"

usage() {
    cat <<'EOF'
scanman-init.sh — create a canonical scanman workspace

USAGE:
  scanman-init.sh [--mode=MODE] <slug> [repo-path] [goal...]
  scanman-init.sh --help

OPTIONS:
  --mode=MODE       focused (default) | reproduction-spec
                    May also be set via SCANMAN_MODE env var.
  --help, -h        Show this help.

ARGUMENTS:
  slug              Workspace slug (lowercase-kebab-case). Required.
  repo-path         Path to the repo being analyzed (optional).
  goal              Free-form goal description (optional, trailing words).

OUTPUT:
  Creates ~/agentBrain/local/research/repo-distill/<slug>/ with:
    - index.md (with method version + UUID5 frontmatter)
    - 00..05 canonical files
  In reproduction-spec mode, also creates:
    - DISTILLATE/ (empty)
    - LEARNINGS.md (skeleton)

ENV:
  SCANMAN_MODE          Default mode when --mode= not supplied.
  AGENTBRAIN_DIR        Override vault root (default: $HOME/agentBrain).

EXAMPLES:
  scanman-init.sh wterm-rebuild ~/Developer/wterm-rebuild-zig
  scanman-init.sh --mode=reproduction-spec wterm-distill ~/Developer/wterm-rebuild-zig
EOF
}

# --- arg parsing ---------------------------------------------------------------

for a in "$@"; do
    case "$a" in
        --help|-h) usage; exit 0 ;;
    esac
done

parse_mode_flag "$@"
ARGS=("${SCANMAN_PASSTHRU_ARGS[@]:-}")
MODE="$SCANMAN_PARSED_MODE"

if [ "${#ARGS[@]}" -eq 0 ] || [ -z "${ARGS[0]:-}" ]; then
    echo "ERROR: <slug> is required" >&2
    echo "" >&2
    usage >&2
    exit 2
fi

SLUG="${ARGS[0]}"
REPO_PATH="${ARGS[1]:-}"
GOAL=""
if [ "${#ARGS[@]}" -gt 2 ]; then
    GOAL="${ARGS[*]:2}"
fi

# Validate slug (kebab-case, lowercase).
if ! [[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    die "slug must be lowercase kebab-case: $SLUG"
fi

# --- delegate to Rust binary when available ------------------------------------

BIN="$(detect_scanman_bin)"
if [ -n "$BIN" ] && [ "$MODE" = "focused" ]; then
    # The current Rust binary only knows focused mode; delegate only when MODE=focused.
    info "delegating to Rust binary: $BIN init"
    if [ -n "$REPO_PATH" ] && [ -n "$GOAL" ]; then
        exec "$BIN" init "$SLUG" "$REPO_PATH" $GOAL
    elif [ -n "$REPO_PATH" ]; then
        exec "$BIN" init "$SLUG" "$REPO_PATH"
    else
        exec "$BIN" init "$SLUG"
    fi
fi

# --- pure-bash fallback --------------------------------------------------------

VAULT="$SCANMAN_AGENTBRAIN_DIR"
TARGET="$VAULT/local/research/repo-distill/$SLUG"

if [ -e "$TARGET" ]; then
    die "Scanman target already exists: $TARGET"
fi

mkdir -p "$TARGET"

TODAY="$(date +%F)"
VERSION="$(scanman_version)"
TPL_DIR="$VAULT/templates"

# Helper — copy template, prepend frontmatter, replace placeholders.
write_doc() {
    local filename="$1"
    local artifact="$2"
    local tpl="$3"

    local stem="${filename%.md}"
    local rel="local/research/repo-distill/$SLUG/$stem"
    local uid
    uid="$(bash "$VAULT/scripts/uuid5-gen.sh" "$rel")"

    local body=""
    if [ -f "$TPL_DIR/$tpl" ]; then
        body="$(cat "$TPL_DIR/$tpl")"
    else
        body="# $stem\n\n[fill in]"
    fi

    {
        if [ "$filename" = "index.md" ]; then
            # Index template usually carries its own frontmatter; do replacements inline.
            printf '%s\n' "$body" \
                | sed -e "s|YYYY-MM-DD|$TODAY|g" \
                      -e "s|<UUID5>|$uid|g" \
                      -e "s|<repo-name>|$SLUG|g"
        else
            # Other docs: prepend uniform frontmatter.
            printf -- '---\ndate: %s\ntype: research\ntags: [repo-distill, architecture, analysis]\nstatus: active\nid: %s\nrepo: %s\nartifact: %s\nsource: session\n---\n' \
                "$TODAY" "$uid" "$SLUG" "$artifact"
            printf '%s\n' "$body"
        fi
    } > "$TARGET/$filename"
}

write_doc "index.md"              "index"           "repo-distill-index.md"
write_doc "00-file-inventory.md"  "file-inventory"  "repo-distill-file-inventory.md"
write_doc "00b-dependency-map.md" "dependency-map"  "repo-distill-dependency-map.md"
write_doc "01-system-map.md"      "system-map"      "repo-distill-system-map.md"
write_doc "02-runtime-model.md"   "runtime-model"   "repo-distill-runtime-model.md"
write_doc "03-core-primitives.md" "core-primitives" "repo-distill-core-primitives.md"
write_doc "04-risk-and-bloat.md"  "risk-and-bloat"  "repo-distill-risk-and-bloat.md"
write_doc "05-redesign-v1.md"     "redesign-v1"     "repo-distill-redesign-v1.md"

# Index post-process (mirror init.rs semantics with simple sed substitutions).
INDEX="$TARGET/index.md"
TMP="$(mktemp)"
{
    if [ -n "$REPO_PATH" ]; then
        sed -e "s|- Repo URL/path|- Repo URL/path: \`$REPO_PATH\`|" "$INDEX"
    else
        sed -e "s|- Repo URL/path|- Repo URL/path:|" "$INDEX"
    fi
} > "$TMP" && mv "$TMP" "$INDEX"

sed -i.bak \
    -e "s|- Version/ref/commit analyzed|- Version/ref/commit analyzed:|" \
    -e "s|- Related notes/docs|- Related notes/docs:|" \
    -e "s|- Scanman method version|- Scanman method version: \`$VERSION\`|" \
    -e "s|- Current phase|- Current phase: initialized|" \
    -e "s|- Known blockers|- Known blockers:|" \
    "$INDEX"
rm -f "$INDEX.bak"

if [ -n "$REPO_PATH" ]; then
    sed -i.bak \
        -e "s|- Next action|- Next action: run \`bash scripts/scanman-scan.sh <repo-path> $SLUG\` and then manually enrich the generated docs|" \
        "$INDEX"
else
    sed -i.bak \
        -e "s|- Next action|- Next action: populate \`00-file-inventory.md\`|" \
        "$INDEX"
fi
rm -f "$INDEX.bak"

# Mode-specific extras.
if [ "$MODE" = "reproduction-spec" ]; then
    mkdir -p "$TARGET/DISTILLATE"
    cat > "$TARGET/LEARNINGS.md" <<EOF
# Learnings — $SLUG reproduction-spec execution

> Capture observations during fase 3-5. See SCANMAN_REPRO_SPEC_PLAYBOOK.md §5.

## Distillate-writing observations

- (none yet)

## Gate-failures encountered

- (none yet)

## Blind-rebuild gaps (fase 5)

- (none yet)

## Recommendations for scanman v0.7+

- (none yet)
EOF
    # Note the mode in index.md so validate can route correctly.
    if ! grep -q "^mode:" "$INDEX" 2>/dev/null; then
        # Insert under the first frontmatter '---' (right after date line).
        awk -v mode="reproduction-spec" '
            BEGIN { inserted=0; fm=0 }
            /^---$/ { fm++; print; next }
            fm==1 && !inserted && /^date:/ { print; print "mode: " mode; inserted=1; next }
            { print }
        ' "$INDEX" > "$TMP" && mv "$TMP" "$INDEX"
    fi
fi

echo "Initialized scanman workspace: $TARGET"
echo "Mode: $MODE"
if [ -n "$REPO_PATH" ]; then
    echo "Next: bash $SCRIPT_DIR/scanman-scan.sh --mode=$MODE $TARGET"
fi
