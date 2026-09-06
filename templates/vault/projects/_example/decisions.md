---
date: {{date}}
type: decisions
tags: [project, example, decisions]
project: example
id: {{uuid5}}
---

# Example Project -- Decisions

## ADR-001: Use Express over Fastify (2026-03-16)

- **Status**: accepted
- **Context**: Needed a Node.js HTTP framework. Team has Express experience.
- **Decision**: Use Express for the REST API.
- **Alternatives**: Fastify — faster benchmarks, but smaller middleware ecosystem and no team experience; not worth the onboarding cost here.
- **Consequences**: Slower than Fastify, but faster onboarding and more middleware available.

## ADR-002: JWT for authentication (2026-03-17)

- **Status**: accepted
- **Context**: Need stateless auth for horizontal scaling.
- **Decision**: Use JWT tokens with short expiry + refresh tokens.
- **Alternatives**: Server-side sessions in Redis — simpler revocation, but a stateful dependency that undercuts the horizontal-scaling goal; opaque tokens — need a central introspection call per request, adding latency and a single point of failure.
- **Consequences**: No server-side session storage needed. Must handle token rotation.
