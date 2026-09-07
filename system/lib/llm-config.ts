/**
 * llm-config — shared resolver for the local-first LLM-config pattern.
 * Policy: system/security-policy.md ("Shipped skills stay user- and
 * model-agnostic"). Shipped code defines config shape; values live per user.
 *
 * Resolution order:
 *   1. skill-local config  vault/addons/<slug>/config.json  → [key]
 *   2. user-wide default   vault/config/llm.json
 *   3. local Ollama probe  http://127.0.0.1:11434 (first genuinely local model)
 *   4. null → caller asks or declines. There is no shipped cloud default.
 *
 * Smoke test: bun system/lib/llm-config.ts <slug> [key]
 * Unit tests:  bun test system/lib/llm-config.test.ts
 */

import { join } from "path";
import { existsSync } from "node:fs";

/** The private layer on disk: vault/ (current name) or local/ (older installs). */
export function localDir(root: string): string {
  const v = join(root, "vault");
  return existsSync(v) ? v : join(root, "local");
}

export interface LlmConfig {
  endpoint: string;
  model: string;
  api_key_env?: string;
  api_key_keychain?: string;
  max_tokens?: number;
  fetch_timeout_ms?: number;
  /** Which layer answered; callers print this before sending. */
  source: "skill" | "user" | "ollama";
}

const LOCAL_ENDPOINT =
  /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(\/|$)/i;

/** Ollama proxies `:cloud` models to Ollama's cloud: localhost endpoint, non-local inference. */
export function isCloudModel(model: string): boolean {
  return /:cloud$/i.test(model.trim());
}

/** True when the endpoint is not local, or the model is a `:cloud` model:
 *  the data-exit rule applies (policy) and the caller must disclose. */
export function isCloud(cfg: LlmConfig): boolean {
  return !LOCAL_ENDPOINT.test(cfg.endpoint) || isCloudModel(cfg.model);
}

/** Pick the first genuinely local model from an ollama /api/tags list. */
export function firstLocalModel(
  models: { name: string }[] | undefined,
): string | null {
  return models?.map((m) => m.name).find((n) => !isCloudModel(n)) ?? null;
}

const FORBIDDEN_SECRET_KEYS = [
  "api_key",
  "apikey",
  "api-key",
  "key",
  "token",
  "password",
  "secret",
];

/**
 * Validate a config object at the write gate (llm-config set-*): URLs must
 * parse, model is required, and raw secrets are rejected: keys live in env
 * vars or a keychain (api_key_env / api_key_keychain), never in files.
 */
export function validateLlmConfig(
  value: unknown,
): { ok: true; cfg: LlmConfig } | { ok: false; error: string } {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return { ok: false, error: "config must be a JSON object" };
  }
  const v = value as Record<string, unknown>;
  for (const k of Object.keys(v)) {
    if (FORBIDDEN_SECRET_KEYS.includes(k.toLowerCase())) {
      return {
        ok: false,
        error: `field "${k}" is a raw secret. Use "api_key_env" or "api_key_keychain" instead (policy: keys never in files).`,
      };
    }
  }
  if (typeof v.endpoint !== "string" || v.endpoint.length === 0) {
    return { ok: false, error: "endpoint is required" };
  }
  try {
    new URL(v.endpoint);
  } catch {
    return { ok: false, error: `endpoint is not a valid URL: ${v.endpoint}` };
  }
  if (typeof v.model !== "string" || v.model.length === 0) {
    return { ok: false, error: "model is required" };
  }
  return { ok: true, cfg: v as unknown as LlmConfig };
}

/**
 * Pure precedence core: skill config wins, then the user-wide default.
 * Returns null when neither layer holds a valid config.
 */
export function pickFirstValid(
  skillCfg: unknown,
  userCfg: unknown,
): { cfg: LlmConfig; source: "skill" | "user" } | null {
  if (valid(skillCfg)) return { cfg: skillCfg, source: "skill" };
  if (valid(userCfg)) return { cfg: userCfg, source: "user" };
  return null;
}

function valid(cfg: unknown): cfg is LlmConfig {
  const c = cfg as LlmConfig | undefined;
  return (
    !!c &&
    typeof c === "object" &&
    typeof c.endpoint === "string" &&
    c.endpoint.length > 0 &&
    typeof c.model === "string" &&
    c.model.length > 0
  );
}

