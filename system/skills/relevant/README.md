---
date: 2026-06-14
type: skill
tags: [skill, relevance, git, sessions, cleanup]
status: active
id: 9a674ba1-93f4-532e-bb25-57c89fedaa5a
---

# /relevant

Agent-facing surface for the `still-needed` addon. Answers "is this still
needed?" for open work across parallel sessions, and reads the verdicts back in
plain language with the exact discard command per item.

## Use

```
/relevant            # git + agentBrain
/relevant git        # only git
/relevant brain      # only parked projects + backlog
/relevant <repo>     # one repo path
```

Triggers on "is this still needed?", "staat er nog iets open?", "did I already
do this in another session?", and before acting on uncommitted/unpushed work.

See `SKILL.md` for the step-by-step the agent follows.
