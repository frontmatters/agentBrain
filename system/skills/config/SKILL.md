---
name: config
description: Inspect and modify agentBrain configuration post-onboarding. Focus-based skill — walk-all (default) or one scope (locale, addons, hooks, preferences, shell-rc). Read-mostly: shows current state and routes mutations to the right tool rather than editing config directly.
argument-hint: "[locale|addons|hooks|preferences|shell-rc|--list]"
user-invocable: true
date: 2026-05-29
type: skill
tags: [skill, config, post-onboarding, focus-based]
id: 6eaed194-f55a-5dee-addc-7604fc47d582
---

# Config

Inspect and adjust agentBrain configuration after the initial `/onboard`. This
skill is a **dashboard + dispatcher**: it surfaces current state and routes
mutations to the right specialist tool (`/onboard <focus>`, `/addons`,
`/add-locale`, etc.) rather than becoming a second source of truth.

## Pattern

Follows the **focus-based skill** pattern — see `system/skill-patterns.md#focus-based-skill`.

```
/config                   walk-all   — show every scope's current state
/config <focus>           walk-one   — show + offer to mutate one scope
/config --list            introspect — list available scopes
```

Contract: idempotent per scope, detect-before-ask, repetition-safe.

## Scopes

| Scope | What it shows | Where mutations route to |
|---|---|---|
| `locale` | `AGENTBRAIN_LOCALE`, `$LANG`, resolved value, shell rc state | `/onboard locale` or edit `~/.zshrc` |
| `addons` | Installed addons, mode, last-config date; configured registries (`addons.sh registry list`) | `/addons enable\|disable\|install <id>` · registries: `addons.sh registry default [<url>\|reset]` (dev: point at Gitea), `addons.sh registry add\|remove <name> <url>` |
| `hooks` | Hooks registered in `~/.claude/settings.json`, by event type | `bash system/addons/<id>/install.sh` (re-register) |
| `preferences` | Scopes (personal/organization/team), file count, placeholder/customized counts | `/onboard <scope>` |
| `shell-rc` | Relevant agentBrain exports in `~/.zshrc` / `~/.bashrc` | Edit shell rc manually (auto-edit is intrusive) |

Run `bash ~/agentBrain/scripts/doctor.sh --summary --with-selftest` for a deeper
health audit — `/config` shows **what is set**, doctor shows **whether it
works**.

## Flow

### `--list`

Print the table above (scope names + one-line descriptions). No mutations.

### Walk-all (default, no args)

For each scope, run the scope-show logic. Output is compact — one section per
scope, ~5 lines each. End with: *"To change something, run `/config <focus>`
or use the routed command."*

### Walk-one (`/config <focus>`)

1. **Show** — current state of that scope, plus any drift indicators
2. **Ask** — only if there is something actionable: *"Change this? (y / N)"*
3. **Route** — if `y`, point the user at the right specialist tool with the
   exact command. Do NOT auto-execute the specialist; the user should see what
   they're about to run.

Exception: trivial single-line edits (e.g. setting a shell rc export) MAY be
applied directly if the user confirms — but always print the diff first.

## Per-scope implementation

### `locale`

```bash
echo "Resolved: $(AGENTBRAIN_LOCALE=${AGENTBRAIN_LOCALE:-} bash -c 'source ~/agentBrain/scripts/lib/_strings.sh; agentbrain_locale')"
echo "AGENTBRAIN_LOCALE env: ${AGENTBRAIN_LOCALE:-(not set)}"
echo "LANG: ${LANG:-(empty)}"
grep -E "^export AGENTBRAIN_LOCALE" ~/.zshrc ~/.bashrc 2>/dev/null | head -3
```

If `AGENTBRAIN_LOCALE` is unset and `$LANG` falls back to `en` but the user
prefers `nl` (or vice-versa): drift. Offer `/onboard locale`.

### `addons`

```bash
bash ~/agentBrain/scripts/addons.sh status 2>/dev/null
```

Format: addon-id, enabled/disabled, last config mtime. Drift = installed but
config older than 30 days OR enabled in config but hook missing in
`settings.json` (cross-check with `hooks` scope).

### `hooks`

Parse `~/.claude/settings.json` and list registered hooks per event:

```bash
python3 -c "
import json, os
s = json.load(open(os.path.expanduser('~/.claude/settings.json')))
for event, entries in (s.get('hooks') or {}).items():
    print(f'  {event}:')
    for e in entries:
        for h in e.get('hooks', []):
            print(f'    - {h.get(\"command\", \"?\")}')
"
```

Drift = hook command points at a script that no longer exists.

### `preferences`

For each scope under `local/preferences/`:

```bash
for scope in personal organization team; do
    dir="$HOME/agentBrain/local/preferences/$scope"
    [[ -d "$dir" ]] || { echo "  $scope/  (absent)"; continue; }
    total=$(find "$dir" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
    placeholders=$(grep -l "This is an example\|^<!-- Example:" "$dir"/*.md 2>/dev/null | wc -l | tr -d ' ')
    echo "  $scope/  $total file(s), $placeholders with placeholders"
done
```

Drift = placeholders > 0 → `/onboard <scope>` to fill them in.

### `shell-rc`

```bash
echo "AgentBrain-related exports in ~/.zshrc and ~/.bashrc:"
grep -nE "^export (AGENTBRAIN_|BRAIN_|PATH=.*agentBrain)" ~/.zshrc ~/.bashrc 2>/dev/null | sort -u
```

No drift detection here — just surface what's there so the user can audit.

## Rules

- **Read-mostly** — do not silently mutate config; offer to route instead
- **No new state files** — `/config` is a view over what already exists; it
  must not introduce its own JSON/YAML config
- **Skip-if-nothing-to-show** — if a scope has no relevant state on this
  machine (e.g. `hooks` when `~/.claude` doesn't exist), say so in one line
- **Locale-aware output** — use `t` helper from `_strings.sh` for headers
  (`generic.summary`, etc.) where strings exist

## Resumable behavior

Inherited from the focus-based pattern. Re-running `/config locale` after
fixing locale shows the new state without re-prompting.

## Related

- [[skill-patterns]] — the pattern this skill implements (focus-based)
- [[onboard]] — initial setup; `/config` is the post-onboarding twin
- `scripts/selftest.sh` — verifies that what `/config` shows actually works (script, not a skill)
- [[doctor]] — deeper health audit; `/config` is shallow status
- `scripts/addons.sh` — primary tool for addon mutations
- `scripts/lib/_strings.sh` — i18n source (for the `locale` scope)
