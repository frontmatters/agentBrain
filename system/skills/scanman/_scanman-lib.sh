#!/usr/bin/env bash
# _scanman-lib.sh — shared helpers for scanman-*.sh wrapper scripts.
#
# Sourced by scanman-init.sh, scanman-scan.sh, scanman-validate.sh,
# scanman-bump-version.sh.
#
# Provides:
#   - SCANMAN_SKILL_DIR       (this dir)
#   - SCANMAN_AGENTBRAIN_DIR  (vault root)
#   - detect_scanman_bin      (echo path-to-rust-bin or empty)
#   - parse_mode_flag         (resolve --mode= / SCANMAN_MODE / default=focused)
#   - die / warn / info       (stderr helpers)
#   - require_workspace       (validate workspace path exists & has index.md)
#
# Bash 3.2 compatible (macOS default).

set -euo pipefail

# Resolve the directory this lib lives in (canonical path, no symlinks).
SCANMAN_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Vault root.
SCANMAN_AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-${HOME}/agentBrain}"

# Rust binary detection — prefer PATH, fall back to vault build artefact.
detect_scanman_bin() {
    if command -v scanman >/dev/null 2>&1; then
        command -v scanman
        return 0
    fi
    local cand="${SCANMAN_SKILL_DIR}/rust-impl/target/release/scanman"
    if [ -x "$cand" ]; then
        echo "$cand"
        return 0
    fi
    echo ""
    return 0
}

# Parse --mode=<value> from positional args. Honor SCANMAN_MODE env var as
# fallback. Default = focused (backwards compatibility).
#
# Usage:
#   parse_mode_flag "$@"   # populates global SCANMAN_PARSED_MODE
#                          # and global SCANMAN_PASSTHRU_ARGS (array)
parse_mode_flag() {
    SCANMAN_PARSED_MODE="${SCANMAN_MODE:-focused}"
    SCANMAN_PASSTHRU_ARGS=()
    local a
    for a in "$@"; do
        case "$a" in
            --mode=*)
                SCANMAN_PARSED_MODE="${a#--mode=}"
                ;;
            --mode)
                die "use --mode=<value>, not --mode <value>"
                ;;
            *)
                SCANMAN_PASSTHRU_ARGS+=("$a")
                ;;
        esac
    done

    # Canonicalize 'repro-spec' -> 'reproduction-spec'.
    if [ "$SCANMAN_PARSED_MODE" = "repro-spec" ]; then
        SCANMAN_PARSED_MODE="reproduction-spec"
    fi

    case "$SCANMAN_PARSED_MODE" in
        focused|reproduction-spec|both)
            : # OK
            ;;
        *)
            die "invalid mode '$SCANMAN_PARSED_MODE' (allowed: focused, reproduction-spec, both)"
            ;;
    esac
    return 0
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

warn() {
    echo "WARN: $*" >&2
}

info() {
    echo "INFO: $*" >&2
}

require_workspace() {
    local ws="$1"
    [ -n "$ws" ] || die "workspace path is required"
    [ -d "$ws" ] || die "workspace not found: $ws"
    [ -f "$ws/index.md" ] || die "workspace missing index.md: $ws"
    return 0
}

# Read the current scanman method version (plain text).
scanman_version() {
    local v_file="${SCANMAN_SKILL_DIR}/VERSION"
    if [ -f "$v_file" ]; then
        tr -d '[:space:]' < "$v_file"
    else
        echo "unknown"
    fi
}
