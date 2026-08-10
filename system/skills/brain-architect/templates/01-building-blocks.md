## Building Blocks

<!-- The mental model first: one mermaid flowchart of components + data flow.
     Then the table. Trust level ∈ {privileged, delegated, data, ui, external}.
     Every row needs an evidence: path (lowercase `evidence:` with colon,
     pointing at a file that exists — stat-checked). Name what is privileged
     (the blast radius) and what is delegated to third parties. -->

```mermaid
flowchart LR
  %% components + data flow
```

| Component | Where | Role | Trust level | Evidence |
|---|---|---|---|---|
| <name> | `<path>` | <role> | <trust> | evidence: `<path>` |
