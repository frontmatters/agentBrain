---
date: 2026-06-06
type: system
tags: [skill, wash-vault, vault, content-debt, agentbrain]
id: 158b943d-c82e-576c-9137-b11d5cf989cc
---

# wash-vault

> Deterministic content-debt repair for the agentBrain vault.

`wash-vault` complements doctor's read-only `check-*` scripts with an opt-in mutation layer. Doctor flags issues; `wash-vault --fix` repairs the deterministic subset.

## Quick start

```bash
# See what's dirty (default = dry-run, exit 2 if findings)
bash ~/agentBrain/system/skills/wash-vault/bin/wash-vault

# Apply the deterministic fixes
bash ~/agentBrain/system/skills/wash-vault/bin/wash-vault --fix

# Scope to a sub-tree
bash ~/agentBrain/system/skills/wash-vault/bin/wash-vault --scope ~/agentBrain/local/learnings

# Run only one rule
bash ~/agentBrain/system/skills/wash-vault/bin/wash-vault --rules id-mismatch

# Structured output for the self-improving-loop
bash ~/agentBrain/system/skills/wash-vault/bin/wash-vault --json
```

## What it fixes

| Rule | Detects | Repairs (with `--fix`) |
|---|---|---|
| `filename-unsafe-chars` | `" ' ' '  … * ? :` in note basenames | `git mv` to sanitized variant; collision-protected vs disk *and* intra-run |
| `no-frontmatter` | Files missing YAML frontmatter entirely | Prepends minimal stub (`date`, `type` from folder, `tags: [type]`, canonical `id`) |
| `id-mismatch` / `missing-id` | `id:` field absent or != `uuid5-gen.sh <path>` | Replaces/inserts the canonical UUID5; tolerates Claude auto-memory `metadata.id` |

## What it does NOT fix

By design, wash-vault stays clear of any change that requires human judgment:

- Tag suggestions
- Body normalization
- Dead wiki-link resolution
- Content rewrites
- Forward-ref decisions

Those belong to the human author (or a future content-aware tool, not this one).

## Full docs

See `SKILL.md` for the complete rule semantics, exempt-list rationale, exit codes, safety guarantees, and the deferred-finding rationales from the peer-review iterations.

## Related

- The canonical note schema this enforces: `local/references/agentbrain-note-schema.md`
- Diagnostic interpretation of wash findings: `local/learnings/wash-output-as-upstream-diagnostic.md`
