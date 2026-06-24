---
date: 2026-03-17
type: decisions
tags: [project, example, decisions]
project: example
id: e37efd37-f064-5546-9b9a-064914f7e6a7
---

# Example Project -- Decisions

## ADR-001: Use Express over Fastify (2026-03-16)

- **Status**: accepted
- **Context**: Needed a Node.js HTTP framework. Team has Express experience.
- **Decision**: Use Express for the REST API.
- **Consequences**: Slower than Fastify, but faster onboarding and more middleware available.

## ADR-002: JWT for authentication (2026-03-17)

- **Status**: accepted
- **Context**: Need stateless auth for horizontal scaling.
- **Decision**: Use JWT tokens with short expiry + refresh tokens.
- **Consequences**: No server-side session storage needed. Must handle token rotation.
