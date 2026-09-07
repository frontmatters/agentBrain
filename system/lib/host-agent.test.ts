import { test, expect } from "bun:test";
import {
  cleanCopilot,
  cleanOllama,
  resolveOrder,
  detectSelfAgent,
  DEFAULT_ORDER,
  AGENTS,
} from "./host-agent";

test("cleanCopilot strips the stats footer, keeps the answer", () => {
  const raw = ["PONG", "", "", "Changes    +0 -0", "AI Credits 8.44 (16s)", "Tokens     ↑ 22.5k • ↓ 6"].join("\n");
  expect(cleanCopilot(raw)).toBe("PONG");
});

test("cleanCopilot is a no-op when there is no footer", () => {
  expect(cleanCopilot("just an answer\nsecond line")).toBe("just an answer\nsecond line");
});

test("cleanOllama strips ANSI/spinner noise", () => {
  const raw = "\x1b[?25lP\x1b[?25h\x1b[?25lONG\x1b[?25h\n";
  expect(cleanOllama(raw)).toBe("PONG");
});

test("resolveOrder keeps DEFAULT_ORDER when no self-agent env is set", () => {
  const saved: Record<string, string | undefined> = {};
  for (const e of ["CLAUDECODE", "PI_VERSION", "COPILOT_CLI", "GEMINI_CLI"]) {
    saved[e] = process.env[e];
    delete process.env[e];
  }
  try {
    expect(resolveOrder()).toEqual([...DEFAULT_ORDER]);
    expect(detectSelfAgent()).toBeNull();
  } finally {
    for (const [e, v] of Object.entries(saved)) if (v !== undefined) process.env[e] = v;
  }
});

test("resolveOrder moves the active agent to the front", () => {
  const envs = ["CLAUDECODE", "PI_VERSION", "COPILOT_CLI", "GEMINI_CLI"];
  const saved: Record<string, string | undefined> = {};
  for (const e of envs) {
    saved[e] = process.env[e];
    delete process.env[e];
  }
  process.env.COPILOT_CLI = "1"; // only copilot marked active
  try {
    const order = resolveOrder();
    expect(order[0]).toBe("copilot");
    expect(new Set(order)).toEqual(new Set(DEFAULT_ORDER));
    expect(order.length).toBe(DEFAULT_ORDER.length); // no duplicate
  } finally {
    for (const [e, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[e];
      else process.env[e] = v;
    }
  }
});

test("every DEFAULT_ORDER name has a registered adapter", () => {
  for (const name of DEFAULT_ORDER) {
    expect(AGENTS.find((a) => a.name === name)).toBeDefined();
  }
});

test("verified flags match the smoke-test record", () => {
  const byName = Object.fromEntries(AGENTS.map((a) => [a.name, a.verified]));
  expect(byName.pi).toBe(true);
  expect(byName.copilot).toBe(true);
  expect(byName.gemini).toBe(true);
  expect(byName.ollama).toBe(true);
  expect(byName.claude).toBe(false); // documented, not smoke-testable in shim env
  expect(byName.codex).toBe(false);
});
