---
name: addon-create
description: Scaffold a new agentBrain addon registry entry with manifest, README, optional SKILL, and validation. Use when creating a new addon like a CLI integration, transport, skill bundle, or optional tooling package.
argument-hint: Addon id, name, install command, command, privacy, install_method
user-invocable: true
related: [import-external-skill]
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
- `system/addons/<id>/CHANGELOG.md` — not optional (see "Changelog convention"
  in `system/addons/README.md`): the addon is distributed as a standalone zip,
  so a consumer installing it on another machine has no access to this repo's
  git history — the in-package changelog is their only way to see what changed.

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

4b. **Write `CHANGELOG.md`**
   - Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) —
     `## [Unreleased]` then `## [0.1.0] - <date>` with `### Added`, newest
     version headings first for future bumps.
   - Versioning: [SemVer](https://semver.org/spec/v2.0.0.html) — the version
     in the heading must always equal `manifest.md`'s `version:`.
   - Bump this in the same change that bumps `manifest.md`'s `version:` —
     never let them drift apart.

5. **Optionally scaffold `SKILL.md`**
   Add only when the addon has a real operator workflow worth standardizing.
   When writing the `description:` field, prefer the YAML **block scalar `>-`**
   form over a bare scalar — descriptions often contain `: ` (colon+space, e.g.
   `Triggers: "..."` or inline YAML like ``hidden: true``), which breaks strict
   YAML parsers (pi) while slipping past lax ones (Claude Code). Example:
   ```yaml
   description: >-
     Your multi-clause description here. Colons and quotes are safe in this form.
   ```
   After writing, run `bash scripts/checks/check-frontmatter.sh` to validate.

5b. **Wire the SKILL into every agent** (only if you scaffolded a `SKILL.md`)
   A skill file in the repo is NOT visible to any agent until it is symlinked
   into each agent's native skills dir. There are three agents (Claude Code,
   Copilot CLI, Pi), wired by two scripts — the two commands below together
   cover all three, so run both:
   ```bash
   bash scripts/setup/setup-skills.sh      # Claude Code + Copilot (shared agent table)
   bash scripts/configure-pi.sh      # Pi (extra config beyond skills)
   bash scripts/checks/check-skill-links.sh # must report 0 failed — validates all three
   ```
   All three link the SAME skills under the hood (shared `scripts/lib/skills.sh`);
   Pi just needs its own script because it also wires extensions, tsconfig,
   keychain, and a wrapper binary. Enabling the addon via `addons.sh install`
   (step 7) re-syncs addon-provided skills for Claude Code + Copilot only, so
   the two commands above remain the way to cover Pi and any standalone skill.
   Note: a **standalone** skill dropped straight into `system/skills/<name>/`
   (not an addon) gets no auto-wire at all — the same two commands are the only
   way it becomes visible. `check-skill-links.sh` (run by the doctor) is the
   backstop that catches this drift regardless of how the skill was added.

6. **Validate**
   Run:
   ```bash
   bash scripts/checks/check-addons.sh <id>
   bash scripts/privacy-scan.sh
   ```

7. **If the user wants it enabled**
   Use:
   ```bash
   bash scripts/addons.sh install <id>
   ```
   Do not manually create `vault/addons/<id>/enabled`.

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
  - vault/example/*.json
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
- Never leave a scaffolded `SKILL.md` unwired — run the step-5b commands and
  confirm `check-skill-links.sh` reports 0 failed before calling it done.
- Public add-on docs describe the tool, not private machine data.

## References

- `system/addons/README.md`
- `system/skills/addons/SKILL.md`
- `system/rules.md`
