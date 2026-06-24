---
name: addon-create
description: Scaffold a new agentBrain addon registry entry with manifest, README, optional SKILL, and validation. Use when creating a new addon like a CLI integration, transport, skill bundle, or optional tooling package.
argument-hint: Addon id, name, install command, command, privacy, install_method
user-invocable: true
resources:
  - system/addons/README.md
  - system/skills/addons/SKILL.md
  - system/rules.md
---

# Addon Create

Scaffold a new add-on under `system/addons/<id>/` with the correct registry shape.

## Goal

Create a reusable, validated addon entry without hand-rolling manifest fields each time.

## Output

At minimum:
- `system/addons/<id>/manifest.md`
- `system/addons/<id>/README.md`

Optional:
- `system/addons/<id>/SKILL.md`
- `system/addons/<id>/install.sh`
- `system/addons/<id>/config.default.json`

## Required decisions

Before writing, gather or infer:
- `id` — lowercase/kebab-case, must equal directory name
- `name` — display name
- `install` — shell install command or setup command
- `command` — health-check binary/command when relevant
- `privacy` — `local` | `sends-docs` | `sends-all`
- `install_method` — `self` | `ai-driven` | `config-entry`
- support matrix — set unknown by default unless known

## Procedure

1. **Check whether the addon already exists**
   - If yes: update instead of creating a duplicate.

2. **Create the directory**
   - `system/addons/<id>/`

3. **Write `manifest.md`**
   - Use the schema from `system/addons/README.md`
   - `id` must match the folder name exactly
   - Default unknown support entries unless known
   - Add `outputs:` if the addon produces files

4. **Write `README.md`**
   Include:
   - what it is
   - install command
   - quick use
   - good fits
   - privacy note

5. **Optionally scaffold `SKILL.md`**
   Add only when the addon has a real operator workflow worth standardizing.

6. **Validate**
   Run:
   ```bash
   bash scripts/check-addons.sh <id>
   bash scripts/privacy-scan.sh
   ```

7. **If the user wants it enabled**
   Use:
   ```bash
   bash scripts/addons.sh install <id>
   ```
   Do not manually create `local/addons/<id>/enabled`.

## Templates

### Minimal manifest

```md
---
id: example-addon
name: Example Addon
version: 0.1.0
install: bash system/addons/example-addon/install.sh
command: example-binary
privacy: local
install_method: self
support:
  pi: full
  claude: unknown
  copilot: unknown
outputs:
  - local/example/*.json
---

# Example Addon
```

### Minimal README sections

- Install
- Quick use
- Good fits
- Privacy

## Guardrails

- Do not skip privacy classification.
- Do not invent support levels unless known.
- Prefer `unknown` over guessing.
- Use `addons.sh install` for enable/onboarding flows.
- Public add-on docs describe the tool, not private machine data.

## References

- `system/addons/README.md`
- `system/skills/addons/SKILL.md`
- `system/rules.md`
