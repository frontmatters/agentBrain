/**
 * host-agent.ts — agent-agnostic headless completion.
 *
 * The ONE place in agentBrain that knows how to run a one-shot text completion
 * through whatever host coding agent is installed. No provider is hard-coded:
 * each agent uses whatever model/provider the user already has active, so a
 * machine with only Claude Code (or only Copilot, or only Ollama) works with no
 * extra key.
 *
 * Consumers (youtube-digest, …) call `runActiveAgent(prompt)` and never name a
 * specific agent. This file legitimately enumerates agents — it is the agnostic
 * dispatch layer, whitelisted in scripts/check-agnostic.sh for exactly that reason.
 *
 * Verification (per the [[cli-help-grep-not-equals-smoke-test]] learning): each
 * adapter's `verified` flag records whether its invocation was smoke-tested
 * end-to-end, not merely read from `--help`.
 *   verified: pi, copilot, gemini, ollama  (smoke-tested: returned a completion)
 *   documented (not smoke-testable in a shimmed dev shell): claude, codex
 *     — standard headless forms; they work on a normal machine where the real
 *       binary (not a dev shim) is on PATH.
 *
 * Usage as a library:
 *   import { runActiveAgent } from "../../lib/host-agent";
 *   const r = await runActiveAgent(prompt);   // → { agent, text } | null
 *
 * Usage as a CLI (so bash addons can share it):
 *   echo "<prompt>" | bun system/lib/host-agent.ts        # prompt on stdin
 *   bun system/lib/host-agent.ts "<prompt>"               # prompt as arg
 *   (exit 0 + completion on stdout, or exit 1 if no agent produced output)
 */

export interface AgentAdapter {
  name: string;
  /** Executable looked up on PATH. */
  bin: string;
  /** Was the exact invocation smoke-tested end-to-end (not just --help)? */
  verified: boolean;
  /**
   * Build the argv (+ optional stdin) for a one-shot completion. Async so an
   * adapter can probe the environment first (e.g. Ollama picks a local model).
   * Returns null to skip the adapter (e.g. Ollama with no model available).
   */
  build(prompt: string): Promise<{ cmd: string[]; input?: string } | null> | { cmd: string[]; input?: string } | null;
  /** Clean raw stdout down to the model's text answer. */
  clean?(raw: string): string;
}

/** Preference order. The currently-running agent (detected via env) is moved to
 *  the front at call time, so we reuse the agent the user is already in. */
export const DEFAULT_ORDER = ["pi", "claude", "copilot", "gemini", "codex", "ollama"] as const;

/** Env markers a host agent sets for itself — used to prefer the active agent. */
const SELF_ENV: Record<string, string> = {
  claude: "CLAUDECODE",
  pi: "PI_VERSION",
  copilot: "COPILOT_CLI",
  gemini: "GEMINI_CLI",
};

const stripAnsi = (s: string): string =>
  s.replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, "").replace(/\x1b\][^\x07]*\x07/g, "").replace(/\r/g, "");

/** Copilot prints the answer, then a stats footer (Changes / AI Credits / Tokens / Total). */
export function cleanCopilot(raw: string): string {
  const lines = raw.split("\n");
  const cut = lines.findIndex((l) => /^(Changes|AI Credits|Tokens|Total duration|Total)\b/.test(l.trim()));
  return (cut >= 0 ? lines.slice(0, cut) : lines).join("\n").trim();
}

export function cleanOllama(raw: string): string {
  return stripAnsi(raw).trim();
}

/** Pick a local Ollama model. Honors AGENTBRAIN_OLLAMA_MODEL, else the first
 *  non-":cloud" model (cloud models need auth), else any listed model. */
export async function pickOllamaModel(): Promise<string | null> {
  const env = process.env.AGENTBRAIN_OLLAMA_MODEL;
  if (env) return env;
  const raw = await runCmd(["ollama", "list"], null, 10_000);
  if (!raw) return null;
  const models = raw
    .split("\n")
    .slice(1) // header row
    .map((l) => l.split(/\s+/)[0])
    .filter((m): m is string => !!m && m !== "NAME");
  const local = models.filter((m) => !m.endsWith(":cloud"));
  return local[0] ?? models[0] ?? null;
}

