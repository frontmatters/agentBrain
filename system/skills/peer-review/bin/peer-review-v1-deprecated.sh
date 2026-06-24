#!/usr/bin/env bash
# peer-review — cross-agent SPEC/design review skill.
# See SPEC.md (v1.3.2) for full design + open questions + v2 backlog.
#
# Self-improving: every successful invocation appends to state/invocations.log,
# building a corpus of (agent, model, doc-sha) tuples that later analysis can
# mine for patterns. Records also flip AGENT_INVOCATION_VERIFIED_<name> for the
# next session.
#
# Agent-agnostic: skill lives in local/skills/, references no specific agent
# beyond the registry (agents.sh). The registry itself is path-based, not
# hardcoded into the dispatcher.

set -euo pipefail

# ── Resolve paths ──
# AGENTBRAIN_DIR is env-overridable (`export AGENTBRAIN_DIR=...` honored); defaults to
# realpath of ~/agentBrain. Fallbacks for macOS without BSD realpath.
#
# Backwards-compat shim (rename 2026-05-24 — remove no earlier than 2026-11-01):
# Old code used BRAIN_DIR; forward to AGENTBRAIN_DIR if user has the legacy env-var set.
if [ -z "${AGENTBRAIN_DIR:-}" ] && [ -n "${BRAIN_DIR:-}" ]; then
	AGENTBRAIN_DIR="$BRAIN_DIR"
	echo "peer-review: warning: BRAIN_DIR is deprecated; use AGENTBRAIN_DIR (removal: 2026-11-01+)" >&2
fi

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-}"
if [ -z "$AGENTBRAIN_DIR" ]; then
	AGENTBRAIN_DIR="$(realpath ~/agentBrain 2>/dev/null \
	          || (cd ~/agentBrain 2>/dev/null && pwd -P) \
	          || python3 -c 'import os; print(os.path.realpath(os.path.expanduser("~/agentBrain")))' 2>/dev/null \
	          || echo "$HOME/agentBrain")"
fi
SKILL_DIR="$AGENTBRAIN_DIR/local/skills/peer-review"
STATE_DIR="$SKILL_DIR/state"
INVOCATIONS_LOG="$STATE_DIR/invocations.log"
REVIEWS_DIR="$AGENTBRAIN_DIR/local/reviews"

# ── Source registry + optional user config ──
# shellcheck disable=SC1091
source "$SKILL_DIR/agents.sh"
if [ -f "$SKILL_DIR/config.sh" ]; then
	# shellcheck disable=SC1091
	source "$SKILL_DIR/config.sh"
fi

# Self-improving: read prior invocations.log to upgrade INVOCATION_VERIFIED
# states. If we've successfully invoked agent X before, treat it as verified.
if [ -f "$INVOCATIONS_LOG" ]; then
	while IFS=$'\t' read -r _ agent _ _ _; do
		# Bash 4+ indirect-var assignment for AGENT_INVOCATION_VERIFIED_<agent>.
		declare "AGENT_INVOCATION_VERIFIED_$agent=yes"
	done < "$INVOCATIONS_LOG"
fi

# ── Defaults ──
FOCUS_DEFAULT="correctness, completeness, clarity, edge cases"
SIZE_WARN_BYTES=51200    # 50 KB threshold

# ── Parse args ──
DOC_PATH=""
EXPLICIT_AGENT=""
CLI_MODEL_FLAG_SET=0
CLI_MODEL_FLAG=""
FOCUS=""
ARCHIVE=0
EXPLICIT_FROM=""
NO_SIZE_WARNING=0
DRY_RUN=0
NO_LOG=0
TIMEOUT_SECS=300       # v1.4: default 5-min timeout (was: hang-forever)
HEARTBEAT_SECS=30      # v1.4: heartbeat every 30s if reviewer is slow