/** Resolve the API key for a config: env var first, then a keychain lookup.
 * Darwin uses `security`; other platforms try `secret-tool`. Returns
 * undefined when neither is configured or found. */
export async function resolveApiKey(
  cfg: LlmConfig,
): Promise<string | undefined> {
  if (cfg.api_key_env) {
    const fromEnv = process.env[cfg.api_key_env];
    if (fromEnv) return fromEnv;
  }
  if (cfg.api_key_keychain) {
    const { $ } = await import("bun");
    try {
      if (process.platform === "darwin") {
        const r = await $`security find-generic-password -s ${cfg.api_key_keychain} -w`.quiet();
        const out = r.stdout.toString().trim();
        if (out) return out;
      } else {
        const r = await $`secret-tool lookup service ${cfg.api_key_keychain}`.quiet();
        const out = r.stdout.toString().trim();
        if (out) return out;
      }
    } catch {
      return undefined;
    }
  }
  return undefined;
}

/** Local Ollama probe: answers with a config only when Ollama is reachable
 * AND at least one genuinely local model is loaded. `:cloud` models are
 * skipped: localhost proxy, cloud inference. */
export async function probeOllama(
  timeoutMs = 600,
): Promise<LlmConfig | null> {
  try {
    const res = await fetch("http://127.0.0.1:11434/api/tags", {
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) return null;
    const tags = (await res.json()) as { models?: { name: string }[] };
    const model = firstLocalModel(tags.models);
    return model
      ? { endpoint: "http://127.0.0.1:11434/v1", model, source: "ollama" }
      : null;
  } catch {
    return null;
  }
}

export interface ResolveOpts {
  /** Vault root (the agentBrain dir). Defaults to $AGENTBRAIN_DIR. */
  brainRoot?: string;
  /** Addon slug: config lives at vault/addons/<slug>/config.json. */
  slug: string;
  /** The skill's own key inside its config file. */
  key?: string;
  /** Callers that already loaded their config can pass the object directly. */
  skillConfig?: Record<string, unknown>;
}

/**
 * Cascade layer 2 only: the user-wide default (vault/config/llm.json).
 * Skills with an active-LLM concept splice that layer between this and the
 * ollama probe; config-only skills use resolveLlmConfig directly.
 */
export async function resolveUserLlmConfig(
  brainRoot?: string,
): Promise<LlmConfig | null> {
  const root = brainRoot ?? process.env.AGENTBRAIN_DIR;
  if (!root) return null;
  const cfg = await loadJson(join(localDir(root), "config", "llm.json"));
  return valid(cfg) ? cfg : null;
}

/**
 * Resolve the LLM config for one skill (config-only consumers: no active-LLM
 * layer). Returns null when nothing local answers: the caller asks or declines.
 * The result NEVER comes from shipped defaults; cloud endpoints are always
 * user-configured values.
 */
export async function resolveLlmConfig(
  opts: ResolveOpts,
): Promise<LlmConfig | null> {
  const root =
    opts.brainRoot ?? process.env.AGENTBRAIN_DIR
    ?? (await import("path")).resolve((await import("path")).join("."));
  // 1 + 2. skill-local, then user-wide
  const local = opts.skillConfig
    ?? (await loadJson(join(localDir(root), "addons", opts.slug, "config.json")));
  const userCfg = await loadJson(join(localDir(root), "config", "llm.json"));
  const picked = pickFirstValid(local?.[opts.key ?? "llm"], userCfg);
  if (picked) return picked.cfg;

  // 3. local Ollama
  return probeOllama();
}

async function loadJson(path: string): Promise<Record<string, unknown> | null> {
  try {
    const { readFileSync } = await import("fs");
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

// Smoke: bun system/lib/llm-config.ts <slug> [key]
if (import.meta.main) {
  const slug = process.argv[2];
  const key = process.argv[3];
  if (!slug) {
    console.error("usage: bun system/lib/llm-config.ts <slug> [key]");
    process.exit(2);
  }
  const cfg = await resolveLlmConfig({ slug, key });
  if (!cfg) {
    console.log("decline: no skill config, no user default, no local Ollama");
    process.exit(1);
  }
  console.log(JSON.stringify(cfg, null, 2));
  if (isCloud(cfg)) {
    console.log("NOTE: non-local endpoint or :cloud model. The data-exit rule applies: print destination and confirm before sending.");
  }
}
