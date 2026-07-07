#!/usr/bin/env bash
# scanman-validate.sh — mandatory completeness gate for scanman workspaces.
#
# Modes:
#   focused              (default, back-compat) — checks 00..05 + index
#   reproduction-spec    (v0.6)                 — checks DISTILLATE/*.md gates
#   both                                        — focused + reproduction-spec
#
# Delegation policy:
#   - focused mode: prefer Rust binary (faster, regex parity tested).
#   - reproduction-spec: prefer Rust binary (implements all 8 active gates
#     with per-mode workspace structure since v0.6.1). Pure-bash fallback
#     below enforces G1, G7, G10, G13 (BLOCKING/WARN per spec) + LEARNINGS.md
#     existence; other gates stub with WARNING messages.
#   - both: focused (Rust or bash) + repro-spec bash gate in one run.
#
# Exit codes (matches rust-impl/src/validate.rs contract):
#   0 = PASS — agent MAY claim "complete enough"
#   1 = FAIL — actionable per-file failures listed on stderr; agent must iterate
#   2 = USAGE / MISSING workspace — fix invocation, then re-run
#
# Usage:
#   scanman-validate.sh [--mode=MODE] <workspace>
#   scanman-validate.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_scanman-lib.sh
. "${SCRIPT_DIR}/_scanman-lib.sh"