while [ $# -gt 0 ]; do
	case "$1" in
		--agent=*)   EXPLICIT_AGENT="${1#*=}" ;;
		--model=*)   CLI_MODEL_FLAG_SET=1; CLI_MODEL_FLAG="${1#*=}" ;;
		--focus=*)   FOCUS="${1#*=}" ;;
		--archive)   ARCHIVE=1 ;;
		--from=*)    EXPLICIT_FROM="${1#*=}" ;;
		--no-size-warning) NO_SIZE_WARNING=1 ;;
		--no-log)    NO_LOG=1 ;;
		--dry-run)   DRY_RUN=1 ;;
		--timeout=*) TIMEOUT_SECS="${1#*=}"
		             [[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]] || {
		                echo "peer-review: --timeout must be a positive integer (seconds)" >&2
		                exit 1
		             } ;;
		-h|--help)
			grep '^# ' "$0" | sed 's/^# \?//'
			exit 0 ;;
		-*)
			echo "peer-review: unknown flag: $1" >&2
			exit 1 ;;
		*)
			if [ -n "$DOC_PATH" ]; then
				echo "peer-review: only one <doc-path> allowed (got '$DOC_PATH' and '$1')" >&2
				exit 1
			fi
			DOC_PATH="$1" ;;
	esac
	shift
done

# ── Reject empty --model (silent collapse to default makes provenance ambiguous) ──
if [ "$CLI_MODEL_FLAG_SET" -eq 1 ] && [ -z "$CLI_MODEL_FLAG" ]; then
	echo "peer-review: --model cannot be empty. Omit the flag to use config/default." >&2
	exit 1
fi

# ── Validate doc ──
if [ -z "$DOC_PATH" ]; then
	echo "Usage: peer-review <doc-path> [--agent=NAME] [--model=MODEL] [--focus=...] [--archive] [--from=NAME] [--no-size-warning] [--dry-run]" >&2
	exit 1
fi

# Resolve to absolute path via realpath with fallback chain.
DOC_PATH_ABS="$(realpath "$DOC_PATH" 2>/dev/null \
             || (cd "$(dirname "$DOC_PATH")" 2>/dev/null && echo "$(pwd -P)/$(basename "$DOC_PATH")") \
             || python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$DOC_PATH" 2>/dev/null \
             || echo "$DOC_PATH")"

[ -f "$DOC_PATH_ABS" ] || { echo "peer-review: doc not found: $DOC_PATH" >&2; exit 1; }
[ -r "$DOC_PATH_ABS" ] || { echo "peer-review: doc not readable: $DOC_PATH" >&2; exit 1; }
[ -s "$DOC_PATH_ABS" ] || { echo "peer-review: doc is empty: $DOC_PATH" >&2; exit 1; }
grep -Iq . "$DOC_PATH_ABS" || { echo "peer-review: doc appears to be binary: $DOC_PATH" >&2; exit 1; }

# ── Self-detect ──
SELF=""
in_array() {
	local needle="$1" item
	shift
	for item in "$@"; do [ "$item" = "$needle" ] && return 0; done
	return 1
}

if [ -n "$EXPLICIT_FROM" ]; then
	# Fix (Pi review #3): validate --from against registry
	if ! in_array "$EXPLICIT_FROM" "${AGENT_NAMES[@]}"; then
		echo "peer-review: --from='$EXPLICIT_FROM' not in registry. Known: ${AGENT_NAMES[*]}" >&2
		exit 4
	fi
	SELF="$EXPLICIT_FROM"
else
	for name in "${AGENT_NAMES[@]}"; do
		env_var_name="AGENT_SELF_ENV_$name"
		env_var_value="${!env_var_name:-}"
		if [ -n "$env_var_value" ] && [ -n "${!env_var_value:-}" ]; then
			SELF="$name"
			break
		fi
	done
fi

# Fix (Pi review #1, HIGH security): if self-detect failed AND no --agent given,
# refuse rather than silently fall back to first-installed (which could be self).
if [ -z "$SELF" ] && [ -z "$EXPLICIT_AGENT" ]; then
	echo "peer-review: cannot determine self-agent (no recognised env var)." >&2
	echo "  Either pass --from=<name> to set self explicitly," >&2
	echo "  or pass --agent=<name> to pick a reviewer directly." >&2
	exit 4
fi

