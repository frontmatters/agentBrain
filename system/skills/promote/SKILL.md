---
name: promote
description: >-
  Move artifacts between mirror subfolders in agentBrain — local/X/ ↔ system/X/
  for the 5 canonical mirror folders (addons, agent-config, integrations,
  pi-config, skills). Use when graduating a private/experimental artifact to
  the canonical system framework, or when demoting one back to private
  experimentation. Triggers: "promote this", "demote", "move to system",
  "graduate skill", "make this canonical".
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

## Status

Spec complete (v1.1.0); implementation v1.1.1 in place, all 7 smoke tests
from SPEC §9 pass. Three minor refinements from peer-review remain open and
are tracked in `local/projects/promote-demote-skill/index.md` backlog.

## Related

- [[forward:promote-demote-skill]] — project document with backlog and resume instructions
- [[forward:bash-multi-verb-script-via-arg0-dispatch]] — `bin/demote` is a symlink to `bin/promote`
- [[forward:bash-prefix-strip-and-prepend-path-swap]] — path computation pattern used here
- [[forward:central-trash-dir-instead-of-auto-rm]] — `--force` semantics
- [[forward:agentbrain-mirror-split-volumes]] — why LOCAL_ROOT and SYSTEM_ROOT are resolved independently
