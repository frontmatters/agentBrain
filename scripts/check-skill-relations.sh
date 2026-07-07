#!/usr/bin/env bash
# check-skill-relations.sh — validate the `related:` frontmatter field
# across all skills, and enforce reciprocity.
#
# Rules:
#   1. Every value in a `related:` list must point to an existing skill
#      (a SKILL.md somewhere in system/skills/ or local/skills/ with
#      matching folder name OR matching `name:` frontmatter).
#   2. If skill A lists B in its related, then skill B must list A back.
#   3. Self-references are not allowed.
#
# Exit codes: 0 ok, 1 errors found.
#
# Bash 3.2 compatible — uses parallel indexed arrays instead of `declare -A`.
#
# Usage: bash scripts/check-skill-relations.sh

set -uo pipefail

resolve_brain_dir() {
    if command -v realpath >/dev/null 2>&1; then
        realpath "$HOME/agentBrain" 2>/dev/null && return 0
    fi
    if [ -d "$HOME/agentBrain" ]; then
        (cd "$HOME/agentBrain" && pwd -P) && return 0
    fi
    echo "check-skill-relations: cannot resolve ~/agentBrain" >&2
    exit 1
}

BRAIN_DIR="$(resolve_brain_dir)"

resolve_scope_root() {
    local p="$BRAIN_DIR/$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$p" 2>/dev/null && return 0
    fi
    (cd "$p" && pwd -P)
}

SYSTEM_SKILLS="$(resolve_scope_root system)/skills"
LOCAL_SKILLS="$(resolve_scope_root local)/skills"

# Parallel arrays: NAMES[i] is the skill name, RELATED[i] is its
# space-separated related list (may be empty).
NAMES=()
RELATED=()

read_fm_field() {
    local file="$1" field="$2"
    awk -v f="$field" '
        BEGIN { in_fm=0 }
        /^---[[:space:]]*$/ { in_fm = !in_fm; if (in_fm == 0) exit; next }
        in_fm && $0 ~ "^"f":" {
            sub("^"f":[[:space:]]*", "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            print
            exit
        }
    ' "$file"
}

parse_related_list() {
    local raw="$1"
    raw="${raw#[}"; raw="${raw%]}"
    echo "$raw" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | tr '\n' ' '
}

scan_skills_dir() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local skill_md folder name related_raw related_list
    for skill_md in "$dir"/*/SKILL.md; do
        [ -f "$skill_md" ] || continue
        folder="$(basename "$(dirname "$skill_md")")"
        name="$(read_fm_field "$skill_md" name)"
        [ -z "$name" ] && name="$folder"
        related_raw="$(read_fm_field "$skill_md" related)"
        related_list=""
        [ -n "$related_raw" ] && related_list="$(parse_related_list "$related_raw")"
        NAMES+=("$name")
        RELATED+=("$related_list")
    done
}

# Lookup: index of a skill name in NAMES, or -1
index_of() {
    local target="$1" i
    for (( i = 0; i < ${#NAMES[@]}; i++ )); do
        if [ "${NAMES[$i]}" = "$target" ]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
}

scan_skills_dir "$SYSTEM_SKILLS"
scan_skills_dir "$LOCAL_SKILLS"

errors=0

for (( i = 0; i < ${#NAMES[@]}; i++ )); do
    skill="${NAMES[$i]}"
    related="${RELATED[$i]}"
    [ -z "$related" ] && continue
    for target in $related; do
        # Rule 3: no self-references
        if [ "$target" = "$skill" ]; then
            echo "FAIL: $skill lists itself in related: (self-reference)" >&2
            errors=$((errors + 1))
            continue
        fi
        # Rule 1: target must exist
        target_idx="$(index_of "$target")"
        if [ "$target_idx" = "-1" ]; then
            echo "FAIL: $skill → $target — target skill does not exist" >&2
            errors=$((errors + 1))
            continue
        fi
        # Rule 2: reciprocity
        target_related="${RELATED[$target_idx]}"
        if ! echo " $target_related " | grep -q " $skill "; then
            echo "FAIL: $skill lists $target but $target does not list $skill back (non-reciprocal)" >&2
            errors=$((errors + 1))
        fi
    done
done

if [ "$errors" -gt 0 ]; then
    echo "" >&2
    echo "check-skill-relations: $errors error(s)" >&2
    exit 1
fi

scanned=${#NAMES[@]}
with_related=0
for r in "${RELATED[@]}"; do
    [ -n "$r" ] && with_related=$((with_related + 1))
done
echo "check-skill-relations: all relations valid ($scanned skills scanned, $with_related with related: field)"
exit 0
