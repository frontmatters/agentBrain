---
name: wash-vault
description: Run vault content through a deterministic cleaning filter — the agentBrain "laundromat". Detects and (optionally) fixes id-mismatches, missing frontmatter, and unsafe characters in note filenames. Default mode is dry-run (preview only); add --fix to apply changes. Use before a vault-batch-commit to normalize the dirty state.
related: []
---

# wash-vault — the agentBrain laundromat

Detect and (with `--fix`) repair the deterministic content-debt that doctor's
`check-*` scripts surface but cannot resolve themselves. The split between
*detect* (doctor) and *fix* (wash-vault) keeps the safety net read-only by
default — explicit `--fix` is required for any mutation.

## Rules

Each pass runs three rules. Execution order is **filename → no-frontmatter → id**
because rule 1 (id) is derived from the filename, so any rename in rule 3 must
happen first. The rules are *named* by what they detect (id-mismatch,
no-frontmatter, filename-unsafe-chars), not by execution order — pass them in
any order to `--rules`.

1. **filename-unsafe-chars** (runs first): file basename contains characters
   that break shell quoting, URL encoding, or filesystem portability (`"`,
   `'`, `'`, `…`, leading/trailing whitespace). Fix: `git mv` to sanitized
   variant. **Collision protection**: if two files sanitize to the same
   target, the second is reported as `filename-collision` and left untouched
   — manual resolve required. **Wiki-link updates are out of scope** — run
   `check-local-content` afterwards to detect orphaned references.

2. **no-frontmatter**: file has no YAML frontmatter at all. Fix: prepend a
   minimal frontmatter stub. `date` = today, `type` = auto-detected from the
   top-level folder under `local/` (e.g. `learnings/`→`learning`,
   `references/`→`reference`, `preferences/`→`feedback`,
   `projects/*/`→`project`/`spec`), `tags` = `[<type>]`,
   `id` = `uuid5-gen.sh <vault-rel-path-no-ext>`. **Note**: stub is always
   minimal — author must enrich `tags:` and content afterwards.

3. **id-mismatch** (also fixes missing-id): frontmatter `id:` differs from
   `uuid5-gen.sh <vault-rel-path-no-ext>`, OR `id:` is absent in
   otherwise-valid frontmatter. Fix: replace or insert the canonical UUID5.
   Reason for drift is usually a file rename; the id should track the path.
   Reported as `id-mismatch` (existing wrong value) or `missing-id` (no
   `id:` line in an existing frontmatter block).

The exempt-list mirrors `check-local-content.sh` (machine-generated buckets:
`learnings/extracted/`, `youtube-digest/`, `findings/`, `metrics/`,
`sessions/archive/`, `.trash/`, `quarantine/`, etc.) — wash skips those.

## Args

```
wash-vault [--fix] [--scope PATH ...] [--rules RULE,RULE] [--help]
```

| Flag | Effect |
|---|---|
| `--fix` | Apply repairs. Default is dry-run (preview only, exit 2 if findings). |
| `--scope PATH` | Limit to one or more paths under `local/`. Default: all of `local/`. |
| `--rules R1,R2` | Run only listed rules. Default: all three. Valid: `id-mismatch`, `no-frontmatter`, `filename-unsafe-chars`. |
| `--json` | Structured output for the self-improving-loop framework. Always exit 0; severity travels per finding. |
| `--help` | This. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | No findings, or `--fix` applied successfully. |
| 1 | Error (uuid5-gen drift, missing brain.json, etc.). |
| 2 | Findings present in dry-run mode (commit-blocking; loop awaits `--fix`). |

## Typical flow

```bash
# 1. See what's dirty
wash-vault

# 2. Apply
wash-vault --fix

# 3. Verify with the detector
bash ~/agentBrain/scripts/check-local-content.sh

# 4. Stage + commit
cd ~/.agentBrain/vault && git add -A && git commit -m "..."
```

## Do not use for

- **Content edits**: wash-vault only fixes *structural* drift (id, frontmatter
  presence, filename safety). Semantic content (tag suggestions, dead-link
  resolution, prose normalization) is human work.
- **Bulk frontmatter rewrites**: the stub is minimal by design. Editors are
  expected to enrich `tags:` and the body manually.
- **Wiki-link rewriting**: out of scope; the filename-rename rule may orphan
  internal references — detect via `check-local-content` after a rename pass.

## Safety

- `--fix` is opt-in; dry-run is default.
- Each rule is independent — `--rules id-mismatch` runs only that rule.
- All mutations stay within `local/` (never touches `system/`).
- File renames use `git mv`, preserving history.
- Stubs only added where no frontmatter exists at all — never overwrites
  existing frontmatter.

## Schedule

This skill is **on-demand**. Doctor pre-commit-hook is the canonical detector;
wash-vault is the operator's response when doctor reports deterministic drift.
