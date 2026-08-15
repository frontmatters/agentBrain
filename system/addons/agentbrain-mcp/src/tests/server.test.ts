import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = mkdtempSync(join(tmpdir(), "ab-mcp-server-"));
mkdirSync(join(root, "local", "learnings"), { recursive: true });
writeFileSync(join(root, "local", "learnings", "x.md"), "---\ntitle: X\n---\n\nfindme content\n");

const serverPath = join(import.meta.dir, "..", "server.ts");

// Speak just enough MCP over stdio: initialize -> tools/list, collect the responses.
function talk(messages: object[], timeoutMs = 8000): Promise<string> {
  return new Promise((resolve, reject) => {
    const p = spawn("bun", [serverPath], { env: { ...process.env, AGENTBRAIN_DIR: root } });
    let out = "";
    const timer = setTimeout(() => { p.kill(); resolve(out); }, timeoutMs);
    p.stdout.on("data", (d) => { out += d.toString(); });
    p.on("error", reject);
    p.on("close", () => { clearTimeout(timer); resolve(out); });
    for (const m of messages) p.stdin.write(JSON.stringify(m) + "\n");
  });
}

test("server lists the brain_* tools after initialize", { timeout: 15000 }, async () => {
  const out = await talk([
    { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "test", version: "0" } } },
    { jsonrpc: "2.0", method: "notifications/initialized" },
    { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} },
  ]);
  assert.match(out, /brain_search/);
  assert.match(out, /brain_save_learning/);
  assert.match(out, /brain_findings_list/);
});