export const AGENTS: AgentAdapter[] = [
  {
    name: "pi",
    bin: "pi",
    verified: true,
    // Headless text out, no tools/session/extensions/context — clean completion.
    build: (p) => ({ cmd: ["pi", "-p", "-nt", "-ne", "-nc", "-ns", "-np", "--no-session", "--mode", "text", p] }),
  },
  {
    name: "claude",
    bin: "claude",
    verified: false,
    build: (p) => ({ cmd: ["claude", "-p", "--output-format", "text", p] }),
  },
  {
    name: "copilot",
    bin: "copilot",
    verified: true,
    build: (p) => ({ cmd: ["copilot", "-p", p] }),
    clean: cleanCopilot,
  },
  {
    name: "gemini",
    bin: "gemini",
    verified: true,
    build: (p) => ({ cmd: ["gemini", "-p", p] }),
  },
  {
    name: "codex",
    bin: "codex",
    verified: false,
    build: (p) => ({ cmd: ["codex", "exec", p] }),
  },
  {
    name: "ollama",
    bin: "ollama",
    verified: true,
    build: async (p) => {
      const model = await pickOllamaModel();
      return model ? { cmd: ["ollama", "run", model], input: p } : null;
    },
    clean: cleanOllama,
  },
];

/** Run a command with a hard timeout. Returns stdout, or null on non-zero exit,
 *  spawn failure, or timeout. stderr is discarded (agents emit MCP/log noise). */
async function runCmd(cmd: string[], input: string | null, timeoutMs: number): Promise<string | null> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(cmd, {
      stdin: input != null ? "pipe" : "ignore",
      stdout: "pipe",
      stderr: "ignore",
    });
  } catch {
    return null;
  }
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    try {
      proc.kill();
    } catch {}
  }, timeoutMs);
  try {
    if (input != null && proc.stdin) {
      (proc.stdin as any).write(input);
      await (proc.stdin as any).end();
    }
    const out = await new Response(proc.stdout).text();
    const code = await proc.exited;
    clearTimeout(timer);
    if (timedOut || code !== 0) return null;
    return out;
  } catch {
    clearTimeout(timer);
    return null;
  }
}

/** The host agent the caller is running inside, if detectable via env. */
export function detectSelfAgent(): string | null {
  for (const [name, env] of Object.entries(SELF_ENV)) {
    if (process.env[env]) return name;
  }
  return null;
}

/** Resolve the try-order: the active agent first, then the rest of DEFAULT_ORDER. */
export function resolveOrder(preferred?: string[]): string[] {
  const base = preferred ?? [...DEFAULT_ORDER];
  const self = detectSelfAgent();
  if (self && base.includes(self)) {
    return [self, ...base.filter((n) => n !== self)];
  }
  return base;
}

/** Names of agents whose binary is present on PATH, in resolved order. */
export function availableAgents(preferred?: string[]): string[] {
  return resolveOrder(preferred).filter((name) => {
    const a = AGENTS.find((x) => x.name === name);
    return a ? !!Bun.which(a.bin) : false;
  });
}

/** True when at least one host agent is available to produce a completion. */
export function hasActiveAgent(preferred?: string[]): boolean {
  return availableAgents(preferred).length > 0;
}

export interface RunOptions {
  /** Override the try-order (defaults to DEFAULT_ORDER, active-agent-first). */
  order?: string[];
  /** Per-agent timeout in ms (default 120000). */
  timeoutMs?: number;
}

/**
 * Run one prompt through the first available host agent that yields a non-empty
 * completion. Returns the agent name + cleaned text, or null if no agent
 * produced output. No provider is chosen here — each agent uses its active model.
 */
export async function runActiveAgent(
  prompt: string,
  opts?: RunOptions,
): Promise<{ agent: string; text: string } | null> {
  const order = resolveOrder(opts?.order);
  const timeoutMs = opts?.timeoutMs ?? 120_000;
  for (const name of order) {
    const a = AGENTS.find((x) => x.name === name);
    if (!a || !Bun.which(a.bin)) continue;
    let built: { cmd: string[]; input?: string } | null;
    try {
      built = await a.build(prompt);
    } catch {
      built = null;
    }
    if (!built) continue;
    const raw = await runCmd(built.cmd, built.input ?? null, timeoutMs);
    if (raw == null) continue;
    const text = (a.clean ? a.clean(raw) : raw).trim();
    if (text) return { agent: name, text };
  }
  return null;
}

// ── CLI entry: `bun system/lib/host-agent.ts "<prompt>"` or prompt on stdin ──
if (import.meta.main) {
  const argPrompt = process.argv.slice(2).join(" ").trim();
  const stdinPrompt = !process.stdin.isTTY ? (await Bun.stdin.text()).trim() : "";
  const prompt = argPrompt || stdinPrompt;
  if (!prompt) {
    console.error("host-agent: no prompt (pass as arg or on stdin)");
    process.exit(2);
  }
  const result = await runActiveAgent(prompt);
  if (!result) {
    console.error("host-agent: no host agent produced a completion (tried: " + availableAgents().join(", ") + ")");
    process.exit(1);
  }
  process.stdout.write(result.text);
}
