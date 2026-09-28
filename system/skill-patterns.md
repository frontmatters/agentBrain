---
date: 2026-05-29
type: system
tags: [skills, patterns, conventions]
id: 1060331f-d1d2-5595-a087-c7e65b988780
---

# Skill patterns

Conventions for building agentBrain skills. **Not** a style guide — these are
structural patterns that, when applied consistently, make skills predictable
for the user and easier to grow. Skip a pattern when it doesn't fit; cargo-cult
adoption is worse than ad-hoc design.

See also: `system/skills.md` (index), and — if installed — the `skill-creator`
skill (generic skill authoring, upstream from Anthropic).

---

## Optional private skill extension

Use when a public skill needs owner-specific strategy or preferences without publishing them or maintaining a full private fork. This is **additive**, not a second skill:

```
system/skills/<name>/SKILL.md   # standalone public procedure
vault/skills/<name>.private.md  # optional private additions; no SKILL.md
```

For an addon-provided skill, use the same `vault/skills/<invoked-name>.private.md` path. The shared agent instructions (`system/agent-config/shared.md`) tell agents to check this exact path **when invoking** the skill, not at session start. No private file means the public skill works unchanged. Use `<name>` as the skill's invocation name, not its display title. Never put a `.private` file anywhere under public `system/`: a dot-prefixed name does not prevent git tracking. `scripts/privacy-scan.sh` blocks tracked/staged paths there (including private-named directories), so both pre-commit and the pre-push doctor reject them. Do not create a duplicate `vault/skills/<name>/SKILL.md`: skill installers link the private skill over the public skill on name collision, so that would shadow rather than extend it.

Keep the extension small: extra criteria, decision heuristics, and local references only. Public skill logic, CLI commands, validation and safety stay in the public skill; the private extension may not bypass them. No mandatory private data or public references to private details. If the same private additions become generally useful, consider sanitizing and promoting only the mechanism. A private extension does **not** make a public artifact private: inspect generated output before publishing.

## Focus-based skill

**Use when** a skill has 2+ independent scopes that a user can want to bend in
isolation — typically configuration, onboarding, or audit flows that touch
several unrelated concerns.

**Skip when** the skill has one scope, or its top-level structure is actions
(`show` / `save` / `delete`) rather than scopes. Filters on data (`--only=`)
are also not scopes — those stay flags.

### Surface

```
<skill>                  walk-all     — iterate every scope, skip-if-done
<skill> <focus>          walk-one     — just that scope (still skip-if-done)
<skill> --list           introspect   — print available scopes; no mutations
```

The user gets a single mental model: *"I can always run `<skill> <focus>` to
revisit one part without redoing the rest."*

### Contract

Every focus-based skill MUST satisfy three rules:

1. **Idempotent per scope** — re-running with the same focus is a no-op unless
   something in the underlying state actually changed.
2. **Detect before ask** — read the current state first; only prompt the user
   about what is missing or stale. Never ask questions the answer to which is
   already on disk.
3. **`<skill> <focus>` ≡ running it 10×** — identical observable behaviour
   regardless of repetition count. No counters, no drift.

### Anti-patterns

- Accepting `<focus>` but secretly running every scope anyway (defeats the
  contract — users can't trust the boundary).
- Using flags (`--only=<focus>`) instead of a positional focus arg for a
  scope-based skill. Flags read as filters, focus reads as "do this scope".
  Pick the one that matches the mental model.
- Mixing scopes and actions on the same level: `/skill action scope` is
  confusing. If you need both, the action is the subcommand and scope is its
  arg: `/skill <action> <scope>`.

### When to also implement `--list`

Mandatory when the user can plausibly forget which scopes exist (e.g. addons,
agent modules). Optional when scopes are intuitive and short (e.g.
personal/organization/team).

### Concrete examples

| Skill | Scopes | Why focus-based fits |
|---|---|---|
| `/onboard` | personal, organization, team, addons, locale | Each scope is an independent decision the user revisits separately. |
| `/config` | locale, addons, hooks, preferences, shell-rc | Same — read-/write-config concerns are orthogonal. |
| `/audit-feature` | a11y, security, performance, lint, tests | A frontend dev wants to spot-audit a11y today, performance tomorrow. |
| `/brain-review` | stale, duplicate, frontmatter, orphans | Vault maintenance has separable hygiene axes. |

### Counter-examples (do not apply this pattern)

| Skill | Why not |
|---|---|
| `/journal` | `show`/`save`/`archive` are actions, not scopes — use subcommand pattern. |
| `/selftest` | `--only=<agent>` is a filter on auto-detected modules; user doesn't choose scope, machine state does. |
| `/save-learning` | Single concern (capture a learning). No scopes to split. |
| `/doctor` | One holistic audit. Flags (`--ci`, `--summary`, `--with-selftest`) tune the run, no scopes to address one-by-one. |

---

## Subcommand-based skill (for comparison)

**Use when** a skill has multiple distinct **actions** on the same target —
read/write/delete-style.

```
<skill> <action> [args]      e.g. /journal show, /journal save "note"
<skill>                      defaults to the safest read-only action (show/status/list)
```

Examples: `/journal`, `/addons` (`status`/`install`/`enable`/`disable`).

**Don't combine** with focus-based — pick one top-level surface, not both. If
a skill genuinely needs both (rare), the action is the top level and scopes
become its args: `/audit-feature run a11y` rather than `/audit-feature a11y run`.

---

## Authoring checklist

When writing a new skill that fits the focus-based pattern:

- [ ] Frontmatter `argument-hint` lists scopes explicitly: `"[personal|organization|team|...]"`
- [ ] SKILL.md has a `## Scopes` section enumerating each scope + what it does
- [ ] SKILL.md has a `## Resumable behavior` section quoting this pattern's contract
- [ ] If scopes are non-obvious, support `<skill> --list`
- [ ] Each scope's logic is wrapped in its own section/function, so adding a new scope is local
- [ ] Slash-command wrapper in `~/.claude/commands/<name>.md` passes `$ARGUMENTS` through; the SKILL.md handles parsing
- [ ] Update `system/skills.md` skills-table row with a hint at the scopes

When writing a subcommand-based skill, the equivalent checklist lives in the
skill itself (see `/journal` for a worked example).

---

## Related

- [[skills]] — canonical skill index (`system/skills.md`)
- [[onboard]] — focus-based reference implementation
- [[config]] — focus-based with `--list` and shell-rc detection
- [[session-journal]] — subcommand-based counter-example