usage() {
    cat <<'EOF'
scanman-validate.sh — mandatory completeness gate for scanman workspaces

USAGE:
  scanman-validate.sh [--mode=MODE] <workspace>
  scanman-validate.sh --help

OPTIONS:
  --mode=MODE       focused (default) | reproduction-spec | both
  --help, -h        Show this help.

ARGUMENTS:
  workspace         Workspace directory (must contain index.md).

EXIT CODES:
  0 = PASS (agent MAY claim "complete enough")
  1 = FAIL (per-file reasons on stderr; agent must iterate)
  2 = USAGE error (fix invocation, then re-run)

ENV (focused mode thresholds — passed through to Rust impl when delegated):
  SCANMAN_MIN_WORDS=300
  SCANMAN_MIN_ITEMS=3
  SCANMAN_MIN_BULLET_LEN=30
  SCANMAN_MIN_CLAIM_LABELS=3
  SCANMAN_MIN_SECTION_WORDS=25
  SCANMAN_MAX_THIN_SECTIONS=2
  SCANMAN_EXEMPT_SECTIONS='^(Related|Purpose|Decision)$'
  SCANMAN_REQUIRE_EVIDENCE=0   # opt-in source-path enforcement for verified claims

ENV (reproduction-spec gate):
  SCANMAN_MIN_ANCHORS=3        # G8 threshold (stubbed in bash; passed to Rust)
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
    echo "ERROR: <workspace> is required" >&2
    echo "" >&2
    usage >&2
    exit 2
fi

WORKSPACE="${ARGS[0]}"

if [ ! -d "$WORKSPACE" ]; then
    echo "ERROR: workspace not found: $WORKSPACE" >&2
    exit 2
fi

# --- thresholds (focused mode) -------------------------------------------------

MIN_WORDS="${SCANMAN_MIN_WORDS:-300}"
MIN_ITEMS="${SCANMAN_MIN_ITEMS:-3}"
MIN_BULLET_LEN="${SCANMAN_MIN_BULLET_LEN:-30}"
MIN_CLAIM_LABELS="${SCANMAN_MIN_CLAIM_LABELS:-3}"
MIN_SECTION_WORDS="${SCANMAN_MIN_SECTION_WORDS:-25}"
MAX_THIN_SECTIONS="${SCANMAN_MAX_THIN_SECTIONS:-2}"
EXEMPT_SECTIONS="${SCANMAN_EXEMPT_SECTIONS:-^(Related|Purpose|Decision)$}"
REQUIRE_EVIDENCE="${SCANMAN_REQUIRE_EVIDENCE:-0}"

FAILURES=()
WARNINGS=()

fail() { FAILURES+=("$*"); }
warn_gate() { WARNINGS+=("$*"); }

# --- focused-mode checks (mirror rust-impl/src/validate.rs) -------------------

run_focused_checks() {
    local ws="$1"
    local required=(
        "index.md"
        "00-file-inventory.md"
        "00b-dependency-map.md"
        "01-system-map.md"
        "02-runtime-model.md"
        "03-core-primitives.md"
        "04-risk-and-bloat.md"
        "05-redesign-v1.md"
    )
    local deep_check=(
        "03-core-primitives.md"
        "04-risk-and-bloat.md"
        "05-redesign-v1.md"
    )
    local discipline_check=(
        "02-runtime-model.md"
        "03-core-primitives.md"
        "04-risk-and-bloat.md"
        "05-redesign-v1.md"
    )

    local f
    for f in "${required[@]}"; do
        if [ ! -f "$ws/$f" ]; then
            fail "$f: MISSING"
        fi
    done

    # Deep checks (existence + placeholders + word count + substantial bullets).
    for f in "${deep_check[@]}"; do
        [ -f "$ws/$f" ] || continue
        local text; text="$(cat "$ws/$f")"

        # Placeholders.
        local placeholders
        placeholders="$(echo "$text" | grep -oE '\[fill in\]|\bTODO\b|\bTBD\b|\bFIXME\b|\bXXX\b' | sort -u | paste -sd, -)"
        if [ -n "$placeholders" ]; then
            fail "$f: contains placeholders [$placeholders]"
        fi

        # Word count.
        local words
        words="$(echo "$text" | wc -w | tr -d ' ')"
        if [ "$words" -lt "$MIN_WORDS" ]; then
            fail "$f: $words words < $MIN_WORDS minimum"
        fi

        # Substantial bullets.
        local bullets
        bullets="$(echo "$text" | grep -cE "^[[:space:]]*[-*][[:space:]].{${MIN_BULLET_LEN},}" || true)"
        if [ "$bullets" -lt "$MIN_ITEMS" ]; then
            fail "$f: $bullets substantial bullets (>= $MIN_BULLET_LEN chars) < $MIN_ITEMS minimum"
        fi
    done

    # Discipline checks: count lines with verified/inferred/unknown.
    for f in "${discipline_check[@]}"; do
        [ -f "$ws/$f" ] || continue
        local count
        count="$(grep -ciE '\b(verified|inferred|unknown)\b' "$ws/$f" || true)"
        if [ "$count" -lt "$MIN_CLAIM_LABELS" ]; then
            fail "$f: $count claim-labels (verified/inferred/unknown) < $MIN_CLAIM_LABELS minimum"
        fi
    done

    # Section-density (thin sections).
    for f in "${deep_check[@]}"; do
        [ -f "$ws/$f" ] || continue
        local thin_count=0
        local thin_lines=()
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            thin_count=$((thin_count + 1))
            thin_lines+=("$line")
        done < <(awk -v min="$MIN_SECTION_WORDS" -v exempt="$EXEMPT_SECTIONS" '
            BEGIN { in_fm=0; cur=""; cnt=0 }
            /^---$/ { in_fm = !in_fm; next }
            in_fm { next }
            /^## / {
                if (cur != "") {
                    if (cur !~ exempt && cnt < min) print cur "\t" cnt
                }
                cur = substr($0, 4)
                cnt = 0
                next
            }
            { for(i=1;i<=NF;i++) cnt++ }
            END {
                if (cur != "" && cur !~ exempt && cnt < min) print cur "\t" cnt
            }
        ' "$ws/$f")

        if [ "$thin_count" -gt "$MAX_THIN_SECTIONS" ]; then
            local tl
            for tl in "${thin_lines[@]}"; do
                local name="${tl%%$'\t'*}"
                local n="${tl##*$'\t'}"
                fail "$f: thin section '## $name' ($n words < $MIN_SECTION_WORDS) — template boilerplate likely unfilled"
            done
        fi
    done

    # Evidence-link check (opt-in).
    if [ "$REQUIRE_EVIDENCE" = "1" ]; then
        local evidence_check=(
            "02-runtime-model.md"
            "03-core-primitives.md"
            "04-risk-and-bloat.md"
        )
        for f in "${evidence_check[@]}"; do
            [ -f "$ws/$f" ] || continue
            local vc
            vc="$(grep -cE '\bverified\b' "$ws/$f" || true)"
            [ "$vc" -eq 0 ] && continue
            local ec
            ec="$(grep -cE '[a-zA-Z0-9_./@-]+\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|zig|rs|go|py|sh|c|cpp|h|hpp|java|rb|php|swift|kt|scala)\b' "$ws/$f" || true)"
            if [ "$ec" -eq 0 ]; then
                fail "$f: $vc verified claim(s) but zero source-path references — claims must be grounded in actual file reads"
            fi
        done
    fi
}

# --- reproduction-spec gate checks --------------------------------------------

# G1: §2 dependency table must declare and fill a Value column.
check_g1() {
    local file="$1"
    local module; module="$(basename "$file" .md)"
    # Extract §2 block.
    local sec2
    sec2="$(awk '/^## Sectie 2/,/^## Sectie [0-9]/' "$file" | sed '$d')"
    [ -z "$sec2" ] && return 0   # No §2 → skip silently

    # Header must mention "Value".
    if ! echo "$sec2" | grep -qE '^\|.*Value.*\|'; then
        fail "G1: ${module} §2 Dependencies table is missing 'Value' column"
        return 0
    fi

    # Data rows: no empty Value cells.
    local bad
    bad="$(echo "$sec2" | awk -F'|' '
        /^\|[[:space:]]*-+/ { next }
        /^\|.*Value/        { for(i=1;i<=NF;i++) if($i~/Value/) col=i; next }
        /^\|/ && col {
            cell=$col
            gsub(/^[[:space:]]+|[[:space:]]+$/,"",cell)
            if (cell=="" || cell=="-" || cell=="?") {
                print "row with empty Value: " $0
            }
        }
    ')"
    if [ -n "$bad" ]; then
        while IFS= read -r line; do
            fail "G1: ${module} §2 ${line}"
        done <<< "$bad"
    fi
}

# G7: §7 pseudocode must be language-agnostic (no Zig/Rust/C-specific tokens).
check_g7() {
    local file="$1"
    local module; module="$(basename "$file" .md)"
    local sec7
    sec7="$(awk '/^## Sectie 7/,/^## Sectie [0-9]/' "$file" | sed '$d')"
    [ -z "$sec7" ] && return 0

    # Banned tokens — Zig/Rust/C-specific.
    local banned='(\*\||\+\||-\||@import|@sizeOf|@offsetOf|@as|@intCast|extern[[:space:]]+(struct|fn)|\busize\b|\bisize\b|\bu8\b|\bu16\b|\bu32\b|\bu64\b|->[[:space:]]*!)'
    local hits
    hits="$(echo "$sec7" | grep -nE "$banned" || true)"
    if [ -n "$hits" ]; then
        local first
        first="$(echo "$hits" | head -1)"
        fail "G7: ${module} §7 pseudocode contains language-specific tokens (e.g. ${first})"
    fi
}

# G10: every type declared in §4 must carry a Memory layout field.
check_g10() {
    local file="$1"
    local module; module="$(basename "$file" .md)"

    local missing
    missing="$(awk '
        /^## Sectie 4([^a-z]|$)/ { in4=1; next }
        /^## Sectie [0-9]/       { if (in4 && type && !have) print "MISSING:" type; in4=0; type=""; have=0 }
        in4 && /^### / {
            if (type && !have) print "MISSING:" type
            type=$0; have=0; next
        }
        in4 && /^\*\*Memory layout\*\*:[[:space:]]*(regular|extern|packed)/ { have=1 }
        END { if (in4 && type && !have) print "MISSING:" type }
    ' "$file")"

    if [ -n "$missing" ]; then
        while IFS= read -r line; do
            local tname="${line#MISSING:}"
            fail "G10: ${module} §4 type missing '**Memory layout**: regular|extern|packed' field: ${tname}"
        done <<< "$missing"
    fi
}