# ── Pick reviewer ──
is_blocked() {
	local agent="$1" b
	# shellcheck disable=SC2086  # we want word-splitting on BLOCKED_AGENTS
	for b in ${BLOCKED_AGENTS:-}; do [ "$b" = "$agent" ] && return 0; done
	return 1
}

REVIEWER=""
if [ -n "$EXPLICIT_AGENT" ]; then
	in_array "$EXPLICIT_AGENT" "${AGENT_NAMES[@]}" || {
		echo "peer-review: agent '$EXPLICIT_AGENT' not in registry. Known: ${AGENT_NAMES[*]}" >&2
		exit 4
	}
	[ "$EXPLICIT_AGENT" = "$SELF" ] && {
		echo "peer-review: refusing to review yourself (--agent=$SELF). Pick a different agent or pass --from=<other> to override self-detect." >&2
		exit 4
	}
	is_blocked "$EXPLICIT_AGENT" && {
		echo "peer-review: agent '$EXPLICIT_AGENT' is in BLOCKED_AGENTS." >&2
		exit 4
	}
	REVIEWER="$EXPLICIT_AGENT"
else
	# Try config default for current self.
	if [ -n "$SELF" ]; then
		default_var="DEFAULT_REVIEWER_FOR_$SELF"
		default_value="${!default_var:-}"
		if [ -n "$default_value" ] && in_array "$default_value" "${AGENT_NAMES[@]}" && [ "$default_value" != "$SELF" ] && ! is_blocked "$default_value"; then
			REVIEWER="$default_value"
		fi
	fi
	# Fallback: first available agent ≠ self, not blocked, callable.
	if [ -z "$REVIEWER" ]; then
		for name in "${AGENT_NAMES[@]}"; do
			[ "$name" = "$SELF" ] && continue
			is_blocked "$name" && continue
			if command -v "$name" >/dev/null 2>&1; then
				REVIEWER="$name"
				break
			fi
		done
	fi
fi

if [ -z "$REVIEWER" ]; then
	echo "peer-review: no callable reviewer found." >&2
	echo "  Self=${SELF:-(unknown)}; tried registry=${AGENT_NAMES[*]}; blocked=${BLOCKED_AGENTS:-(none)}" >&2
	echo "  Install at least one reviewer CLI or pass --agent=<name>." >&2
	exit 4
fi

# ── Verify reviewer is callable ──
if ! command -v "$REVIEWER" >/dev/null 2>&1; then
	cat >&2 <<EOF
peer-review: chosen reviewer '$REVIEWER' not found on PATH.

Install at least one supported reviewer CLI:
  claude   → https://docs.anthropic.com/en/docs/claude-code/cli
  pi       → bun add -g pi
  copilot  → brew install gh && gh extension install github/gh-copilot
  gemini   → npm i -g @google/gemini-cli
  aider    → uv tool install aider-chat

Or use --agent=<other-installed-agent>.
See SPEC.md §13 for v2 API-direct fallback (no CLI required).
EOF
	exit 5
fi

# ── Resolve model ──
config_model_var="DEFAULT_MODEL_FOR_$REVIEWER"
CONFIG_MODEL="${!config_model_var:-}"
if [ "$CLI_MODEL_FLAG_SET" -eq 1 ]; then
	MODEL="$CLI_MODEL_FLAG"
	MODEL_SOURCE="flag"
elif [ -n "$CONFIG_MODEL" ]; then
	MODEL="$CONFIG_MODEL"
	MODEL_SOURCE="config"
else
	MODEL=""
	MODEL_SOURCE="cli-default"
fi

# ── Build prompt ──
FOCUS="${FOCUS:-$FOCUS_DEFAULT}"
DOC_SIZE=$(wc -c < "$DOC_PATH_ABS" | tr -d ' ')
if [ "$DOC_SIZE" -gt "$SIZE_WARN_BYTES" ] && [ "$NO_SIZE_WARNING" -eq 0 ]; then
	echo "peer-review: warning — doc is ${DOC_SIZE} bytes (>50 KB); reviewer may truncate. Suppress with --no-size-warning." >&2
fi

