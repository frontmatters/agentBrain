# Onboarding Bak A · Sub-plan 4 — MCP provisioning coverage (G15)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the agentBrain MCP server registration to the agents it currently misses — **Pi, Gemini, Kiro** — so enabling `agentbrain-mcp` actually wires `brain_search` into those agents instead of silently skipping them (G15).

**Architecture:** The addon already registers into detected clients via `src/register.ts` `targets()` (claude-code, cursor, windsurf, claude-desktop) and writes `cfg.mcpServers.<server>` idempotently, preserving other keys. Pi (`~/.pi/agent/mcp.json`), Gemini (`~/.gemini/settings.json`), and Kiro (`~/.kiro/settings/mcp.json`) all use the **same `mcpServers` config shape** (verified on a real machine), so this is purely additive: three new `ClientTarget`s + tests + a `support:` matrix update. No change to the register/unregister write logic.

**Tech Stack:** TypeScript (`bun`), the addon's existing `node:test`/`bun test` suite (`src/tests/register.test.ts`), the addon `manifest.md`.

**Scope note:** GitHub Copilot CLI is intentionally NOT added — its MCP config path/shape could not be verified. The **fail-loud "enabled-but-not-registered" doctor check** (the other half of G15) is deferred to a follow-on (Sub-plan 4b); this plan delivers the coverage fix.

---

## File structure

- **Modify** `system/addons/agentbrain-mcp/src/register.ts` — add pi/gemini/kiro targets.
- **Modify** `system/addons/agentbrain-mcp/src/tests/register.test.ts` — cover the new targets + key-preservation.
- **Modify** `system/addons/agentbrain-mcp/manifest.md` — add pi/gemini/kiro to `support:`.

---

### Task 1: Add pi/gemini/kiro registration targets (TDD)

**Files:**
- Modify: `system/addons/agentbrain-mcp/src/register.ts` (the `targets()` function, lines 31–41)
- Modify: `system/addons/agentbrain-mcp/src/tests/register.test.ts`

- [ ] **Step 1: Write the failing tests**

Append to `system/addons/agentbrain-mcp/src/tests/register.test.ts`:

```ts
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd system/addons/agentbrain-mcp && bun test src/tests/register.test.ts`
Expected: FAIL — the new tests throw on `t.find((x) => x.id === "pi")!` being `undefined` (pi/gemini/kiro are not targets yet).

- [ ] **Step 3: Add the three targets**

In `system/addons/agentbrain-mcp/src/register.ts`, replace the `targets()` array block:

```ts
  const ts: ClientTarget[] = [
    { id: "claude-code", configPath: join(home, ".claude.json"), detectPath: join(home, ".claude") },
    { id: "cursor", configPath: join(home, ".cursor", "mcp.json") },
    { id: "windsurf", configPath: join(home, ".codeium", "windsurf", "mcp_config.json") },
  ];
```

with:

```ts
  const ts: ClientTarget[] = [
    { id: "claude-code", configPath: join(home, ".claude.json"), detectPath: join(home, ".claude") },
    { id: "cursor", configPath: join(home, ".cursor", "mcp.json") },
    { id: "windsurf", configPath: join(home, ".codeium", "windsurf", "mcp_config.json") },
    // Pi/Gemini/Kiro all use the same `mcpServers` config shape; detect via the
    // install-marker dir so a machine counts as "installed" before its config exists.
    { id: "pi", configPath: join(home, ".pi", "agent", "mcp.json"), detectPath: join(home, ".pi") },
    { id: "gemini", configPath: join(home, ".gemini", "settings.json") },
    { id: "kiro", configPath: join(home, ".kiro", "settings", "mcp.json"), detectPath: join(home, ".kiro") },
  ];
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd system/addons/agentbrain-mcp && bun test src/tests/register.test.ts`
Expected: PASS — all tests in the file pass, including the two new ones.

- [ ] **Step 5: Run the full addon suite (no regressions)**

Run: `cd system/addons/agentbrain-mcp && bun test`
Expected: the whole addon test suite passes.

- [ ] **Step 6: Commit**

```bash
git add system/addons/agentbrain-mcp/src/register.ts system/addons/agentbrain-mcp/src/tests/register.test.ts
git commit -m "feat(mcp): register agentBrain MCP into Pi, Gemini, and Kiro (G15)"
```

---

### Task 2: Advertise the new agents in the addon manifest

**Files:**
- Modify: `system/addons/agentbrain-mcp/manifest.md` (the `support:` block)

- [ ] **Step 1: Extend the support matrix**

In `system/addons/agentbrain-mcp/manifest.md`, replace this exact block:

```markdown
support:
  claude: full
  claude-desktop: full
  cursor: full
  windsurf: full
  hermes: rules
```

with:

```markdown
support:
  claude: full
  claude-desktop: full
  cursor: full
  windsurf: full
  pi: full
  gemini: full
  kiro: full
  hermes: rules
```

- [ ] **Step 2: Verify the manifest still validates**

Run: `bash scripts/check-addons.sh 2>&1 | tail -5`
Expected: no error about `agentbrain-mcp` (the manifest still parses; `support:` keys are recognized agent ids).

- [ ] **Step 3: Verify the support keys match the register targets**

Run: `grep -E '^\s+(pi|gemini|kiro):' system/addons/agentbrain-mcp/manifest.md`
Expected: three lines — `pi: full`, `gemini: full`, `kiro: full`. These are the same three ids added to `targets()` in Task 1, so onboarding Step 4 will now offer the addon for a Pi/Gemini/Kiro user instead of skipping it.

- [ ] **Step 4: Commit**

```bash
git add system/addons/agentbrain-mcp/manifest.md
git commit -m "feat(mcp): advertise Pi/Gemini/Kiro support so /onboard offers the addon (G15)"
```

---

## Self-Review (Sub-plan 4)

- **Spec coverage:** G15 coverage half — "register the MCP server into each detected agent's config" — is delivered for Pi/Gemini/Kiro (Task 1) and surfaced to onboarding via `support:` (Task 2). The write logic already preserves other servers/keys (verified by the new gemini-settings-preservation test). The "fail loudly if enabled-but-not-registered" half is explicitly deferred to Sub-plan 4b (noted, not dropped).
- **Placeholder scan:** every step shows the exact TS / YAML / commands; no TBD.
- **Type/name consistency:** the three ids `pi` / `gemini` / `kiro` are identical across `targets()`, the tests, and the `support:` block. The preservation test asserts on `cfg.mcpServers` keys without hardcoding the server name (robust to `SERVER_NAME`).
- **Assumptions verified at execution:** (a) Pi/Gemini/Kiro use the `mcpServers` shape (verified on the operator's machine); (b) `register()` spreads the loaded JSON and only sets `mcpServers`, so Gemini's `settings.json` `theme`/`selectedAuthType` survive (asserted by the new test); (c) detection uses `detectPath ?? dirname(configPath)` — pi/kiro set `detectPath` to the install-marker dir, gemini relies on `dirname(~/.gemini/settings.json) == ~/.gemini`.

## Not in this sub-plan (Sub-plan 4b)

A `doctor` "MCP registration health" check: when `agentbrain-mcp` is enabled, verify the server is actually present in each detected agent's config and **fail loudly** otherwise. Plus GitHub Copilot CLI once its MCP config path is verified. These are additive follow-ons on top of this coverage fix.
