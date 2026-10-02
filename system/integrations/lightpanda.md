---
date: 2026-05-18
type: system
tags: [scripts, lightpanda]
id: 84f514b3-b0be-53b2-8ae8-a06be5b479a0
---

# Lightpanda

Lightpanda is a small headless browser. agentBrain installs it for Pi so an agent
can search the web, open a page, extract content and fill forms.

## Install

```bash
bash scripts/tools/install-lightpanda.sh
```

The installer checks Node.js 20+ and Pi, installs the Lightpanda browser and its
npm packages (core, MCP server, Pi extension), registers the `lightpanda` skill and
verifies the result. Run it again to reinstall or update; it detects an existing
install and asks first.

## Use

```text
/lightpanda search "query"
/lightpanda browse https://example.com
/lightpanda extract ".selector"
/lightpanda form '{"email":"user@example.com"}'
```

The full command reference is in `system/skills/lightpanda/SKILL.md`.