DOC_CONTENT="$(cat "$DOC_PATH_ABS")"
# Fix (Pi review #6): SHA must match what's IN the prompt, not what's on disk.
# Command substitution `$(cat ...)` strips trailing newlines; compute SHA on
# the actual byte string we embed, so archive provenance stays honest.
DOC_SHA="$(printf '%s' "$DOC_CONTENT" | shasum -a 256 | cut -d' ' -f1)"

PROMPT="You are reviewing a design specification written by another AI agent. Focus on: $FOCUS.

Be specific and concrete. Cite section numbers or quote specific lines when raising issues. Push back where you disagree — your job is to catch what the author missed, not to validate.

If the document references external files or context you can't see, note it as a caveat but proceed with the review based on the content provided.

Reply with structured feedback per section if the spec has sections; otherwise as a numbered list of issues.

--- BEGIN DOCUMENT ---
$DOC_CONTENT
--- END DOCUMENT ---"

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
MODEL_DISPLAY="${MODEL:-(CLI default)}"
BANNER="--- Review by $REVIEWER [model: $MODEL_DISPLAY; source: $MODEL_SOURCE] (focus: $FOCUS; at: $TIMESTAMP) ---"

# ── Dry-run short-circuit ──
if [ "$DRY_RUN" -eq 1 ]; then
	echo "$BANNER"
	echo ""
	echo "would invoke: invoke_$REVIEWER \"<\$PROMPT length=${#PROMPT}>\" \"$MODEL\""
	echo ""
	echo "(--dry-run: no invocation performed)"
	exit 0
fi

# ── Invoke reviewer (v1.4: tempfile + watchdog + heartbeat) ──
echo "$BANNER"

# Write reviewer output to tempfile so we can monitor it concurrently.
# (Command substitution `$(invoke …)` would block until child exit, making
#  watchdog/heartbeat impossible.)
response_log="$(mktemp -t peer-review-response.XXXXXX)"
trap 'rm -f "$response_log"' EXIT

# Spawn the reviewer in background so we can track its PID.
( "invoke_$REVIEWER" "$PROMPT" "$MODEL" >"$response_log" 2>&1 ) &
invoke_pid=$!

# Watchdog: enforce --timeout=N. After timeout, SIGTERM, then SIGKILL if needed.
# `trap '' TERM` in subshell suppresses bash's "Terminated" job-notification noise
# when the watchdog is cleaned up by the main script after invocation completes.
(
	trap 'exit 0' TERM
	sleep "$TIMEOUT_SECS"
	kill -TERM "$invoke_pid" 2>/dev/null || exit 0
	sleep 3
	kill -KILL "$invoke_pid" 2>/dev/null || true
) &
watchdog_pid=$!

# Heartbeat: print to stderr every $HEARTBEAT_SECS so caller knows we're alive.
# Same trap pattern — quiet on cleanup-via-SIGTERM.
(
	trap 'exit 0' TERM
	elapsed=0
	while sleep "$HEARTBEAT_SECS"; do
		elapsed=$((elapsed + HEARTBEAT_SECS))
		kill -0 "$invoke_pid" 2>/dev/null || break
		echo "peer-review: still waiting on $REVIEWER (${elapsed}s elapsed, timeout=${TIMEOUT_SECS}s)" >&2
	done
) &
heartbeat_pid=$!

# Block until reviewer exits (or watchdog kills it).
set +e
wait "$invoke_pid"
RESPONSE_EXIT=$?
set -e

# Tear down monitors with SIGKILL (not SIGTERM): bash defers SIGTERM until the
# current command finishes — so a sleeping subshell would block cleanup until
# its `sleep N` completed (could be 30s for heartbeat or full TIMEOUT_SECS for
# watchdog). SIGKILL is non-trappable and stops the subshell immediately.
kill -KILL "$watchdog_pid" 2>/dev/null || true
kill -KILL "$heartbeat_pid" 2>/dev/null || true
# Brief wait reaps zombies. With SIGKILL these return immediately.
wait "$watchdog_pid" 2>/dev/null || true
wait "$heartbeat_pid" 2>/dev/null || true

