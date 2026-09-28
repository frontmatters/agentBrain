---
date: 2026-06-04
type: system
tags: [skill, park]
id: 13c7dbbb-1ed5-5f11-98aa-9383266be574
---

# park

Save side of the see -> load -> save session loop.

## Purpose

Captures in-progress work to agentBrain so a later session (any agent, any model) can resume without rediscovery: updates the project status via project-update, persists per-insight learnings via save-learning, and prints an unpark-prompt for the next session.

## Usage

```
/park
/park <project-slug>
```

## Related

- [[unpark]] — load side of the loop in a fresh session
- [[list-parks]] — discover what is currently parked
