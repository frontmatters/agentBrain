import { readFile, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";

const SERVER_NAME = "agentbrain";

export interface ClientTarget { id: string; configPath: string; detectPath?: string; }

// Claude Desktop's config path differs by OS (the GUI app, not the Claude Code
// CLI). On Windows we need APPDATA; if it's missing, treat the client as
// unsupported rather than guessing.
function claudeDesktopConfigPath(home: string): string | null {
  switch (process.platform) {
    case "darwin":
      return join(home, "Library", "Application Support", "Claude", "claude_desktop_config.json");
    case "linux":
      return join(home, ".config", "Claude", "claude_desktop_config.json");
    case "win32":
      return process.env.APPDATA
        ? join(process.env.APPDATA, "Claude", "claude_desktop_config.json")
        : null;
    default:
      return null;
  }
}

// MCP clients whose config path is verified (Cursor/Windsurf docs May 2026;
// Claude Code user-scope mcpServers in ~/.claude.json, detected via ~/.claude/;
// Claude Desktop GUI per `claude_desktop_config.json` docs).
export function targets(home = homedir()): ClientTarget[] {
  const ts: ClientTarget[] = [
    { id: "claude-code", configPath: join(home, ".claude.json"), detectPath: join(home, ".claude") },
    { id: "cursor", configPath: join(home, ".cursor", "mcp.json") },
    { id: "windsurf", configPath: join(home, ".codeium", "windsurf", "mcp_config.json") },
  ];
  const cdPath = claudeDesktopConfigPath(home);
  if (cdPath) ts.push({ id: "claude-desktop", configPath: cdPath });
  return ts;
}

// "Detected" = the client's install marker exists: detectPath when set
// (configPath may live directly in $HOME), else the config dir.
export function detected(t: ClientTarget): boolean {
  return existsSync(t.detectPath ?? dirname(t.configPath));
}

function serverEntry(brainAlias: string) {
  return { command: "bun", args: [join(brainAlias, "system/addons/agentbrain-mcp/src/server.ts")] };
}

async function loadJson(p: string): Promise<any> {
  if (!existsSync(p)) return {};
  const raw = await readFile(p, "utf8");
  try { return JSON.parse(raw); } catch {
    throw new Error(`${p}: malformed JSON — refusing to overwrite (it may hold other MCP servers). Fix or delete the file, then retry.`);
  }
}

// Idempotent: set mcpServers.agentbrain, preserving any other servers.
export async function register(t: ClientTarget, brainAlias: string): Promise<void> {
  const cfg = await loadJson(t.configPath);
  cfg.mcpServers ??= {};
  cfg.mcpServers[SERVER_NAME] = serverEntry(brainAlias);
  await mkdir(dirname(t.configPath), { recursive: true });
  await writeFile(t.configPath, `${JSON.stringify(cfg, null, 2)}\n`);
}

// Remove only our entry; leave the rest untouched. Returns true iff it removed something.
export async function unregister(t: ClientTarget): Promise<boolean> {
  if (!existsSync(t.configPath)) return false;
  const cfg = await loadJson(t.configPath);
  if (cfg.mcpServers && SERVER_NAME in cfg.mcpServers) {
    delete cfg.mcpServers[SERVER_NAME];
    await writeFile(t.configPath, `${JSON.stringify(cfg, null, 2)}\n`);
    return true;
  }
  return false;
}

if (import.meta.main) {
  const brainAlias = process.env.BRAIN_ALIAS ?? join(homedir(), "agentBrain");
  const uninstall = process.argv.includes("--uninstall");
  let hadError = false;
  for (const t of targets()) {
    if (!detected(t)) { console.log(`skip ${t.id}: not detected`); continue; }
    try {
      if (uninstall) {
        const removed = await unregister(t);
        console.log(removed ? `unregistered ${t.id} (${t.configPath})` : `nothing to unregister for ${t.id}`);
      } else {
        await register(t, brainAlias);
        console.log(`registered ${t.id} -> ${t.configPath}`);
      }
    } catch (e) {
      hadError = true;
      console.error(`error processing ${t.id}: ${(e as Error).message}`);
    }
  }
  if (hadError) process.exit(1);
}
