# shellcheck shell=bash
# shellcheck disable=SC2034  # vars are used by bin/peer-review which sources this file
# agents.sh — registry of headless-invocable reviewer CLIs.
#
# Architecture: each agent has a dedicated `invoke_<name>` function. The function
# receives the prompt as $1 and optionally the model as $2 and passes them safely
# to the CLI — either as a quoted positional argument or via a file path
# (whichever the CLI accepts without us constructing a shell-evaluated string).
#
# Bash quoted-variable expansion ("$1") does NOT re-evaluate content — it passes
# the byte string to the launched process as a single argv element. Safe for
# prompts containing backticks, $-substitutions, quotes, or newlines.
#
# Self-improvement: peer-review writes to state/invocations.log on every successful
# invocation. After first success for an agent, the next session can read the log
# and treat that agent as INVOCATION_VERIFIED=yes without flipping this file.

AGENT_NAMES=(claude pi copilot gemini aider)

# ── invoke functions ──────────────────────────────────────────────
# $1 = prompt (always)
# $2 = model name (optional; empty string = use CLI's own default)

invoke_claude() {
	local prompt="$1" model="${2:-}"
	local -a args=(-p "$prompt")
	[ -n "$model" ] && args+=(--model "$model")
	claude "${args[@]}"
}

invoke_pi() {
	local prompt="$1" model="${2:-}"
	local -a args=(-p "$prompt")
	[ -n "$model" ] && args+=(--model "$model")
	pi "${args[@]}"
}

invoke_copilot() {
	local prompt="$1" model="${2:-}"
	local -a args=(-p "$prompt")
	[ -n "$model" ] && args+=(--model "$model")
	copilot "${args[@]}"
}

invoke_gemini() {
	local prompt="$1" model="${2:-}"
	local -a args=(-p "$prompt")
	[ -n "$model" ] && args+=(-m "$model")    # gemini uses -m, not --model
	gemini "${args[@]}"
}

invoke_aider() {
	# aider's --message-file passes content via a file path — even safer (no argv at all).
	local prompt="$1" model="${2:-}"
	local tmpfile rc
	tmpfile="$(mktemp -t peer-review-aider.XXXXXX)"
	# Fix (Pi review #4): match spec — lazy-eval $tmpfile + reset trap.
	# Single-quotes prevent immediate expansion; $tmpfile resolves at trap-fire time.
	# `trap - RETURN` resets the trap (cosmetic for one-shot RETURN traps, but matches SPEC).
	# shellcheck disable=SC2064
	trap 'rm -f "$tmpfile"; trap - RETURN' RETURN
	printf '%s' "$prompt" > "$tmpfile"
	local -a args=(--message-file "$tmpfile" --no-stream --yes-always)
	[ -n "$model" ] && args+=(--model "$model")
	aider "${args[@]}"
	rc=$?
	return $rc
}

# ── self-detect env vars ──────────────────────────────────────────
# Set when running INSIDE the named agent. Tentative — verify per agent.
# Empty value = cannot auto-detect; user must pass --from=<name>.

AGENT_SELF_ENV_claude="CLAUDECODE"
AGENT_SELF_ENV_pi="PI_VERSION"
AGENT_SELF_ENV_copilot="COPILOT_CLI"
AGENT_SELF_ENV_gemini="GEMINI_CLI"
AGENT_SELF_ENV_aider="AIDER_VERSION"

# ── verification state (see [[cli-help-grep-not-equals-smoke-test]]) ──
# HELP_VERIFIED       — flag exists in CLI --help output
# INVOCATION_VERIFIED — exact invoke pattern has been smoke-tested end-to-end
# Self-updating: after first successful invocation, peer-review writes to
# state/invocations.log; future sessions treat that agent as invocation-verified.

AGENT_HELP_VERIFIED_claude="yes"     ; AGENT_INVOCATION_VERIFIED_claude="no"
AGENT_HELP_VERIFIED_pi="yes"         ; AGENT_INVOCATION_VERIFIED_pi="yes"  # verified in this session
AGENT_HELP_VERIFIED_copilot="yes"    ; AGENT_INVOCATION_VERIFIED_copilot="no"
AGENT_HELP_VERIFIED_gemini="yes"     ; AGENT_INVOCATION_VERIFIED_gemini="no"
AGENT_HELP_VERIFIED_aider="no"       ; AGENT_INVOCATION_VERIFIED_aider="no"
