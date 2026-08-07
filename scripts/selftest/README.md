---
date: 2026-05-29
type: system
tags: [selftest, scripts, agents]
id: 8327e9b7-eddb-50cd-924b-58ff4328842d
---

# scripts/selftest/ — agent-agnostic selftest modules

The dispatcher (`scripts/selftest.sh`) sources every `*.sh` file in this directory
and runs the agent-specific check sections only for agents detected on the
current machine. The generic section always runs.

## File layout

| File              | What it covers                                                   |
|-------------------|------------------------------------------------------------------|
| `_lib.sh`         | Shared helpers (`ok` / `nok` / `wrn` / `hdr` / counters)         |
| `generic.sh`      | Vault root, UUID5, frontmatter validator, session schema         |
| `claude-code.sh`  | Claude Code: `session-journal` + `claude-memory-redirect` addons |
| `pi.sh`           | Pi: extensions + skills symlinks, tsconfig                       |
| `copilot-cli.sh`  | GitHub Copilot CLI: pointer + skills dir                         |
| `gemini-cli.sh`   | Gemini CLI: GEMINI.md pointer                                    |

## Contract for a new agent module

Each `<agent>.sh` must define two functions with unique names (no associative
arrays — Bash 3 compat):

```bash
detect_<agent>() {
    # Return 0 if this agent is installed on this machine, 1 otherwise.
    command -v <cli> &>/dev/null || [[ -d "$HOME/<config-dir>" ]]
}

run_<agent>() {
    hdr "<Display Name>"
    # ok/nok/wrn calls — they mutate dispatcher-owned counters in place.
}
```

The dispatcher discovers modules by name, not by listing — to add a new agent,
drop a `scripts/selftest/<agent>.sh` file and register the agent id in
`scripts/selftest.sh`'s `AGENT_MODULES` array.

## i18n

Use `$(t selftest.<agent>.<key>)` for user-facing strings so all output is
localisable. Add the keys in both `_t_en()` and `_t_nl()` in
`scripts/lib/_strings.sh`. Missing keys fall back to English silently.

## Idempotency & non-destructiveness

Selftest modules MUST be safe to re-run:

- Read configuration, do not mutate it
- One write/delete cycle is acceptable for end-to-end checks (e.g. the
  `claude-memory-redirect` write-through test) — clean up after yourself
- Never edit `~/.claude/settings.json`, agent config files, or `local/`
