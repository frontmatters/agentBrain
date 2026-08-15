---
name: promote
description: >-
  Move artifacts between mirror subfolders in agentBrain — local/X/ ↔ system/X/
  for the 5 canonical mirror folders (addons, agent-config, integrations,
  pi-config, skills). Use when graduating a private/experimental artifact to
  the canonical system framework, or when demoting one back to private
  experimentation. Triggers: "promote this", "demote", "move to system",
  "graduate skill", "make this canonical".
related: [import-external-skill]
---

# promote / demote

Path-swap mirror-folder skill. See `SPEC.md` (v1.1.0) for the full design.

## Location

```
~/agentBrain/system/skills/promote/
```

## Quickstart

```bash
# Promote a tested skill from local to system
bash bin/promote $BRAIN_DIR/local/skills/yt-digest

# Demote a system integration back to private
bash bin/demote $BRAIN_DIR/system/integrations/lightpanda.md
```

## After every promote/demote: ksc aftercare (MANDATORY)

`bin/promote` is a pure path-swap. The agent executing this skill MUST
complete the ksc aftercare (see `system/versioning.md`) in the same session,
for skills AND addons alike:

1. **Fix internal paths** in the moved artifact (`local/...` ↔ `system/...`
   references inside SKILL.md, manifests, scripts).
2. **Update the index**: `system/skills.md` (skills) or the addon registry
   (addons); on demote, remove the entry.
3. **CHANGELOG entry** under `## [Unreleased]` in `CHANGELOG.md` — no
   version bump (releases are assembled, not streamed).
4. **Commit both sides** with conventional messages: the public repo
   (addition/removal) and the private vault (counterpart).
5. **Re-point ALL agent symlinks** — Claude (`~/.claude/skills/`), Pi
   (`~/.pi/agent/skills/`), Copilot (`~/.copilot/skills/`), and any other
   detected agent — and run the artifact's own tests from the new location.
6. **Add the public-repo hygiene files** the system side requires: a
   `README.md` in the artifact root (and in subdirs that hold content, like
   `templates/`) — `check-readmes.sh` enforces this.
7. **Run `doctor --summary`** to prove the promote is complete;
   `check-skill-links` and `check-readmes` catch exactly the steps people
   skip.

Presenting a promote as done without these steps is incomplete work.

## Status

Spec complete (v1.1.0); implementation v1.1.1 in place, all 7 smoke tests
from SPEC §9 pass. Three minor refinements from peer-review remain open and
are tracked in `local/projects/promote-demote-skill/index.md` backlog, plus:
automate the ksc aftercare in `bin/promote` itself (checklist output or
`--ksc` flow) so the guarantee stops depending on agent discipline.

## Related

- [[forward:promote-demote-skill]] — project document with backlog and resume instructions
- [[forward:bash-multi-verb-script-via-arg0-dispatch]] — `bin/demote` is a symlink to `bin/promote`
- [[forward:bash-prefix-strip-and-prepend-path-swap]] — path computation pattern used here
- [[forward:central-trash-dir-instead-of-auto-rm]] — `--force` semantics
- [[forward:agentbrain-mirror-split-volumes]] — why LOCAL_ROOT and SYSTEM_ROOT are resolved independently
