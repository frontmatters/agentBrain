---
id: agentbrain-mcp
name: agentBrain MCP server
version: 0.1.1
install: bash system/addons/agentbrain-mcp/install.sh
command: bun
privacy: local
install_method: self
test: bun test
support:
  claude: full
  claude-desktop: full
  cursor: full
  windsurf: full
outputs:
  - local/learnings/*.md
  - local/projects/*/*.md
---

# agentBrain MCP server (add-on)

A direct-file MCP server over this brain. Lets MCP-capable agents that lack a global
skills directory — Cursor, Windsurf — natively search/read the brain and save learnings
and project notes into `local/`.

- **Run** (stdio): `bun system/addons/agentbrain-mcp/src/server.ts`
- **Register** into detected clients: `bash system/addons/agentbrain-mcp/install.sh` (`--uninstall` reverses).
- **Tools**: `brain_search`, `brain_read`, `brain_recent`, `brain_rules`,
  `brain_save_learning`, `brain_project_update`.
- **Brain root**: `AGENTBRAIN_DIR` env, else the `~/agentBrain` alias (so `brain use` flips it).

Privacy `local`: this add-on only reads/writes brain files — nothing is sent to any external
service. Writes are confined to `local/` with kebab filenames, full frontmatter and a UUID5 id.
