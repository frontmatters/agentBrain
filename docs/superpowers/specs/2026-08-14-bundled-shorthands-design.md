# Bundled + self-declared shorthands — design

Date: 2026-08-14
Status: approved (brainstorm)

## Goal

Ship a small set of **default shorthands** with agentBrain (so a fresh install
already understands `ab`, `moc`, and the enabled addons' names) **without** taking
away the user's ability to define their own. Addons declare their own shorthand in
their manifest — the same "addons describe themselves" pattern as `author:`.

## Non-goals (YAGNI)

- **No general dev-convention shorthands** in the bundle (e.g. `ksc` =
  SemVer+KaC+Conventional Commits). Those are not agentBrain-specific → they stay
  in the user's local layer.
- **No shell aliases** for bundled/addon shorthands. Bundled shorthands are
  glossary **terms** only; writing an `alias` into every user's `~/.zshrc` for every
  enabled addon is invasive. A cmd-alias remains a deliberate local choice.
- No change to how the user adds their own shorthands (`shorthand add …`).

## Sources & precedence

`shorthand apply` merges **three** sources into the generated glossary note
(`local/preferences/personal/shorthand.md`) and — for `cmd`-kind entries only, which
come from the local layer — the managed `~/.zshrc` block:

| Layer | Source | Example | Precedence |
|---|---|---|---|
| Local | `local/addons/shorthand/shorthand.json` (user) | user's own, via `shorthand add` | **highest — wins** |
| Core | `system/addons/shorthand/shorthand.system.json` (bundled, read-only) | `ab` → agentBrain, `moc` → Map of Content | wins over addon |
| Addon-derived | `shorthand:` field in **enabled** addon manifests | `ytd` → youtube-digest | lowest |

Precedence on a colliding short: **local > core > addon-derived.**

- An addon **cannot hijack** a core short (`ab`/`moc`): core wins.
- **Addon-vs-addon** collision on the same short: deterministic winner = the addon
  whose `id` sorts first alphabetically; `check-addons` emits a WARN naming both.
- Local always overrides, so the user is never stuck with a default.

## Manifest field

New **optional** manifest field (lowercase handle, like `author:`):

```yaml
shorthand: ytd
```

- Expands to a **term**: `ytd` → the addon's `name` (human label). Kind = `term`.
- Absent → the addon contributes no shorthand (most addons).
- Enabled-gated: the derived shorthand appears only while the addon is enabled;
  disabling the addon removes it on the next `apply`.

## Components affected

1. **`system/addons/shorthand/bin/shorthand`** (`apply` + `check`): add the
   addon-derived source. On apply, enumerate enabled addons (reuse the addons
   layer's enabled-state: `local/addons/<id>/enabled` + `manifest_path`), read each
   manifest's `shorthand:`, and merge as `term`/`system`-layer entries beneath core
   and local. The drift-guard (`check`) must render the same merged set.
2. **`scripts/check-addons.sh`**: validate `shorthand:` when present — lowercase,
   no whitespace, and unique across bundled addons (WARN on collision). Optional
   field; not added to `REQUIRED`.
3. **`system/addons/_template/manifest.md`** + `system/addons/README.md`: document
   the optional `shorthand:` field and the three-layer model.
4. **Stamp `shorthand:` on the addons that deserve one** — decided in the plan
   (candidates: `youtube-digest` → ytd, others as fit). Not every addon needs one.

## Data flow (apply)

```
shorthand apply
  ├─ read core     shorthand.system.json        → [ab, moc]  (term/system)
  ├─ read addons   for each enabled addon: manifest.shorthand → term/system
  │                 (skip if absent; addon-vs-addon: id-alpha wins)
  ├─ read local    shorthand.json               → user entries (term|cmd/local)
  ├─ merge          local > core > addon-derived
  ├─ write         local/preferences/personal/shorthand.md  (marked `:short`)
  └─ write         ~/.zshrc managed block        (only local cmd-kind entries)
```

## Rendering

Addon-derived entries render in the glossary like core ones, layer = `system`
(they are framework-shipped). Marked form uses the configured marker (default `:`),
e.g. `| :ytd | youtube-digest | term | system |`.

## Error handling

- Malformed/oversized manifest, or a `shorthand:` with illegal chars → skip that
  addon's shorthand, don't fail `apply`; `check-addons` reports the format issue.
- Missing enabled-state / unreadable manifest → skip silently (addon simply
  contributes nothing).

## Testing

Extend `system/addons/shorthand/tests/test-shorthand.sh`:

- An enabled addon with `shorthand: foo` surfaces `foo` in the glossary (term/system).
- Disabling that addon removes `foo` on re-apply.
- Local override of an addon-derived short: local wins.
- Core beats an addon that declares `ab`.
- Two addons declaring the same short: deterministic (id-alpha) winner.
- `check-addons`: bad `shorthand:` format flagged; duplicate across addons WARNs.

## Rollout

Additive and backward-compatible: `shorthand:` is optional, precedence keeps
existing core + local behaviour intact, and no shell writes are introduced for the
new source. Ship under shorthand's next MINOR (e.g. 0.4.0) + a CHANGELOG entry.
