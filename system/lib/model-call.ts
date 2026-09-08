/**
 * model-call.ts — one prompt through the configured model, with the cascade
 * every behaviour shares: settings -> vault/config/llm.json -> local ollama ->
 * the host agent's active model. Provider-agnostic: an OpenAI-compatible
 * endpoint/model/key triple from config, no provider name special-cased.
 *
 * Lived in youtube-digest until 2026-09-07. extract-learnings, an essential
 * addon, imported it from there; youtube-digest is not in the release payload,
 * so on every fresh install the precompact hook failed to load and no learning
 * was ever extracted. Shared code lives in system/lib; addons reach it as
 * "@agentbrain/lib/*" (system/addons/tsconfig.json for bundled addons, a
 * rendered tsconfig for registry addons in vault/addons/).
 */
import { runActiveAgent, hasActiveAgent } from "./host-agent";
import { resolve } from "path";
import { resolveLlmConfig, probeOllama as probeOllamaLib, isCloud, type LlmConfig } from "./llm-config";

export interface SummarizerConfig {
  /** Friendly label, e.g. "glm" / "openai" / "ollama". */
  provider?: string;
  /** OpenAI-compatible chat/completions endpoint. */
  endpoint: string;
  /** Model name as expected by the provider. */
  model: string;
  /** API key from an env var (tried first). */
  api_key_env?: string;
  /** Or from the dev-config keychain (service name). */
  api_key_keychain?: string;
  max_tokens?: number;
  /** Optional override for the fetch timeout (default 120000ms). */
  fetch_timeout_ms?: number;
}

export interface ModelCallOpts {
  /** Auto-accept the fallback without prompting. */
  assumeYes?: boolean;
  /** Test seam for the active-agent fallback; production uses host-agent. */
  activeAgent?: (prompt: string) => Promise<string | null>;
  /** Test seam for the config resolver; production uses system/lib/llm-config. */
  resolver?: () => Promise<LlmConfig | null>;
  /** Test seam for the ollama probe; production uses system/lib/llm-config. */
  probeOllama?: () => Promise<LlmConfig | null>;
  /** Which addon's per-addon config applies (vault/addons/<slug>/config.json). */
  slug?: string;
}

function defaultResolveLlmConfig(slug: string) {
  // The brain root: AGENTBRAIN_DIR when set, else this file's own place
  // (system/lib -> root). No cwd dependency.
  const brainRoot = process.env.AGENTBRAIN_DIR
    ?? resolve(import.meta.dir, "..", "..");
  return () => resolveLlmConfig({ slug, brainRoot });
}

function probeOllamaDefault() {
  return probeOllamaLib();
}

const FALLBACK_LABEL = "the active agent's model (Pi/Claude)";

async function resolveKey(cfg: SummarizerConfig): Promise<string | undefined> {
  if (cfg.api_key_env && process.env[cfg.api_key_env]) return process.env[cfg.api_key_env];
  if (cfg.api_key_keychain) {
    const { $ } = await import("bun");
    try {
      const r = await $`security find-generic-password -s ${cfg.api_key_keychain} -w ~/Library/Keychains/dev-config.keychain-db`.quiet();
      return r.stdout.toString().trim();
    } catch {
      return undefined;
    }
  }
  return undefined;
}

/** Hard upper bound for one summarization fetch. Long enough for a 10k-token
 *  completion on a slow model, short enough that a dead/hung endpoint can't
 *  hold an entire sync hostage. Overridable per-call via cfg.fetch_timeout_ms. */
const DEFAULT_FETCH_TIMEOUT_MS = 120_000;
/** Total attempts (1 initial + 1 retry). One retry catches transient hiccups
 *  (cold-start, rate-limit blips, brief network glitches) without doubling
 *  cost on permanently-broken endpoints. */
const SUMMARIZE_ATTEMPTS = 2;

async function doOneConfiguredCall(
  cfg: SummarizerConfig,
  prompt: string,
  key: string | undefined,
): Promise<string | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), cfg.fetch_timeout_ms ?? DEFAULT_FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(cfg.endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(key ? { Authorization: `Bearer ${key}` } : {}),
      },
      body: JSON.stringify({
        model: cfg.model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: cfg.max_tokens ?? 2000,
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      throw new Error(`Summarizer ${cfg.provider ?? cfg.model} ${res.status}: ${await res.text()}`);
    }
    const data = (await res.json()) as any;
    return data.choices?.[0]?.message?.content ?? null;
  } finally {
    clearTimeout(timer);
  }
}

/** Generic OpenAI-compatible /chat/completions call. Provider-agnostic — the
 *  endpoint/model/key triple comes from cfg, no provider name is special-cased.
 *  Retries once on failure with a short backoff so one transient hiccup
 *  (z.ai cold-start, brief rate-limit, network glitch) doesn't drop a
 *  transcript to TODO-placeholder. After SUMMARIZE_ATTEMPTS the last error
 *  propagates and the caller keeps the placeholder. */
export async function callConfigured(cfg: SummarizerConfig, prompt: string): Promise<string | null> {
  const key = await resolveKey(cfg);
  let lastError: unknown;
  for (let attempt = 1; attempt <= SUMMARIZE_ATTEMPTS; attempt++) {
    try {
      return await doOneConfiguredCall(cfg, prompt, key);
    } catch (e) {
      lastError = e;
      if (attempt < SUMMARIZE_ATTEMPTS) {
        const backoffMs = 2000 * attempt;
        console.log(`[summarizer] attempt ${attempt}/${SUMMARIZE_ATTEMPTS} failed (${(e as Error).message?.slice(0, 80)}), retrying in ${backoffMs}ms`);
        await new Promise((r) => setTimeout(r, backoffMs));
      }
    }
  }
  throw lastError;
}