# Classify exit code.
if [ "$RESPONSE_EXIT" -ne 0 ]; then
	echo "" >&2
	if [ "$RESPONSE_EXIT" -eq 143 ] || [ "$RESPONSE_EXIT" -eq 137 ]; then
		echo "peer-review: reviewer '$REVIEWER' KILLED by watchdog after ${TIMEOUT_SECS}s timeout" >&2
		echo "  Likely cause: API/model transient stall, or non-TTY auth-prompt deadlock." >&2
		echo "  See [[peer-review-hang-rca-2026-05-24]]. Increase --timeout=N if false positive." >&2
	else
		echo "peer-review: reviewer '$REVIEWER' exited $RESPONSE_EXIT" >&2
		[ -s "$response_log" ] && { echo "  Last 10 lines of reviewer output:" >&2; tail -10 "$response_log" >&2; }
	fi
	exit 6
fi

# Read captured response from tempfile.
RESPONSE="$(cat "$response_log")"

if [ -z "$RESPONSE" ]; then
	echo "peer-review: reviewer returned empty response (warning only, exit 0)" >&2
	exit 0
fi

echo "$RESPONSE"

# ── Self-improving: log successful invocation ──
# Opt-out via --no-log; default is to log (this is THE self-improvement mechanism).
# DOC_SHA already computed at prompt-build time (Pi review #6 fix), so the logged
# SHA matches what the reviewer actually saw.
if [ "$NO_LOG" -eq 0 ]; then
	mkdir -p "$STATE_DIR"
	printf '%s\t%s\t%s\t%s\t%s\n' \
		"$TIMESTAMP" "$REVIEWER" "$MODEL_DISPLAY" "$MODEL_SOURCE" "$DOC_SHA" \
		>> "$INVOCATIONS_LOG"
fi

# ── Archive (opt-in) ──
ARCHIVE_DEFAULT="${ARCHIVE_DEFAULT:-false}"
should_archive=0
[ "$ARCHIVE" -eq 1 ] && should_archive=1
[ "$ARCHIVE_DEFAULT" = "true" ] && should_archive=1
if [ "$should_archive" -eq 1 ]; then
	mkdir -p "$REVIEWS_DIR"
	doc_base="$(basename "$DOC_PATH_ABS" .md)"
	archive_basename="$TIMESTAMP-$doc_base-by-$REVIEWER"
	archive_file="$REVIEWS_DIR/$archive_basename.md"
	# Fix (Pi review #7 + own bug): the earlier `|| echo ...` was unreachable
	# because `head -1` succeeds on empty input. Use subshell + explicit fallback.
	reviewer_version="$( ( "$REVIEWER" --version 2>/dev/null || true ) | head -1 )"
	[ -z "$reviewer_version" ] && reviewer_version="(version unavailable)"
	# Compute UUID5 for archive — agentBrain frontmatter contract requires it.
	# Path-no-ext is what uuid5-gen.sh expects.
	archive_uuid5="$(bash "$AGENTBRAIN_DIR/scripts/uuid5-gen.sh" "local/reviews/$archive_basename" 2>/dev/null || echo "")"
	{
		echo "---"
		echo "date: $(date -u +%Y-%m-%d)"
		echo "type: review"
		[ -n "$archive_uuid5" ] && echo "id: $archive_uuid5"
		echo "doc-path: $DOC_PATH_ABS"
		echo "doc-content-sha256: $DOC_SHA"
		echo "reviewer: $REVIEWER"
		echo "requested-model: $MODEL_DISPLAY"
		echo "model-source: $MODEL_SOURCE"
		echo "reviewer-cli-version: $reviewer_version"
		echo "focus: $FOCUS"
		echo "timestamp: $TIMESTAMP"
		echo "prompt-template-version: 1.3.2"
		echo "---"
		echo ""
		echo "# Review of \`$(basename "$DOC_PATH_ABS")\` by $REVIEWER"
		echo ""
		echo "$BANNER"
		echo ""
		echo "$RESPONSE"
	} > "$archive_file"
	echo "" >&2
	echo "peer-review: archived to $archive_file" >&2
fi

exit 0
