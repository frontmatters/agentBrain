---
date: 2026-05-22
type: system
tags: [addon, mcp, server]
id: a9225409-0bce-5679-97cb-905e5d96e24e
---

# agentBrain MCP server

Direct-file MCP server exposing the brain to Cursor and Windsurf — MCP-capable
agents that lack a global skills directory. It lets them natively search/read the
brain and save learnings + project notes into `local/`.

## Install

```bash
bash system/addons/agentbrain-mcp/install.sh        # bun install + register into detected clients
```

Registers **only** into clients whose config dir already exists (i.e. the client
is installed):

| Client | Config file written |
| --- | --- |
| Claude Code (CLI) | `~/.claude.json` |
| Cursor | `~/.cursor/mcp.json` |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` |
| Claude Desktop (GUI app) | macOS: `~/Library/Application Support/Claude/claude_desktop_config.json` · Linux: `~/.config/Claude/claude_desktop_config.json` · Windows: `%APPDATA%/Claude/claude_desktop_config.json` |

The registration is idempotent (re-running won't duplicate the entry) and merges
into any existing MCP config rather than clobbering it.

## Usage

```bash
bun system/addons/agentbrain-mcp/src/server.ts       # run the server directly (stdio)
```

Tools: `brain_search(query,limit?)`, `brain_read(path)`, `brain_recent(n?)`,
`brain_rules()`, `brain_save_learning(title,body,tags?)`,
`brain_project_update(name,section?,body)`.

Brain root resolves via `$AGENTBRAIN_DIR`, else the `~/agentBrain` alias (so
`brain use dev|live` flips it).

## Uninstall

```bash
bash system/addons/agentbrain-mcp/install.sh --uninstall
```

Removes only this server's entry from each client config; other MCP servers in
the same file are left untouched. Idempotent.

## Troubleshooting

**The client doesn't see the tools after install.** MCP clients read their config
once at startup. **Fully restart Cursor/Windsurf/Claude Desktop** (quit the app,
not just reload the window) after install or uninstall so it re-reads `mcp.json`.
Claude Code picks it up on the next `claude` invocation. To confirm the entry
landed: `grep -A3 agentbrain ~/.cursor/mcp.json` (or any of the paths above).

**Install says "malformed JSON — refusing to overwrite".** The client's existing
`mcp.json` / `mcp_config.json` is not valid JSON. The installer deliberately
refuses to overwrite it (it may hold your other MCP servers). Fix the JSON (a
trailing comma or stray character is the usual cause) or delete the file, then
re-run `install.sh`.

**"Client not detected" — nothing registered.** Registration only targets clients
whose config directory already exists. If you just installed Cursor/Windsurf,
launch it once (so it creates `~/.cursor/` or `~/.codeium/windsurf/`), then re-run
`install.sh`.

**Server starts but tools error with "brain not found".** The server resolves the
brain via `$AGENTBRAIN_DIR`, falling back to the `~/agentBrain` symlink. If you run
the client from an environment where neither resolves (e.g. a sandbox without the
alias), set `AGENTBRAIN_DIR` explicitly in the client's MCP server `env` block.

**`bun: command not found` at launch.** The registered command runs `bun`. Ensure
`bun` is on the PATH the client launches with; some GUI clients don't inherit your
shell PATH — use an absolute `bun` path in the config or add it to the client's
`env`.

## Other MCP clients (VS Code, ChatGPT, ...)

The server is a standard stdio MCP server — any MCP-capable client can use it;
`register.ts` only automates Claude Code, Cursor and Windsurf. Manual wiring:

- **VS Code (Copilot)**: add to the user-level `mcp.json` (Command Palette →
  "MCP: Open User Configuration"). Note VS Code uses a `servers` key, not
  `mcpServers`:
  `{ "servers": { "agentbrain": { "type": "stdio", "command": "bun", "args": ["<home>/agentBrain/system/addons/agentbrain-mcp/src/server.ts"] } } }`
- **ChatGPT (desktop)**: ChatGPT connectors expect a *remote* MCP server
  (HTTPS/SSE); this server is stdio-only and local-first. Exposing the brain
  over a network endpoint changes the privacy story (`local` → networked) —
  intentionally not supported. If you ever need it, put a separate authenticated
  gateway in front; do not tunnel this server directly.

## Privacy

`privacy: local`: this add-on only reads/writes brain files — nothing is sent to
any external service. Writes are confined to `local/` with kebab filenames, full
frontmatter and a UUID5 id.
