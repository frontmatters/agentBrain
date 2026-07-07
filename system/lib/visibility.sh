#!/usr/bin/env bash
# visibility.sh — shared filters for hidden/forgotten notes.
# Sourced by list-* skills and brain-* skills.

# is_hidden <path-to-md>
# Returns 0 if hidden, 1 if visible/absent.
# For project children: checks parent project's index.md (cascade).
is_hidden() {
    local file="$1"
    [ -z "$file" ] && return 1
    [ ! -f "$file" ] && return 1
    if grep -qE '^hidden:[[:space:]]*true[[:space:]]*$' "$file" 2>/dev/null; then
        return 0
    fi
    case "$file" in
        */local/projects/*/*.md)
            local project_dir="${file%/*}"
            local index="$project_dir/index.md"
            [ -f "$index" ] && [ "$index" != "$file" ] && \
                grep -qE '^hidden:[[:space:]]*true[[:space:]]*$' "$index" 2>/dev/null && return 0
            ;;
    esac
    return 1
}

# is_in_trash <path>
# Returns 0 if path is under local/.trash/
is_in_trash() {
    case "$1" in
        */local/.trash/*) return 0 ;;
        *) return 1 ;;
    esac
}
