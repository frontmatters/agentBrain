---
date: 2026-05-29
type: system
tags: [addon, sessions, automation, claude]
id: 6c0cdcb8-fe8a-57b0-a959-401a3548a07f
---

# Session Journal (behavior)

Auto-fills `vault/sessions/session-journal.md` so the existing session-continuity flow has real content to archive. Without this addon the journals stay empty and `previous`-chains link a chain of empty files.

## What it does

| Trigger | When it fires | What it writes |
|---|---|---|
| **Stop hook** (`claude-stop-hook.sh`) | Claude Code session ends | Full journal update (project, task, files, done, next step) |
| **Autosave hook** (`claude-autosave-hook.sh`) | After every Write/Edit, throttled to 1×/5min by default | Same fields, refreshed in-place |
| **`/journal` slash command** | Manual | Show / save (with text) / archive |

All three call the same core script (`journal-update.sh`) so output is consistent.

## Install

```bash
bash system/addons/session-journal/install.sh
```

This registers the hooks in `~/.claude/settings.json` and copies the default config to `vault/sessions/journal-config.json` (only if missing — never overwrites your edits).

## Uninstall

```bash
bash system/addons/session-journal/uninstall.sh            # remove hooks, keep your config
bash system/addons/session-journal/uninstall.sh --purge    # also delete local config + hook log
```

Removes any `Stop`/`PostToolUse` hook entry in `~/.claude/settings.json` that points at this addon (unrelated hooks are left untouched). Idempotent — running it again, or with nothing installed, is a clean no-op. The seeded `vault/sessions/journal-config.json` is preserved unless you pass `--purge`.

## Configure

Edit `vault/sessions/journal-config.json`. Schema in `config.default.json`. Key knobs:

- `stop_hook.enabled` — disable per-trigger
- `autosave.mode` — `throttled_tool_use` (default) | `interval` | `disabled`
- `autosave.throttle_seconds` — minimum gap between autosaves
- `general.log_enabled` — write hook activity to `vault/sessions/.journal-hook.log`

## Files

- `journal-update.sh` — core, takes a transcript JSON path and updates the journal
- `claude-stop-hook.sh` — Stop hook adapter
- `claude-autosave-hook.sh` — PostToolUse hook adapter with throttling
- `journal-show.sh` — readable dump of current journal, used by `/journal show`
- `journal-archive.sh` — manual archive trigger, used by `/journal archive`
- `config.default.json` — defaults (in git)
- `install.sh` — registers hooks, seeds config
- `uninstall.sh` — removes our hooks from settings.json (`--purge` also drops local config)
- `tests/test-journal.sh` — parse roundtrip + corrupt-config + uninstall tests
- `manifest.md`, `README.md` — docs

## Locale

User-facing output (install script, selftest) is locale-aware. Resolution order:

1. `AGENTBRAIN_LOCALE=nl|en` (explicit override)
2. `$LANG` system locale (first two chars — `nl_NL.UTF-8` → `nl`, `en_US.UTF-8` → `en`)
3. Fallback: `en`

Strings live in `scripts/lib/_strings.sh`. Helper scripts (`journal-*.sh`) are English-only since their output is mostly mechanical (file paths, counts).

## Troubleshooting

**A config edit had no effect.** A corrupt `journal-config.json` no longer fails silently. The core script validates it on every run: a manual `/journal save`/update aborts with `not valid JSON` on stderr (exit 2), and the Stop/autosave hooks log `falling back to default config` to stderr and continue on the shipped defaults (a hook must never block session end). Fix the JSON or delete the file to fall back to `config.default.json`.

**The journal never updates.** Confirm the hooks are registered: `grep session-journal ~/.claude/settings.json`. If absent, re-run `install.sh` and add the printed hook lines. Check `vault/sessions/.journal-hook.log` for skip reasons (`addon disabled`, `stop_hook disabled`, `no transcript path`).

**Updates are too frequent / too sparse.** Tune `autosave.throttle_seconds` (minimum gap between autosaves) or set `autosave.mode` to `disabled`.

**`python3` not found.** The transcript parser is Python-only. Install python3; without it the hooks no-op silently by design (they must not block the session).

## Privacy

`local-only`. Transcript is parsed locally with `python3`; nothing is sent off-machine. Logging defaults on but stays in `vault/sessions/.journal-hook.log` (gitignored via `vault/.gitignore`).

**Context-aware routing.** The journal is written to the session's context, not always the shared vault. `journal-update.sh` resolves the session's `cwd` through `system/lib/context.sh` (`infer_context`): a session under a space's code-root (for example a client's `_work/` tree) routes to `vault/spaces/<slug>/sessions/`, which syncs to that space's own remote, never the personal vault. A confidential `_work/` session with no mapped space fails closed to a gitignored `vault/sessions/.quarantine/`, never the shared vault. A personal session routes to `vault/sessions/` as before. This keeps a client's identifiers inside the `_work/` boundary.

## Related

- `system/sessions.md` — the underlying session-continuity spec
- `system/agent-config/shared.md` — the session-start/journal-update rules
- `scripts/checks/check-session-schema.sh` — validates archive naming
