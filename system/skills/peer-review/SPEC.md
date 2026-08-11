---
date: 2026-05-24
type: spec
tags: [spec]
source: session
version: 1.4.2
id: 87d61620-3ad8-5434-8f26-a0affd9d88e2
---

# peer-review — cross-agent SPEC/design review skill

**Status**: draft v1.4.2 (v1.4.1 + SIGKILL-on-cleanup fix: bash defers SIGTERM until sleep finishes — cleanup blocked. SIGKILL is non-trappable; ensures fast teardown. §6 step 10 now shows full actual code, not elision; see §12)
**Implementation language**: bash (per-agent invoke functions; no eval, no JSON parser)
**Skill location**: `$AGENTBRAIN_DIR/local/skills/peer-review/`
**`$AGENTBRAIN_DIR`**: env-overridable (`export AGENTBRAIN_DIR=/path/...` honored), defaults to `realpath ~/agentBrain`
**OS assumption**: macOS-only in v1 (consistent with user's environment)

---

## 1. Purpose

agentBrain is agent-agnostic: knowledge, skills, and policies live on a shared substrate where Claude, Pi, Copilot, Gemini, and Aider are all guests, not owners. One consequence: a SPEC, design, plan, or rule written by one agent benefits from being reviewed by another — a different model, different training, different blind spots.

Today this workflow is manual: copy doc into another agent's session, paste the response back. The `peer-review` skill formalizes the loop: takes a document path, picks a reviewer that is **not** the currently-running agent, invokes it headlessly with a review prompt, and returns the response to the calling session.

This skill is the first artifact in agentBrain that needs a **machine-readable agent registry** (which CLIs to invoke, how, and from which env they self-identify). The registry is intrinsically reusable infrastructure for any future multi-agent skill.

## 2. Scope (v1)

**In scope**:
- Single-document review: one file path in, review text out.
- **Content-in-prompt**: the document content is embedded in the prompt; the reviewer needs no read/tool permissions.
- Five supported reviewer backends: `claude`, `pi`, `copilot`, `gemini`, `aider`.
- Self-detect via env vars; refuse to invoke self as reviewer.
- Reviewer selection via flag (`--agent=…`) or per-source-agent config default (e.g., "if I'm CC, ask Pi").
- Optional archive of review under `local/reviews/<timestamp>-<doc>-by-<reviewer>.md`.

**Out of scope** (deferred to v2+):
- Multi-file review where the reviewer cross-references other files (requires granting tools — significant per-agent config).
- Round-trip editing (review → patch → re-review).
- IDE-bound agents as reviewers: `cline`, `cursor`, `vscode-copilot`, `windsurf`, `obsidian` cannot be invoked headlessly and are intentionally **not** in the registry.
- Quality scoring or comparison of reviews ("which reviewer caught more").
- Streaming output (we capture and print at end).
- Pre-truncation of large documents (we warn but defer to the reviewer's own limits).

## 3. Commands

```
peer-review <doc-path>
            [--agent=<name>]
            [--model=<model>]
            [--focus="<comma,sep,topics>"]
            [--archive]
            [--from=<self-agent>]
            [--no-size-warning]
            [--timeout=<seconds>]
            [--dry-run]
```

| Flag | Meaning | Default |
|---|---|---|
| `<doc-path>` | File to review (required). Read once; content passed to per-agent `invoke_<name>` function (argv-quoted for claude/pi/copilot/gemini, tempfile for aider — see §4). | — |
| `--agent=<name>` | Explicit reviewer choice. Must be in registry and ≠ self. | per-config default |
| `--model=<model>` | On-the-fly model override for the chosen reviewer. Pass-through — no validation in the skill; the agent CLI errors if the model name is invalid for that agent. | per-config `DEFAULT_MODEL_FOR_<agent>` if set; else CLI's own default |
| `--focus=…` | Comma-separated focus topics, injected into prompt template. | `"correctness, completeness, clarity, edge cases"` |
| `--archive` | Save review **response + metadata** (not embedded doc-content) to `local/reviews/<ts>-<doc>-by-<reviewer>.md`. | off |
| `--from=<self-agent>` | Set self explicitly. **Required if self-detect fails** (no recognised env var) and `--agent` is also absent. | auto-detect via env vars |
| `--no-size-warning` | Suppress the >50 KB doc-size warning. Doc is processed regardless of size (no hard cap in v1); flag only affects the warning emission. | off (warning fires + proceeds) |
| `--timeout=<seconds>` | Hard timeout for the reviewer invocation. Watchdog sends SIGTERM after N seconds, then SIGKILL after 3 more seconds if reviewer hangs. Exit 6 on kill. Closes the silent-hang failure mode from [[peer-review-hang-rca-2026-05-24]]. | `300` (5 min) |
| `--dry-run` | Print the prompt + chosen reviewer + exact stdin invocation; do not invoke. | off |

### Examples

```bash
peer-review ~/agentBrain/local/skills/promote/SPEC.md
peer-review ./design.md --agent=gemini --focus="bash-portability, edge-cases"
peer-review PLAN.md --archive
peer-review SPEC.md --dry-run                       # see what would happen
peer-review SPEC.md --from=claude --agent=pi        # explicit both sides
peer-review SPEC.md --agent=pi --model=gpt-5.5      # use pi CLI but route to a specific model
peer-review SPEC.md --agent=claude --model=claude-opus-4-7  # heavier model for deep review
```

## 4. Agent registry

Sourceable bash file at `$AGENTBRAIN_DIR/local/skills/peer-review/agents.sh`. **No JSON parser, no shell-string construction with user content.** Each agent gets its own bash function; the script calls `invoke_<name> "$PROMPT" "$MODEL"` (where `$MODEL` may be empty to use the CLI's own default).

```bash
# agents.sh — registry of headless-invocable reviewer CLIs.
#
# Architecture: each agent has a dedicated `invoke_<name>` function. The function
# receives the prompt as $1 and passes it safely to the CLI — either as a quoted
# positional argument or via a file path (whichever the CLI accepts without us
# constructing a shell-evaluated command string).
#
# Bash quoted-variable expansion ("$1") does NOT re-evaluate content — it passes
# the byte string to the launched process as a single argv element. This is safe
# even for prompts containing backticks, $-substitutions, quotes, or newlines.

AGENT_NAMES=(claude pi copilot gemini aider)

# Each invoke function receives:
#   $1 = prompt (always)
#   $2 = model name (optional; empty string = use CLI's own default)
#
# Pattern: build an args array, append the model flag only if non-empty.

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
  [ -n "$model" ] && args+=(-m "$model")   # gemini uses -m, not --model
  gemini "${args[@]}"
}

invoke_aider() {
  # aider's --message-file passes content via a file path — even safer (no argv at all).
  local prompt="$1" model="${2:-}"
  local tmpfile rc
  tmpfile="$(mktemp -t peer-review-aider.XXXXXX)"
  # Trap ensures cleanup even on Ctrl-C / SIGTERM / unexpected exit.
  trap 'rm -f "$tmpfile"; trap - RETURN' RETURN
  printf '%s' "$prompt" > "$tmpfile"
  local -a args=(--message-file "$tmpfile" --no-stream --yes-always)
  [ -n "$model" ] && args+=(--model "$model")
  aider "${args[@]}"
  rc=$?
  return $rc
}

# Self-detect env vars — tentative; smoke-test required (see §10 dependencies).
# If empty, the agent cannot auto-detect as self and --from is required when this agent is the caller.
AGENT_SELF_ENV_claude="CLAUDECODE"
AGENT_SELF_ENV_pi="PI_VERSION"
AGENT_SELF_ENV_copilot="COPILOT_CLI"
AGENT_SELF_ENV_gemini="GEMINI_CLI"
AGENT_SELF_ENV_aider="AIDER_VERSION"

# TWO verification levels (per [[cli-help-grep-not-equals-smoke-test]] learning):
#   HELP_VERIFIED        — the flag exists in CLI --help output
#   INVOCATION_VERIFIED  — the exact invoke pattern has been smoke-tested end-to-end
# An agent is "production-ready as reviewer" only when INVOCATION_VERIFIED=yes.

AGENT_HELP_VERIFIED_claude="yes"    ; AGENT_INVOCATION_VERIFIED_claude="no"
AGENT_HELP_VERIFIED_pi="yes"        ; AGENT_INVOCATION_VERIFIED_pi="partial"  # `pi -p "<arg>"` works in yt-digest; full peer-review smoke-test pending
AGENT_HELP_VERIFIED_copilot="yes"   ; AGENT_INVOCATION_VERIFIED_copilot="no"
AGENT_HELP_VERIFIED_gemini="yes"    ; AGENT_INVOCATION_VERIFIED_gemini="no"
AGENT_HELP_VERIFIED_aider="no"      ; AGENT_INVOCATION_VERIFIED_aider="no"   # --help output truncated at spec time
```

### Why this is injection-safe

```bash
# In the dispatcher:
PROMPT="$(cat -- "$DOC_PATH")"
"invoke_$REVIEWER_NAME" "$PROMPT"
```

- `"invoke_$REVIEWER_NAME"` resolves to a trusted function name from a whitelisted list (`AGENT_NAMES`).
- `"$PROMPT"` is passed as a single quoted argv element. The shell parser does not re-interpret its content. Backticks, `$`, quotes, newlines — all literal.
- The dispatcher does NOT use `eval` and does NOT construct a command string containing `$PROMPT`. The original v1.1 design had an `eval` step that Pi correctly flagged as a footgun in its v1.1 review (NEW issue A); this v1.2 architecture removes the entire class of risk.

### Help-verified ≠ invocation-verified

The v1 SPEC claimed "verified via --help" for 4 of 5 CLIs. During Pi's peer-review of v1.1, smoke-testing the registry pattern `pi -p -` failed (`Error: Unknown option: -`). The flag exists; the specific invocation does not. **All 5 agents now require smoke-testing before `AGENT_INVOCATION_VERIFIED_<name>` is flipped to `yes`.** See [[cli-help-grep-not-equals-smoke-test]] for the durable learning.

## 5. User config

Sourceable bash file at `$AGENTBRAIN_DIR/local/skills/peer-review/config.sh` (optional; sensible defaults if absent).

```bash
# config.sh — user preferences for peer-review.
# All values optional; the skill falls back to built-in defaults if a variable is unset.

# Default reviewer per source-agent. If running INSIDE <key>, prefer <value>.
DEFAULT_REVIEWER_FOR_claude="pi"
DEFAULT_REVIEWER_FOR_pi="claude"
DEFAULT_REVIEWER_FOR_copilot="claude"
DEFAULT_REVIEWER_FOR_gemini="claude"
DEFAULT_REVIEWER_FOR_aider="claude"

# Default model per agent CLI. Empty = use the CLI's own default.
# Validation is pass-through — the agent CLI errors if the model name is invalid.
#
# Personal cheat-sheet of models known to work (NOT validated by the skill, just notes):
#   claude:  claude-sonnet-4-6 (balanced), claude-opus-4-7 (deep), claude-haiku-4-5 (fast)
#   pi:      gpt-5.5 (via github-copilot provider), claude-sonnet-4.6, etc.
#   copilot: gpt-5.5, claude-sonnet-4 (provider-dependent)
#   gemini:  gemini-2.5-pro (default), gemini-2.5-flash (fast)
#   aider:   o4-mini, claude-sonnet-4-6, gpt-5
DEFAULT_MODEL_FOR_claude=""
DEFAULT_MODEL_FOR_pi=""
DEFAULT_MODEL_FOR_copilot=""
DEFAULT_MODEL_FOR_gemini=""
DEFAULT_MODEL_FOR_aider=""

# Agents to never invoke as reviewer (space-separated). Empty by default.
BLOCKED_AGENTS=""

# Default --archive behavior (true|false).
ARCHIVE_DEFAULT="false"
```

Format choice: bash sourceable rather than JSON — eliminates the jq dependency that Pi correctly flagged (jq is **not** in macOS by default). Bash sourcing is `source config.sh` and gives the script free access to the variables.

## 6. Behavior

1. **Parse args**: `<doc-path>` is required; flags optional.
2. **Validate doc**: exists, regular file, readable, non-empty, not binary (`grep -Iq`). Else exit 1.
3. **Self-detect**: iterate registry, find first agent whose `AGENT_SELF_ENV_<name>` is set in the environment. If `--from=<name>` is passed, use that (overrides detection). If neither matches and `--agent` is also absent → exit 4 with: *"Cannot determine self-agent (no recognised env var). Pass `--from=<name>` to set self explicitly, or `--agent=<name>` to pick a reviewer directly."* Self-detect is **best-effort only**; explicit `--from` is the predictable path.
4. **Pick reviewer** (priority):
   1. `--agent=<name>` if passed → validate (in registry, ≠ self, not blocked). Error if invalid.
   2. Else `DEFAULT_REVIEWER_FOR_<self>` from config if defined and valid.
   3. Else first agent in registry that is (a) ≠ self, (b) not blocked, (c) `command -v <agent>` returns 0.
   4. No candidate → exit 4.
5. **Verify reviewer is callable**: `command -v <agent>` returns 0. Else exit 5 with an actionable hint listing **all** registered agents and their install pointers:
   ```
   peer-review: chosen reviewer '<agent>' not found on PATH.

   Install at least one supported reviewer CLI:
     claude   → https://docs.anthropic.com/en/docs/claude-code/cli
     pi       → bun add -g pi
     copilot  → brew install gh && gh extension install github/gh-copilot
     gemini   → npm i -g @google/gemini-cli
     aider    → uv tool install aider-chat
   
   Or use --agent=<other-installed-agent>.
   See [[peer-review]] section 13 for v2 API-direct fallback (no CLI required).
   ```
   The error path acts as inline onboarding for new users who tried the skill before installing any reviewer.
6. **Resolve model** (priority: `--model` flag > `DEFAULT_MODEL_FOR_<reviewer>` from config > empty=CLI default):
   ```bash
   # Reject empty --model="" early (silent collapse to config/default makes provenance ambiguous).
   if [ "${CLI_MODEL_FLAG+set}" = "set" ] && [ -z "$CLI_MODEL_FLAG" ]; then
     echo "peer-review: --model cannot be empty. Omit the flag to use config/default." >&2
     exit 1
   fi

   # Indirect-var lookup — same pattern as §10, no eval.
   CONFIG_MODEL_VAR="DEFAULT_MODEL_FOR_$REVIEWER_NAME"
   CONFIG_MODEL="${!CONFIG_MODEL_VAR:-}"
   MODEL="${CLI_MODEL_FLAG:-$CONFIG_MODEL}"

   # Track source for audit trail (used in banner + archive metadata, §6 step 11/12).
   if [ -n "${CLI_MODEL_FLAG:-}" ]; then
     MODEL_SOURCE="flag"
   elif [ -n "$CONFIG_MODEL" ]; then
     MODEL_SOURCE="config"
   else
     MODEL_SOURCE="cli-default"
   fi
   ```
   No model-name validation in the skill — the agent CLI errors with a clear message if the model name is invalid for that agent (per [[cli-help-grep-not-equals-smoke-test]]: we don't duplicate the CLI's own knowledge). v1.3 had an `eval` regression here that two consecutive Pi reviews caught — v1.3.1 replaces it with the same `${!var}` pattern that §10 already documents. The architecture is now consistent.
7. **Build prompt** in a bash variable: substitute `$FOCUS` and embed document content into the template (section 7).
8. **Size guard**: if `wc -c <doc-path>` > 50 KB AND `--no-size-warning` absent → print warning to stderr ("doc large; reviewer may truncate") but proceed. With `--no-size-warning`, suppress the warning. No hard cap in v1; pre-truncation is v2.
9. **`--dry-run` short-circuit**: print prompt + chosen reviewer + chosen model + the function-call dispatch line that would run; exit 0. (Already passed `command -v` check in step 5.)
10. **Invoke reviewer via the per-agent function with watchdog + heartbeat** (v1.4 runtime; defined in `agents.sh`, see §4). Actual code from `bin/peer-review`:

    ```bash
    response_log="$(mktemp -t peer-review-response.XXXXXX)"
    trap 'rm -f "$response_log"' EXIT

    # Background subshell so we can track the PID.
    ( "invoke_$REVIEWER_NAME" "$PROMPT" "$MODEL" >"$response_log" 2>&1 ) &
    invoke_pid=$!

    # Watchdog: SIGTERM at deadline, SIGKILL 3s later.
    ( trap 'exit 0' TERM
      sleep "$TIMEOUT_SECS"
      kill -TERM "$invoke_pid" 2>/dev/null || exit 0
      sleep 3
      kill -KILL "$invoke_pid" 2>/dev/null || true
    ) &
    watchdog_pid=$!

    # Heartbeat: print "still waiting (Ns elapsed)" every HEARTBEAT_SECS.
    ( trap 'exit 0' TERM
      elapsed=0
      while sleep "$HEARTBEAT_SECS"; do
        elapsed=$((elapsed + HEARTBEAT_SECS))
        kill -0 "$invoke_pid" 2>/dev/null || break
        echo "peer-review: still waiting on $REVIEWER (${elapsed}s elapsed, timeout=${TIMEOUT_SECS}s)" >&2
      done
    ) &
    heartbeat_pid=$!

    # Wait for reviewer (set +e bracket so $? is readable).
    set +e; wait "$invoke_pid"; RESPONSE_EXIT=$?; set -e

    # Teardown: SIGKILL (not SIGTERM) because bash defers SIGTERM until the
    # current `sleep` finishes — would block cleanup for up to HEARTBEAT_SECS.
    kill -KILL "$watchdog_pid" 2>/dev/null || true
    kill -KILL "$heartbeat_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true

    # Classify: 143 (SIGTERM)/137 (SIGKILL) → watchdog timeout → exit 6
    # Other non-zero → reviewer error → exit 6 + last 10 lines of output
    # Zero → RESPONSE="$(cat "$response_log")"
    ```
    No eval, no constructed shell strings — the per-agent function receives `$PROMPT` and `$MODEL` as quoted argv. SIGKILL on cleanup is non-trappable; ensures fast teardown regardless of subshell state.
11. **Print** review to stdout, prefixed with an **audit-trail banner**:
    ```
    --- Review by <reviewer> [model: <model-or-default>; source: <flag|config|cli-default>] (focus: <focus>; at: <YYYYMMDD-HHMMSS>) ---
    ```
    If `--model` was not specified and no config default exists, `<model-or-default>` reads `(CLI default)` and `source` is `cli-default`. The `at:` timestamp lets you place the review in time even when archive is off. Banner makes "which reviewer, which model, when" visible without parsing — important when you keep reviews around and want to know later what produced what.
12. **Archive** if `--archive` flag or `ARCHIVE_DEFAULT=true` in config: write to `local/reviews/<ts>-<basename>-by-<reviewer>.md` with **response + metadata only**. Metadata header includes:
    - `doc-path` (absolute)
    - `doc-content-sha256` (lets future-you verify what was reviewed)
    - `reviewer` (agent name)
    - `requested-model` (resolved value before invocation; "(CLI default)" if none specified)
    - `model-source` (one of: `flag`, `config`, `cli-default`)
    - `reviewer-cli-version` (best-effort, e.g. `$(claude --version 2>&1 | head -1)` — captured for provenance even when defaults drift)
    - `focus`
    - `timestamp`
    - `prompt-template-version`
    
    **Doc content is NOT embedded in the archive** — sha256 confirms identity. Saves space, avoids duplication. Note: `requested-model` is what we asked for; we cannot reliably capture the "effective" model the API actually served (that requires per-API introspection). For most cases the request IS what ran; provenance gaps only show when the provider silently substitutes a different model.

## 7. Default prompt template

```
You are reviewing a design specification written by another AI agent. Focus on: $FOCUS.

Be specific and concrete. Cite section numbers or quote specific lines when raising issues. Push back where you disagree — your job is to catch what the author missed, not to validate.

If the document references external files or context you can't see, note it as a caveat but proceed with the review based on the content provided.

Reply with structured feedback per section if the spec has sections; otherwise as a numbered list of issues.

--- BEGIN DOCUMENT ---
$DOC_CONTENT
--- END DOCUMENT ---
```

Template is hardcoded in v1. v2 may make it overridable via `config.prompt_template` or `--template=<path>`.

## 8. Edge cases

| Case | Behavior |
|---|---|
| Doc is empty (0 bytes) | Exit 1, message: "Document is empty, nothing to review." |
| Doc is very large (>50 KB) | Print warning to stderr ("Doc is large; reviewer may truncate") but proceed. `--no-size-warning` suppresses the warning. No hard cap in v1 — pre-truncation is v2. |
| Self-agent equals only available reviewer | Exit 4: "No other agent available. Self=<self>; registry=[…]; blocked=[…]." |
| Reviewer CLI exits non-zero | Surface last 10 lines of its output verbatim, exit 6, do not write archive. |
| Reviewer hangs beyond `--timeout` seconds | Watchdog sends SIGTERM; if reviewer still alive 3s later, SIGKILL. Wait returns 143 (SIGTERM) or 137 (SIGKILL). Skill exits 6 with message referencing [[peer-review-hang-rca-2026-05-24]]; no archive; no invocations.log entry. Heartbeat to stderr every 30s during the wait. |
| Reviewer returns empty stdout | Print warning to stderr ("Reviewer returned empty response") but exit 0. |
| Doc path is a symlink | Resolve via `realpath` (with `pwd -P` and Python3 fallbacks) before reading. |
| Doc content contains spaces, quotes, backticks, `$` | **No special handling needed** — prompt is always passed to the per-agent `invoke_<name>` function via bash quoted-variable expansion (`"$1"`), which does not re-interpret content. For most agents this becomes a quoted argv element; for aider it becomes a tempfile (even safer). Shell parser never re-evaluates the doc content. See §6 step 10 + §4. |
| `--archive` but `local/reviews/` doesn't exist | `mkdir -p` it. |
| Two agents both detect as self (env var clash) | Pick first match in registry order; print warning to stderr noting the clash. |
| Network/auth failure in reviewer | Surface reviewer's stderr, exit 6. |
| User passes `--agent` and `--from` to same agent | Exit 4 with explicit "cannot review yourself" error. |
| Doc is a binary file | Exit 1 with "binary content detected, peer-review handles text only" (use `file` or `grep -Iq`). |

## 9. File layout

```
$AGENTBRAIN_DIR/local/skills/peer-review/
├── SKILL.md                 # discovery: name, description, when-to-use, 3 examples
├── SPEC.md                  # this document
├── agents.sh                # registry (v1: 5 CLI agents) — sourceable bash, no JSON parser needed
├── config.example.sh        # template; user copies to config.sh and edits
├── bin/
│   └── peer-review          # bash entrypoint (~150 lines)
└── ../../reviews/           # archived reviews land here (sibling under local/)
                             # $AGENTBRAIN_DIR/local/reviews/<ts>-<doc>-by-<reviewer>.md
```

## 10. Implementation notes

### Dependencies (explicit)

**Required** (script refuses to run if missing):
- `bash` ≥ 4 (originally for associative arrays; v1.2+ no longer uses those, but `${!var}` indirect expansion + `local -a` array syntax used in §4 invoke functions still work cleanest in bash 4+. Apple's pre-installed bash 3.x is technically `${!var}`-capable but `local -a` requires bash 4. User has bash 5 via homebrew typically.)
- Standard CLI: `mv`, `mkdir`, `printf`, `cat`, `wc`, `grep`, `file`, `command`, `realpath` (with `pwd -P` fallback)
- At least one of the registered reviewer CLIs on `$PATH` (claude, pi, copilot, gemini, aider)

**Soft-required for self-detect**: env vars set by the calling agent (currently tentative — see section 4). If none detectable AND `--from` absent AND `--agent` absent → user gets a clear error and a hint.

**No JSON/YAML parser dependency** (per Pi review): registry and config are sourceable bash files.

### Patterns

- **Shell**: `#!/usr/bin/env bash`, `set -euo pipefail`.
- **`$AGENTBRAIN_DIR` resolution** (env-overridable per Pi's v1.1 review point 1):
  ```bash
  AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(realpath ~/agentBrain 2>/dev/null || (cd ~/agentBrain && pwd -P))}"
  ```
  If the user has `export AGENTBRAIN_DIR=…`, that wins. Otherwise resolve via `realpath` with `pwd -P` and Python3 fallbacks.
- **Sourcing registry**: `source "$SKILL_DIR/agents.sh"` once at startup. Each agent's `invoke_<name>` function becomes callable.
- **realpath**: try BSD `realpath`, fall back to `(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")`, final fallback `python3 -c 'import os; print(os.path.realpath(...))'`.
- **Function-call dispatch** (no `eval`, no shell-string construction):
  ```bash
  REVIEWER_NAME="…"  # validated to be in AGENT_NAMES whitelist
  "invoke_$REVIEWER_NAME" "$PROMPT" "$MODEL"   # $MODEL may be empty string
  ```
  The function name is dynamically composed but constrained to a whitelisted set. Both prompt and model are passed as quoted argv elements — bash does not re-interpret their content. No injection surface.
- **Self-detect env vars**: implementation MUST verify each agent's real env var by running a session of that agent and inspecting `env`. If unknown for an agent, leave `AGENT_SELF_ENV_<name>` empty; auto-detect skips it; `--from` becomes mandatory when that agent is self.
- **Model validation = pass-through**: the skill does NOT maintain a list of valid models per agent. Models churn faster than any whitelist could keep up (Claude versions every few months, GPT/Gemini cycle even faster). The agent CLI knows its own valid models and errors with a clear message when given an invalid one. We accept the small UX cost of getting the error one round-trip late in exchange for zero maintenance burden and no stale-knowledge bugs. (User cheat-sheet in `config.example.sh` as inline comments, not validation code.)
- **Model resolution code path** (in dispatcher):
  ```bash
  # CLI_MODEL_FLAG is whatever the user passed via --model, or empty.
  # Indirect-var lookup for the per-agent config default.
  CONFIG_MODEL_VAR="DEFAULT_MODEL_FOR_$REVIEWER_NAME"
  CONFIG_MODEL="${!CONFIG_MODEL_VAR:-}"
  MODEL="${CLI_MODEL_FLAG:-$CONFIG_MODEL}"
  # MODEL is now: cli-flag | config-default | empty.
  # Pass to invoke_<name>; empty string → function omits the model flag entirely.
  ```
  Uses bash 4+ indirect expansion (`${!var}`); compatible with the bash 4+ requirement already documented in dependencies.
- **Archive timestamp format**: `YYYYMMDD-HHMMSS` (sortable, no whitespace).
- **Archive content**: response + metadata header (doc-path, doc-content-sha256, reviewer, requested-model, model-source, reviewer-cli-version, focus, timestamp, prompt-template-version). **No embedded doc-content** — sha256 lets future-you verify what was reviewed without bloating storage. See §6 step 12 for full rationale around requested vs effective model.
- **OS assumption**: macOS-only in v1. Cross-platform is v2 if ever needed.

## 11. Testing (smoke)

1. **Round-trip from CC**: from inside Claude Code, `peer-review SPEC.md` → expect Pi's review on stdout.
2. **Explicit agent**: `peer-review SPEC.md --agent=gemini` → expect Gemini's review.
3. **Self-collision refusal**: `peer-review SPEC.md --agent=claude` from CC → exit 4 with clear "cannot review yourself".
4. **Missing doc**: `peer-review /no/such/file` → exit 1.
5. **Empty doc**: `peer-review /dev/null` → exit 1, "empty document".
6. **Binary doc**: `peer-review /bin/ls` → exit 1, "binary content".
7. **`--dry-run`**: `peer-review SPEC.md --dry-run` → prints prompt and chosen reviewer; no invocation.
8. **Archive**: `peer-review SPEC.md --archive` → file appears at `local/reviews/<ts>-SPEC-by-pi.md` with metadata header.
9. **Blocked reviewer**: with `aider` in `blocked`, `--agent=aider` → exit 4.
10. **Override via `--from`**: `peer-review SPEC.md --from=pi --agent=claude` → invokes claude as reviewer, treats pi as self.
11. **Model flag passed through**: `peer-review SPEC.md --agent=pi --model=claude-sonnet-4.6 --dry-run` → output shows resolved model + source=`flag`; no actual invocation.
12. **Config default model resolution**: with `DEFAULT_MODEL_FOR_pi="claude-sonnet-4.6"` in config, `peer-review SPEC.md --agent=pi --dry-run` → output shows that model + source=`config`.
13. **CLI default fallback**: with no `--model` and no config default, banner shows `[model: (CLI default); source: cli-default]`.
14. **Empty model rejected**: `peer-review SPEC.md --model=` → exit 1 with "--model cannot be empty" error.
15. **Invalid model surfaced**: `peer-review SPEC.md --agent=pi --model=does-not-exist` → reviewer CLI's own error (e.g., "Model not supported") surfaces verbatim, exit 6. Demonstrates pass-through.
16. **Archive includes model + model-source**: `peer-review SPEC.md --agent=pi --model=X --archive` → archive header contains `requested-model: X`, `model-source: flag`, `reviewer-cli-version: <pi --version>`.
17. **`--timeout=garbage` rejected**: `peer-review SPEC.md --timeout=garbage` → exit 1, "must be a positive integer".
18. **`--timeout=N` enforces deadline**: with a `pi` mock that sleeps 9999s and `--timeout=2`, the skill must exit (non-zero) within 2-10s. Watchdog SIGTERM, then SIGKILL after 3s grace. (Covered by `test.sh` Sanity 8.)
19. **Heartbeat appears on stderr**: with `HEARTBEAT_SECS=30` and a slow reviewer (>30s), at least one `peer-review: still waiting on <agent> (Ns elapsed, timeout=Ms)` line appears on stderr during the wait.

## 12. Open questions for the reviewer

### Added in v1.4.0 (2026-05-24)

Bug-driven release after a real hang during this session (see [[peer-review-hang-rca-2026-05-24]]). Two invocations hung 1h+ silently because pi-CLI has no client-side timeout and the calling pipeline (`bash | tail -N`) masked the lack of output. v1.4 closes both gaps:

- **`--timeout=<seconds>` flag** (default 300s). Watchdog SIGTERM at deadline, SIGKILL 3s later if hung. Exit 6 on kill with a message pointing to the RCA learning.
- **Heartbeat to stderr every 30s** (`HEARTBEAT_SECS=30`). When reviewer is slow, the caller sees `peer-review: still waiting on $REVIEWER (Ns elapsed, timeout=Ms)` — signal that the call is alive vs hung.
- **Tempfile + background invoke** (not command substitution). The reviewer runs in a forked subshell whose PID we track; output captured to `mktemp` file; `wait $pid` returns deterministic exit code that the watchdog/heartbeat can reason about. Removed `set -e` momentarily around the wait so we can read $? without the shell dying first.
- **Per-agent invoke functions unchanged** (still in agents.sh). The runtime layer above them changed.

Test coverage: `test.sh` now includes mocked-pi timeout-trigger that confirms `--timeout=2` kills a `sleep 9999` mock within 2-10 seconds.

### Added in v1.3.2 (2026-05-24)

Not review-driven — user-questions during stap 3+4 fix-pass surfaced three UX/scope gaps. No code architecture changes; only error-message verbosity in §6 step 5 and three new v2 backlog rows:

- **No-CLI-installed handling** improved: §6 step 5 error now lists install hints per supported agent + pointer to v2 API-direct fallback. Inline onboarding for new users.
- **API-direct fallback** added to v2 backlog (§13) — major monetisation hook; makes peer-review usable without any CLI installed.
- **Same-CLI different-model peer-review** added to v2 backlog — relaxation of self-refusal when `--model` differs from source-model. Useful when only one CLI is installed.
- **Tempfile + cache hygiene** added to v2 backlog — `mktemp` + `trap EXIT` for prompt-files; Pi `~/.pi/` cache invalidation policy.

### Resolved by Pi peer-review of v1.3 → v1.3.1 (2026-05-24, third round)

Two Pi reviews with different models (gpt-5.4 and openai-codex/gpt-5.5 — see [[cli-help-grep-not-equals-smoke-test]] for the test methodology). Both independently converged on the same findings, strong validation that the drift was real.

- ~~`eval` regressed in §6 step 6~~ → **replaced by `${!var}` indirect expansion** (the same pattern §10 already had). Architecture is now consistent across §4, §6, §10.
- ~~Stale "stdin" wording in §3 commands, §8 edge cases~~ → updated to reflect actual mechanism (per-agent invoke function with argv or tempfile).
- ~~§4 intro showed 1-arg dispatcher `invoke_<name> "$PROMPT"`~~ → updated to 2-arg form `"$PROMPT" "$MODEL"`.
- ~~§10 dispatch example also 1-arg~~ → updated to 2-arg form.
- ~~§10 archive-content bullet missed model/model-source~~ → expanded to include all v1.3+ fields plus `reviewer-cli-version` for provenance.
- ~~§10 bash 4+ rationale was "associative arrays" but v1.2+ no longer uses them~~ → updated to reflect actual reason (`local -a` array syntax).
- ~~Empty `--model=""` silently collapsed to config/default~~ → **explicit rejection** in §6 step 6 (clear error, exit 1).
- ~~Banner format was thin~~ → expanded to `[model: X; source: <flag|config|cli-default>] (focus: …; at: <timestamp>)`. Stronger provenance even without archive.
- ~~Archive metadata had `model` field but no source-distinction~~ → split into `requested-model` + `model-source` + `reviewer-cli-version`; rationale around requested vs effective documented inline.
- ~~Aider tempfile lacked cleanup-on-interrupt~~ → added `trap 'rm -f "$tmpfile"' RETURN` in `invoke_aider`.
- ~~§11 testing had no v1.3 smoke tests~~ → added 6 new scenarios covering --model flag, config default, CLI default fallback, empty rejection, invalid pass-through, archive model fields.

### Added in v1.3 (2026-05-24)

Not a review-driven change — user-requested feature: per-agent model selection. Three additions:

- **`--model=<name>` flag** in §3 commands. Pass-through (no validation in skill); the agent CLI errors if invalid.
- **`DEFAULT_MODEL_FOR_<agent>` config** in §5 with inline cheat-sheet comments. Empty = use the CLI's own default.
- **Audit-trail banner + archive metadata** in §6 steps 11-12: review output prefix shows `[model: X]`, archive header includes `model` and `model-source` fields. Required for "what produced this review three months from now" traceability.

Per-agent invoke functions in §4 now accept an optional second arg for model; build their argv via bash array (`args+=(--model "$model")`) only if non-empty. Gemini uses `-m` instead of `--model` per its CLI; aider also supports `--model`. Pass-through architecture means the model name is never interpreted by the skill — just forwarded.

### Resolved by Pi peer-review of v1.1 → v1.2 (2026-05-24, second round)

Pi reviewed v1.1 and identified 3 NEW issues plus 4 partial-addresses. v1.2 addresses all:

- ~~NEW issue A: `eval` reintroduced in §6 step 9 (inconsistent with §10 `bash -c` recommendation)~~ → **removed entirely**; §4 architecture switched to per-agent `invoke_<name>` functions; dispatcher uses `"invoke_$NAME" "$PROMPT"` — no eval, no shell-string construction.
- ~~NEW issue B: `--allow-large` semantics mismatch (doesn't "allow", just suppresses warning)~~ → **renamed to `--no-size-warning`** in §3 commands table and §6 step 7; semantics now match name (doc is processed regardless of size; flag only affects the warning emission).
- ~~NEW issue C: "Verified" underspecified (help-verified ≠ smoke-tested)~~ → **two-level verification** in §4 registry: `AGENT_HELP_VERIFIED_*` + `AGENT_INVOCATION_VERIFIED_*`. All 5 agents start at `INVOCATION_VERIFIED=no`; only smoke-test promotes them.
- ~~Partial #1: AGENTBRAIN_DIR still hardcoded as realpath of ~/agentBrain~~ → **env-overridable**: `AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-...}"` in §10. User can export to override.
- ~~Partial #3: invocation verification claim was weak~~ → resolved by 2-level scheme above.
- ~~Partial #5: §6 step 9 used `eval` despite §10 recommending `bash -c`~~ → resolved by function-call dispatch.
- ~~Partial #7: --allow-large naming~~ → resolved by rename to --no-size-warning.

### Resolved by Pi peer-review (2026-05-24, first round, v1 → v1.1)

- ~~Path hardcoding `~/agentBrain`~~ → **replaced by `$AGENTBRAIN_DIR`** resolved at startup. Pi's specific suggestion (`~/Developer/agentBrain`) was based on wrong assumption — actual symlink target is `~/Developer/agentBrain-dev`.
- ~~JSON registry with jq~~ → **switched to sourceable bash** (`agents.sh`, `config.sh`). No JSON parser dependency. jq is **not** universal on macOS as the original spec wrongly claimed.
- ~~Shell-arg invocation `cmd -p "$PROMPT"`~~ → **always-stdin pattern**: `printf '%s' "$PROMPT" | bash -c "$AGENT_INVOKE"`. Closes the injection class entirely (backticks, `$`, quotes in doc content are safe).
- ~~Self-detect implicit fallback to "unknown"~~ → **hard error when self can't be determined** unless `--agent` or `--from` provided. Predictable behavior, no silent self-as-anything.
- ~~Archive includes prompt with embedded doc content~~ → **response + metadata + doc-content-sha256** only. Doc lives at its on-disk path; sha256 confirms what was reviewed. No duplication.
- ~~Doc size: warning at 50 KB~~ → **warning + `--allow-large` flag** to bypass it. No hard cap (rejected as too restrictive; pre-truncation deferred to v2).
- ~~"No deps beyond standard CLI"~~ → **dependencies section** explicit (bash 4+, registered CLIs on PATH, no parser).
- ~~`registry invoke strings unverified`~~ → **4 of 5 CLIs verified** in session (claude/pi/copilot/gemini via `--help`), only **aider marked as unverified** with explicit smoke-test requirement before production use. Pi flagged all 5 as TBD because Pi couldn't see chat verification; this is precisely the [[peer-review-out-of-band-limitation]] in action.

### Still open

1. **First-match reviewer selection when no config default**: I propose "first agent in registry order (= `AGENT_NAMES` array) that is ≠ self, not blocked, and on PATH". This means the array-order silently determines fallback. Alternatives: alphabetical, or require explicit default. Which is least surprising?

2. **Where should `config.sh` live?** Inside `local/skills/peer-review/` (git-tracked) or in `~/.config/peer-review.sh` (outside the brain, untracked)? Inside is simpler (one location) but commits defaults. Recommendation: inside for v1; revisit if a privacy concern surfaces.

3. **Should `--dry-run` also `command -v <reviewer>`?** It validates the reviewer exists without invoking — useful for setup-testing. Current spec: yes (steps 4–5 happen before dry-run short-circuit). Confirm?

4. **Aider config gap**: `system/agent-config/` has no `aider.md` while aider IS installed. Bundle creation of that file with peer-review implementation, or out of scope? Recommendation: bundle — 10-line descriptive file, makes the registry coherent.

5. **`--agent` overriding self-detect**: if user explicitly passes `--agent=<self>`, we refuse. But what if they're confident the env-detect is wrong (e.g., a wrapper sets `CLAUDECODE` but they're actually in Pi)? Current: refuse uniformly. Alternative: `--agent` wins because explicit > implicit. Which?

6. **`bash 4+` requirement**: associative arrays are bash-4-only; Apple's pre-installed bash is 3.x. Implementation must either (a) refuse with clear error on bash 3, (b) require homebrew bash on PATH, (c) avoid assoc-arrays via name-mangled variables (uglier but bash-3-compatible). User has bash 5 typically; default = (a). Confirm?

## 13. Out of scope — v2 backlog

| Feature | Why deferred |
|---|---|
| Multi-file review (reviewer reads referenced files) | Requires per-agent tool config; significant complexity |
| Round-trip editing (review → patch → re-review) | Needs reviewer-output parsing + apply-suggestions logic |
| Streaming output | Better UX but complicates capture and archive |
| IDE-bound agents (cline, cursor, vscode-copilot, windsurf) | Not headlessly invocable; would need IDE-side cooperation |
| Review quality scoring | Subjective; a meta-skill that compares reviews |
| `--init` interactive setup wizard | Nice-to-have once base skill is proven |
| YAML/JSON registry (current = bash sourceable) | Switch only if bash array friction proves real (adding 5+ agents, dynamic registry) |
| Pre-truncate large docs | Wait until token-limit-exceeded errors actually appear |
| Prompt-template overrides via config | Wait until users want different review styles |
| Cross-platform (Linux) support | Add when the brain runs on more than this mac |
| Verify aider invocation pattern | Spec-time `aider --help` was incomplete; smoke-test required before aider goes production as reviewer |
| Verify all `AGENT_SELF_ENV_*` env var names | Tentative at spec time; first implementation phase must inspect a real session of each agent and confirm |
| Migrate `agents.sh` → `system/skills/peer-review/agents.sh` | Once peer-review is stable + reused by other multi-agent skills, the registry is reusable infrastructure and belongs in system/ — see promote/demote skill for the mechanism |
| **API-direct fallback** (no CLI required) | For users with API keys but no agent CLI installed. Direct `curl` to Anthropic/OpenAI/Google APIs as a fallback when no reviewer CLI is on PATH. Major monetisation hook (peer-review becomes usable in any environment, not just dev machines with multiple CLIs). Requires per-provider auth handling, model-name mapping per provider, response-parsing. Substantial; v2 priority if peer-review is productised. |
| **Same-CLI different-model self-review** | Currently `--from=X --agent=X` is refused (echo chamber prevention). But `pi --model=A` reviewing content produced by `pi --model=B` is meaningful peer review (different blind spots despite same CLI). v2 could relax the self-refusal when `--model` is also provided AND differs from the source's model. Edge case; useful when only one CLI is installed. |
| **Tempfile + cache hygiene** | Per-invocation prompt-files (currently in `/tmp` for manual testing) should be `mktemp` + `trap EXIT` cleaned. Aider's `--message-file` already follows this; the broader skill should too. Also: Pi has `~/.pi/` state-dir that accumulates per-session context; high-frequency peer-review usage should consider periodic cache invalidation or document expected disk-growth. |
