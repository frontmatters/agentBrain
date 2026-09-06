import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const home = mkdtempSync(join(tmpdir(), "ab-mcp-home-"));
mkdirSync(join(home, ".cursor"), { recursive: true });           // Cursor "detected"
// Windsurf dir intentionally absent -> not detected.

test("targets() builds per-client config paths under the given home", async () => {
  const { targets } = await import("../register");
  const t = targets(home);
  const cursor = t.find((x) => x.id === "cursor")!;
  assert.equal(cursor.configPath, join(home, ".cursor", "mcp.json"));
  const windsurf = t.find((x) => x.id === "windsurf")!;
  assert.equal(windsurf.configPath, join(home, ".codeium", "windsurf", "mcp_config.json"));
});

test("detected() is true only when the client config dir exists", async () => {
  const { targets, detected } = await import("../register");
  const t = targets(home);
  assert.equal(detected(t.find((x) => x.id === "cursor")!), true);
  assert.equal(detected(t.find((x) => x.id === "windsurf")!), false);
});

test("claude-code target: ~/.claude.json config, detected via ~/.claude dir", async () => {
  const { targets, detected } = await import("../register");
  const t = targets(home);
  const cc = t.find((x) => x.id === "claude-code")!;
  assert.equal(cc.configPath, join(home, ".claude.json"));
  // ~/.claude.json lives directly in $HOME — detection must use detectPath,
  // not dirname(configPath), or every machine would count as "installed".
  assert.equal(detected(cc), false);
  mkdirSync(join(home, ".claude"), { recursive: true });
  assert.equal(detected(cc), true);
});

test("claude-desktop target: OS-aware config path + detected via parent dir", async () => {
  const { targets, detected } = await import("../register");
  const cdHome = mkdtempSync(join(tmpdir(), "ab-mcp-cd-"));
  const t = targets(cdHome);
  const cd = t.find((x) => x.id === "claude-desktop");
  if (process.platform === "darwin") {
    assert.ok(cd, "claude-desktop must be a target on darwin");
    assert.equal(
      cd!.configPath,
      join(cdHome, "Library", "Application Support", "Claude", "claude_desktop_config.json")
    );
    assert.equal(detected(cd!), false);
    mkdirSync(join(cdHome, "Library", "Application Support", "Claude"), { recursive: true });
    assert.equal(detected(cd!), true);
  } else if (process.platform === "linux") {
    assert.ok(cd, "claude-desktop must be a target on linux");
    assert.equal(
      cd!.configPath,
      join(cdHome, ".config", "Claude", "claude_desktop_config.json")
    );
  }
  // win32 deliberately not asserted: depends on APPDATA which may not be set in CI.
});

test("register adds our entry, preserves others; unregister removes only ours", async () => {
  const { register, unregister } = await import("../register");
  const dir = mkdtempSync(join(tmpdir(), "ab-mcp-reg-"));
  const cursor = { id: "cursor", configPath: join(dir, "mcp.json") } as const;
  writeFileSync(cursor.configPath, JSON.stringify({ mcpServers: { other: { command: "x", args: [] } } }));
  await register(cursor as any, "/brain/alias");
  let cfg = JSON.parse(readFileSync(cursor.configPath, "utf8"));
  assert.deepEqual(cfg.mcpServers.agentbrain, { command: "bun", args: ["/brain/alias/system/addons/agentbrain-mcp/src/server.ts"] });
  assert.ok(cfg.mcpServers.other, "must preserve pre-existing servers");
  await register(cursor as any, "/brain/alias"); // idempotent
  cfg = JSON.parse(readFileSync(cursor.configPath, "utf8"));
  assert.equal(Object.keys(cfg.mcpServers).length, 2);
  await unregister(cursor as any);
  cfg = JSON.parse(readFileSync(cursor.configPath, "utf8"));
  assert.equal("agentbrain" in cfg.mcpServers, false);
  assert.ok(cfg.mcpServers.other, "unregister must leave other servers intact");
});

test("register creates config + parent dir when absent", async () => {
  const { register } = await import("../register");
  const fresh = { id: "cursor", configPath: join(home, "fresh", "mcp.json") };
  await register(fresh as any, "/b");
  assert.ok(existsSync(fresh.configPath));
});

test("register refuses to overwrite a malformed config (no data loss)", async () => {
  const { register } = await import("../register");
  const dir = mkdtempSync(join(tmpdir(), "ab-mcp-reg-"));
  const cursor = { id: "cursor", configPath: join(dir, "mcp.json") } as const;
  writeFileSync(cursor.configPath, "{ not valid json !!");
  await assert.rejects(() => register(cursor as any, "/b"), /malformed JSON/);
  assert.equal(readFileSync(cursor.configPath, "utf8"), "{ not valid json !!"); // untouched
});

test("unregister reports whether it removed anything", async () => {
  const { register, unregister } = await import("../register");
  const dir = mkdtempSync(join(tmpdir(), "ab-mcp-reg-"));
  const cursor = { id: "cursor", configPath: join(dir, "mcp.json") } as const;
  writeFileSync(cursor.configPath, JSON.stringify({ mcpServers: {} }));
  assert.equal(await unregister(cursor as any), false);  // nothing of ours present
  await register(cursor as any, "/b");
  assert.equal(await unregister(cursor as any), true);   // removed our entry
});

test("pi/gemini/kiro targets: verified config paths + install-marker detection", async () => {
  const { targets, detected } = await import("../register");
  const h = mkdtempSync(join(tmpdir(), "ab-mcp-more-"));
  const t = targets(h);

  const pi = t.find((x) => x.id === "pi")!;
  assert.equal(pi.configPath, join(h, ".pi", "agent", "mcp.json"));
  assert.equal(detected(pi), false);
  mkdirSync(join(h, ".pi"), { recursive: true });
  assert.equal(detected(pi), true); // detected via ~/.pi marker, before agent/mcp.json exists

  const gem = t.find((x) => x.id === "gemini")!;
  assert.equal(gem.configPath, join(h, ".gemini", "settings.json"));
  assert.equal(detected(gem), false);
  mkdirSync(join(h, ".gemini"), { recursive: true });
  assert.equal(detected(gem), true);

  const kiro = t.find((x) => x.id === "kiro")!;
  assert.equal(kiro.configPath, join(h, ".kiro", "settings", "mcp.json"));
  assert.equal(detected(kiro), false);
  mkdirSync(join(h, ".kiro"), { recursive: true });
  assert.equal(detected(kiro), true); // detected via ~/.kiro marker, before settings/ exists
});

test("register() preserves unrelated keys in a shared settings.json (gemini)", async () => {
  const { targets, register } = await import("../register");
  const h = mkdtempSync(join(tmpdir(), "ab-mcp-gem-"));
  mkdirSync(join(h, ".gemini"), { recursive: true });
  const p = join(h, ".gemini", "settings.json");
  writeFileSync(p, JSON.stringify({ theme: "Dark", selectedAuthType: "oauth" }));
  const gem = targets(h).find((x) => x.id === "gemini")!;
  await register(gem, join(h, "agentBrain"));
  const cfg = JSON.parse(readFileSync(p, "utf8"));
  assert.equal(cfg.theme, "Dark");
  assert.equal(cfg.selectedAuthType, "oauth");
  const keys = Object.keys(cfg.mcpServers ?? {});
  assert.equal(keys.length, 1);
  assert.ok(cfg.mcpServers[keys[0]].command, "registered server entry has a command");
});
