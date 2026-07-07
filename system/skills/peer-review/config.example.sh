# shellcheck shell=bash
# shellcheck disable=SC2034  # vars are sourced by bin/peer-review
# config.example.sh — user preferences for peer-review.
# Copy to config.sh and edit. All values optional; the skill falls back to built-in
# defaults if a variable is unset.

# ── Default reviewer per source-agent ──
# If running INSIDE <key>, prefer <value> as reviewer.

DEFAULT_REVIEWER_FOR_claude="pi"
DEFAULT_REVIEWER_FOR_pi="claude"
DEFAULT_REVIEWER_FOR_copilot="claude"
DEFAULT_REVIEWER_FOR_gemini="claude"
DEFAULT_REVIEWER_FOR_aider="claude"

# ── Default model per agent CLI ──
# Empty = use the CLI's own default.
# Pass-through validation only — the agent CLI errors if model name is invalid.
#
# Personal cheat-sheet of models known to work (NOT validated by the skill):
#   claude:  claude-sonnet-4-6 (balanced), claude-opus-4-7 (deep), claude-haiku-4-5 (fast)
#   pi:      github-copilot/gpt-5.4, github-copilot/claude-sonnet-4.6, openai-codex/gpt-5.5
#   copilot: gpt-5.5, claude-sonnet-4 (provider-dependent)
#   gemini:  gemini-2.5-pro (default), gemini-2.5-flash (fast)
#   aider:   o4-mini, claude-sonnet-4-6, gpt-5

DEFAULT_MODEL_FOR_claude=""
DEFAULT_MODEL_FOR_pi=""
DEFAULT_MODEL_FOR_copilot=""
DEFAULT_MODEL_FOR_gemini=""
DEFAULT_MODEL_FOR_aider=""

# ── Behavior toggles ──

# Space-separated agents to never invoke as reviewer. Empty by default.
BLOCKED_AGENTS=""

# Default --archive behavior (true|false). Setting to true builds a self-improvement
# corpus over time in ../reviews/ — enables later pattern-analysis ("which model
# caught what kind of bug?").
ARCHIVE_DEFAULT="false"