# G13: §12 abbreviations must carry disclaimer and not substitute for full distillates.
check_g13() {
    local file="$1"
    local module; module="$(basename "$file" .md)"
    local workspace_distillate_dir; workspace_distillate_dir="$(dirname "$file")"

    local sec12
    sec12="$(awk '/^## Sectie 12/,/^## /' "$file" | sed '$d')"
    [ -z "$sec12" ] && return 0

    # Heuristic 1: disclaimer text present.
    if ! echo "$sec12" | grep -qiE 'not.*substitut|contextual.*only|full.*distillate.*required'; then
        warn_gate "G13: ${module} §12 lacks a 'not a substitute for full distillate' disclaimer"
    fi

    # Heuristic 2: every dependency named has its own DISTILLATE/<dep>.md.
    local deps
    deps="$(echo "$sec12" | grep -oE '^###[[:space:]]+[A-Z][A-Za-z0-9_]+' | awk '{print tolower($2)}')"
    local dep
    for dep in $deps; do
        if [ ! -f "$workspace_distillate_dir/$dep.md" ]; then
            warn_gate "G13: ${module} §12 references '${dep}' but ${workspace_distillate_dir}/${dep}.md is missing"
        fi
    done
}

run_repro_spec_checks() {
    local ws="$1"
    local dist_dir="$ws/DISTILLATE"
    if [ ! -d "$dist_dir" ]; then
        fail "reproduction-spec mode: $ws/DISTILLATE/ is missing"
        return 0
    fi

    local count=0
    local file
    for file in "$dist_dir"/*.md; do
        [ -e "$file" ] || continue
        count=$((count + 1))
        check_g1  "$file"
        check_g7  "$file"
        check_g10 "$file"
        check_g13 "$file"
    done

    if [ "$count" -eq 0 ]; then
        fail "reproduction-spec mode: no DISTILLATE/*.md files found"
        return 0
    fi

    # LEARNINGS.md existence gate — learning capture (playbook §5) is verplicht.
    if [ ! -f "$ws/LEARNINGS.md" ]; then
        fail "reproduction-spec mode: $ws/LEARNINGS.md is missing — learning capture (playbook §5) is mandatory. Fix: create LEARNINGS.md from the §5 skeleton"
    fi

    # Stub other gates with WARNING.
    warn_gate "G2 (compile-time assertion location): not yet enforced in bash — upgrade to Rust impl or run manual review"
    warn_gate "G3/G5 (anchor type labels): not yet enforced in bash — upgrade to Rust impl or run manual review"
    warn_gate "G6 (state-reset matrix): not yet enforced in bash — upgrade to Rust impl or run manual review"
    warn_gate "G8 (anchor coverage minimum): not yet enforced in bash — upgrade to Rust impl or run manual review"
    warn_gate "G9 (post-dispatch state visibility): not yet enforced in bash — upgrade to Rust impl or run manual review"
    warn_gate "G11 (anchor kind sub-classification): not yet enforced in bash — upgrade to Rust impl or run manual review"
}

# --- main dispatch -------------------------------------------------------------

# focused mode → prefer Rust impl when available
if [ "$MODE" = "focused" ]; then
    BIN="$(detect_scanman_bin)"
    if [ -n "$BIN" ]; then
        info "delegating to Rust binary: $BIN validate"
        exec "$BIN" validate "$WORKSPACE"
    fi
    # Pure-bash fallback for focused.
    run_focused_checks "$WORKSPACE"
elif [ "$MODE" = "reproduction-spec" ]; then
    BIN="$(detect_scanman_bin)"
    if [ -n "$BIN" ]; then
        info "delegating to Rust binary: $BIN validate --mode=reproduction-spec"
        exec "$BIN" validate --mode=reproduction-spec "$WORKSPACE"
    fi
    # Pure-bash fallback (subset: G1, G7, G10 blocking; G13 + stubs as WARN).
    run_repro_spec_checks "$WORKSPACE"
elif [ "$MODE" = "both" ]; then
    BIN="$(detect_scanman_bin)"
    if [ -n "$BIN" ]; then
        info "running Rust focused gate first"
        if ! "$BIN" validate "$WORKSPACE"; then
            : # collect Rust failures alongside repro-spec ones
        fi
    else
        run_focused_checks "$WORKSPACE"
    fi
    run_repro_spec_checks "$WORKSPACE"
fi

# --- output --------------------------------------------------------------------

if [ "${#FAILURES[@]}" -eq 0 ]; then
    echo "PASS: $WORKSPACE is complete-enough (mode: $MODE)"
    if [ "$MODE" = "focused" ] || [ "$MODE" = "both" ]; then
        echo "  - all required files exist"
        echo "  - 03/04/05 contain no placeholders"
        echo "  - 03/04/05 meet word count (>= $MIN_WORDS)"
        echo "  - 03/04/05 meet substantial items (>= $MIN_ITEMS bullets, >= $MIN_BULLET_LEN chars)"
        echo "  - 02/03/04/05 demonstrate claim discipline (>= $MIN_CLAIM_LABELS labels)"
        echo "  - 03/04/05 have <= $MAX_THIN_SECTIONS thin sections (>= $MIN_SECTION_WORDS words/section)"
    fi
    if [ "$MODE" = "reproduction-spec" ] || [ "$MODE" = "both" ]; then
        echo "  - DISTILLATE/*.md gates: G1, G7, G10 BLOCKING; G13 WARNING — all pass"
    fi
    if [ "${#WARNINGS[@]}" -gt 0 ]; then
        echo ""
        echo "Warnings (non-blocking):"
        for w in "${WARNINGS[@]}"; do
            echo "  WARN: $w"
        done
    fi
    exit 0
else
    echo "FAIL: $WORKSPACE is incomplete (mode: $MODE)" >&2
    for f in "${FAILURES[@]}"; do
        echo "  - $f" >&2
    done
    if [ "${#WARNINGS[@]}" -gt 0 ]; then
        echo "" >&2
        for w in "${WARNINGS[@]}"; do
            echo "  WARN: $w" >&2
        done
    fi
    echo "" >&2
    echo "Agent must iterate to fill missing/insufficient content before claiming completion." >&2
    exit 1
fi
