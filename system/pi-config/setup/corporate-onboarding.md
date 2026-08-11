---
date: 2026-05-19
type: system
tags: [pi-agent, corporate, onboarding, setup]
id: e9826d18-9b5d-5310-9683-7778418b0c80
---

# Corporate Pi + agentBrain Onboarding

Use this checklist when onboarding Pi + agentBrain in a corporate environment.
Keep this file public-safe: it defines the process only. Real company names, domains,
policies, endpoints, and credential details belong in `local/`.

## Goals

A corporate-ready setup should answer these before agents start writing code:

- Which data may leave the machine/network?
- Which AI providers/models are approved?
- How are credentials retrieved without pasting secrets into chat?
- Which repositories/projects are in scope?
- Which logs or session artifacts may be stored?
- Which update path is allowed for Pi, packages, and skills?

## Preflight roles

| Role            | Decision needed                                             |
| --------------- | ----------------------------------------------------------- |
| Security / IAM  | Credential storage, SSO, device trust, secret broker        |
| Legal / Privacy | Data classifications, retention, telemetry restrictions     |
| Platform / IT   | Proxy, CA certificates, package registries, managed devices |
| Engineering     | Approved repos, languages, build tools, validation commands |
| Team lead       | Autonomy level, review expectations, escalation path        |

## Corporate setup phases

### 1. Policy capture

Create private local notes from the local starter templates:

```text
local/security/corporate-onboarding.md
local/integrations/corporate-agent-policy.md
```

Record only references to policies and helpers. Do not paste secrets.

### 2. Network and package access

Document private details in `local/integrations/corporate-agent-policy.md`:

- Corporate proxy requirements (`HTTPS_PROXY`, certificate trust, VPN state).
- Approved package managers and registries.
- Whether Pi auto-update is allowed or pinned.
- Whether postinstall compatibility patches are allowed.

### 3. Credential flow

Before asking a user for a token, agents must check:

```text
local/integrations/
local/security/
```

Preferred corporate patterns:

- macOS Keychain, Windows Credential Manager, Linux Secret Service, or a company-approved secret helper.
- Device-code OAuth where approved by policy.
- Short-lived tokens from a documented helper command.
- No token values in prompts, notes, logs, screenshots, or commits.

### 4. Provider/model policy

Capture allowed providers privately:

- Approved providers/models.
- Disallowed providers/models.
- BYOK or company gateway requirements.
- Whether training/data retention is disabled by contract/policy.
- Which project classifications can use which models.

### 5. Repository and data boundaries

For each repo or project:

- Scope: read-only, edit allowed, commit allowed, push allowed.
- Data class: public, internal, confidential, restricted.
- Files excluded from agent reads.
- Required validation commands before commits.
- Required human review before push/deploy.

### 6. Onboarding interview

Run:

```text
/onboard corporate
```

The agent should ask only for policy choices and references, not secrets.

### 7. Validation gate

Run:

```bash
bash scripts/doctor.sh
bash scripts/privacy-scan.sh
PI_AUTO_UPDATE=0 pi --offline --list-models
```

If Pi is configured for corporate providers, also validate one minimal prompt per approved provider.

### 8. Handoff

A complete corporate onboarding handoff includes:

- Private local policy notes filled in.
- Credential helper documented and tested.
- Approved provider/model list documented.
- Update/patch policy documented.
- Project scope and validation commands documented.
- Rollback/recovery instructions documented.

## Red flags

Stop and escalate when:

- A tool asks for raw tokens in chat.
- A provider is not in the approved provider list.
- A repo contains restricted data and no model policy exists.
- Proxy/certificate interception changes auth behavior.
- A generated note contains company secrets, private endpoints, or customer data in public paths.

## Related

- [[Rules]]
- [[README]]
