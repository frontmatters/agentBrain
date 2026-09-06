## Constraints

<!-- One mermaid diagram of egress/zones, then the six lenses.
     Every lens gets facts WITH evidence:, or an explicit "⚠ Open: …" line.
     An empty lens is forbidden; "⚠ Open" is a valid and honest answer. -->

```mermaid
flowchart TD
  %% egress / zone diagram: what talks to what, across which boundary
```

### Egress
<!-- outbound connections: destination, payload class, source file -->
evidence: `<path-of-egress-source-file>`

### Data & Storage
<!-- where state lives, what is relocatable/encrypted -->

### Secrets
<!-- where credentials live, how injected -->

### Identity & Access
<!-- authN/authZ, roles, enforcement point (server-side or UI-only?) -->

### Compliance
<!-- applicable regimes (GDPR/DORA/…) and the evidence each expects -->

### Operations
<!-- logging, monitoring, health, incident path -->