/** True when the process must never block on a prompt: an explicit
 *  YTK_NON_INTERACTIVE flag (set by the launchd/cron entrypoint), or any of the
 *  generic CI markers. The scheduled path sets YTK_NON_INTERACTIVE=1 so a missing
 *  summarizer at 03:00 falls back silently to a TODO placeholder instead of
 *  hanging on stdin forever. */
export function isNonInteractive(): boolean {
  const flag = (process.env.YTK_NON_INTERACTIVE ?? "").toLowerCase();
  if (flag === "1" || flag === "true" || flag === "yes") return true;
  if (process.env.CI) return true;
  return false;
}

/** Ask before falling back to the active model. Skipped entirely when
 *  non-interactive (cron) or when there is no TTY — both auto-fall-back with a
 *  notice instead of prompting. */
function confirmFallback(opts?: ModelCallOpts): boolean {
  if (opts?.assumeYes) return true;
  if (isNonInteractive()) {
    console.log(`[summarizer] non-interactive (YTK_NON_INTERACTIVE) — falling back to ${FALLBACK_LABEL} without prompt.`);
    return true;
  }
  if (!process.stdin.isTTY) {
    console.log(`[summarizer] No summarizer configured — falling back to ${FALLBACK_LABEL} (headless).`);
    return true;
  }
  const ans = prompt(`No summarizer configured. Fall back to ${FALLBACK_LABEL}? [y/N]`);
  return /^y(es)?$/i.test((ans ?? "").trim());
}

/** Fallback: summarize with whatever host agent is installed, headless. Delegates
 *  to the shared agent-agnostic runner (system/lib/host-agent.ts): no provider is
 *  hard-coded and the agent the user is already in is preferred, so a machine with
 *  only Claude Code / Copilot / Gemini / Ollama still gets summaries out of the box. */
async function callActiveAgent(prompt: string): Promise<string | null> {
  const result = await runActiveAgent(prompt);
  if (!result) {
    if (!hasActiveAgent()) {
      console.log("[summarizer] no host agent found — configure settings.summarizer or install a coding agent (Claude Code, Pi, Copilot, Gemini, Ollama, …).");
    }
    return null;
  }
  return result.text;
}

/** Run one prompt through the configured model, with Pi as a salvage-fallback
 *  on hard failures (auth, rate-limit, model deprecation). The configured-fail
 *  fallback is automatic — no TTY confirmation — because the user already
 *  expressed a preference by setting settings.summarizer; the fallback only
 *  fires when that preference can't be honored. Reused by other behaviors
 *  (extract-learnings). */
export async function callModel(
  prompt: string,
  settings: { summarizer?: SummarizerConfig },
  opts?: { assumeYes?: boolean; activeAgent?: (prompt: string) => Promise<string | null>; resolver?: () => Promise<LlmConfig | null>; probeOllama?: () => Promise<LlmConfig | null> }
): Promise<string | null> {
  // Cascaded config (system/security-policy.md): skill -> user-wide llm.json ->
  // active LLM -> local ollama probe -> decline. Never a shipped cloud default.
  let cfg = settings.summarizer;
  let sourceLabel = "settings.summarizer";
  if (!(cfg?.endpoint && cfg?.model)) {
    const resolved = await (opts?.resolver ?? defaultResolveLlmConfig(opts?.slug ?? "youtube-digest"))();
    if (resolved) {
      cfg = resolved;
      sourceLabel = resolved.source === "user" ? "vault/config/llm.json (user default)" : "local ollama probe";
    }
  }
  if (cfg?.endpoint && cfg?.model) {
    if (isCloud(cfg)) {
      console.log(`[summarizer] data-exit: transcript goes to ${cfg.endpoint} (model: ${cfg.model}, source: ${sourceLabel})`);
    } else {
      console.log(`[summarizer] summarizing with ${cfg.model} via ${sourceLabel}`);
    }
    try {
      return await callConfigured(cfg, prompt);
    } catch (e) {
      const label = cfg.provider ?? cfg.model;
      const msg = (e as Error).message?.slice(0, 100) ?? String(e);
      if (hasActiveAgent()) {
        console.log(`[summarizer] configured (${label}) failed: ${msg} — falling back to the active agent (Pi/Claude)`);
        const agentResult = await (opts?.activeAgent ?? callActiveAgent)(prompt);
        if (agentResult) return agentResult;
        console.log(`[summarizer] agent-fallback also returned nothing — giving up`);
      } else {
        console.log(`[summarizer] configured (${label}) failed: ${msg} — no host agent (pi/claude) available for fallback`);
      }
      throw e;
    }
  }
  // Cascade layer 3: the active LLM (the host agent's model), with consent.
  if (hasActiveAgent() && confirmFallback(opts)) {
    const agentResult = await (opts?.activeAgent ?? callActiveAgent)(prompt);
    if (agentResult) return agentResult;
    // Cascade layer 4: a genuinely local ollama model before giving up.
    const ollama = await (opts?.probeOllama ?? probeOllamaDefault)();
    if (ollama) {
      console.log(`[summarizer] no agent result — trying local ollama model ${ollama.model}`);
      try {
        return await callConfigured(ollama, prompt);
      } catch {
        // fall through to the placeholder
      }
    }
    return null;
  }
  return null;
}
