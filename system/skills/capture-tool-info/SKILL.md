---
name: capture-tool-info
description: Capture useful tool, service, auth, Azure, company-library, or workflow information into the correct private agentBrain note. Use whenever operational tool info appears during work.
argument-hint: Optional tool/topic to capture (e.g. "gitea helper path" or "azure devops")
user-invocable: true
resources:
  - system/rules.md
  - templates/local-starters/
---

# Capture Tool Info

Capture operational information without turning agentBrain into a duplicate note dump.

## Trigger

Use this when you learn or see:

- Tool/service URLs, local ports, dashboards, helper scripts
- Credential locations, keychain service names, auth workflows (never token values)
- Git hosting/provider details (GitHub, GitLab, Azure Repos, Gitea, self-hosted)
- Physical machines/hosts/devices (servers, SBCs like a Raspberry Pi, NAS, laptops, phones) — their role, OS, IP/Tailscale address, or SSH login user
- Azure DevOps/cloud usage, CLI conventions, org/project references
- Work/company profile info, internal libraries, package registries, design systems
- Project-specific commands, repo URLs, deploy steps
- Repeatable setup fixes, troubleshooting, or reusable patterns

## Routing

| Information                        | Destination                                                                            |
| ---------------------------------- | -------------------------------------------------------------------------------------- |
| Physical machine/host/device       | `local/devices/[name].md` (see device frontmatter note below)                          |
| Integration endpoint/helper/config | `local/integrations/[tool].md`                                                         |
| Credential storage/auth workflow   | `local/security/[tool].md` or relevant integration note                                |
| Git provider preferences           | `local/preferences/personal/git-config.md`                                             |
| Azure/cloud preferences            | `local/preferences/personal/cloud-azure.md`                                            |
| Organization/work context          | `local/preferences/organization/context.md` or `local/preferences/team/context.md`     |
| Organization/internal libraries    | `local/preferences/organization/libraries.md` or `local/preferences/team/libraries.md` |
| Project-specific tool info         | `local/projects/[project]/`                                                            |
| Troubleshooting fix                | `local/learnings/troubleshooting.md`                                                   |
| Reusable pattern                   | `local/learnings/patterns.md`                                                          |
| Setup event/history                | `local/setup-history/[topic].md`                                                       |
| Future idea                        | `local/backlog/[topic].md`                                                             |

## Write flow

1. **Classify** the information using the routing table.
2. **Locate** likely target file(s). Prefer existing notes.
3. **Read before writing.** Search for the same tool, URL, helper, command, provider, or concept.
4. **Verify freshness if already present:**
   - Path exists? `test -e ...`
   - Command exists? `command -v ...`
   - Service reachable? use a safe non-secret health check
   - Version/current behavior confirmed?
5. **Decide:**
   - Current + complete -> skip write; optionally update `last-confirmed`
   - Current + incomplete -> enrich existing section
   - Stale -> update current value and move old value to `History`/`Deprecated`
   - Uncertain -> mark `needs-verification`, do not delete old info
6. **Create only when needed.** New notes must use UUID5 and required frontmatter.
7. **Summarize** what changed and where.

## Required frontmatter for new operational notes

```yaml
---
date: YYYY-MM-DD
type: integration|security|preference|setup-history|device
tags: [tool, provider, domain]
status: active|deprecated|missing|needs-verification|experimental
last-confirmed: YYYY-MM-DD
confidence: high|medium|low
id: <UUID5>
---
```

Generate IDs with:

```bash
scripts/uuid5-gen.sh "local/integrations/tool-name"
```

### Device notes are different (`local/devices/`)

A physical machine/host is a **device**, not an integration — `local/devices/`
already exists. Always check it before writing a host anywhere else, and match
the existing device frontmatter shape instead of the generic operational one:

```yaml
---
date: YYYY-MM-DD
type: device
tags: [device, <class>]      # e.g. sbc, server, nas, laptop, mobile
status: active|idle|retired
last-confirmed: YYYY-MM-DD
confidence: high|medium|low
priority: low|medium|high
id: <UUID5>

# intent (manual — stable)
role: "..."
model: "..."

# state (auto-syncable — volatile)
hostname: ...
tailscale_ip: ...
ssh_user: ...
os: "..."
online: true
last_synced: YYYY-MM-DD
---
```

## Required sections for operational notes

```markdown
# Tool Name

## Current

- Key facts, URLs, paths, commands, preferences.

## Verification

- Last checked: YYYY-MM-DD
- Method: command/path/API check used
- Result: OK / needs verification

## History

- Deprecated or old values with dates.

## Related

- `local/preferences/personal/git-config.md`
- `local/security/credential-notes.md`
```

## Privacy rules

- Never save token/password/private-key values.
- Before asking for credentials, check `local/integrations/` and `local/security/`.
- Ask before saving company names, internal repo URLs, production infrastructure, customer/project names, or proprietary library details.
- Approved corporate/work details still go only to `local/` or configured `local/secure/`, never public docs.
