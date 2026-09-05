#!/usr/bin/env bun
import { describe, test, expect } from "bun:test";
import {
  isCloud,
  isCloudModel,
  firstLocalModel,
  pickFirstValid,
  validateLlmConfig,
  resolveApiKey,
  type LlmConfig,
} from "./llm-config.ts";

const localCfg = (over: Partial<LlmConfig> = {}): LlmConfig => ({
  endpoint: "http://127.0.0.1:11434/v1",
  model: "qwen3.8:latest",
  ...over,
});

describe("isCloudModel", () => {
  test("flags ollama :cloud models", () => {
    expect(isCloudModel("glm-5.3:cloud")).toBe(true);
    expect(isCloudModel("GLM:Cloud")).toBe(true);
  });
  test("passes local models", () => {
    expect(isCloudModel("qwen3.8:27b-mlx")).toBe(false);
    expect(isCloudModel("llama3")).toBe(false);
  });
});

describe("isCloud", () => {
  test("localhost endpoint + local model is not cloud", () => {
    expect(isCloud(localCfg())).toBe(false);
  });
  test("remote endpoint is cloud", () => {
    expect(isCloud(localCfg({ endpoint: "https://api.z.ai/api/v4" }))).toBe(true);
  });
  test("localhost endpoint with :cloud model is still cloud", () => {
    expect(isCloud(localCfg({ model: "glm-5.3:cloud" }))).toBe(true);
  });
});

describe("firstLocalModel", () => {
  test("skips :cloud models, picks the first local one", () => {
    expect(
      firstLocalModel([
        { name: "glm-5.3:cloud" },
        { name: "qwen3.8:27b-mlx" },
        { name: "llama3" },
      ]),
    ).toBe("qwen3.8:27b-mlx");
  });
  test("all-cloud list yields null", () => {
    expect(firstLocalModel([{ name: "a:cloud" }, { name: "b:cloud" }])).toBeNull();
  });
  test("undefined yields null", () => {
    expect(firstLocalModel(undefined)).toBeNull();
  });
});

describe("pickFirstValid", () => {
  test("skill config wins over user default", () => {
    const r = pickFirstValid(localCfg({ model: "skill-model" }), localCfg({ model: "user-model" }));
    expect(r?.source).toBe("skill");
    expect(r?.cfg.model).toBe("skill-model");
  });
  test("user default used when skill has none", () => {
    const r = pickFirstValid(undefined, localCfg({ model: "user-model" }));
    expect(r?.source).toBe("user");
  });
  test("invalid skill config falls through to user", () => {
    const r = pickFirstValid({ endpoint: "" }, localCfg());
    expect(r?.source).toBe("user");
  });
  test("nothing valid yields null", () => {
    expect(pickFirstValid(undefined, undefined)).toBeNull();
    expect(pickFirstValid({ endpoint: "nope" }, {})).toBeNull();
  });
});

describe("validateLlmConfig", () => {
  test("accepts a minimal valid config", () => {
    const r = validateLlmConfig({ endpoint: "http://gn100:11434/v1", model: "glm-4.5-air:q4kxl" });
    expect(r.ok).toBe(true);
  });
  test("rejects raw secret fields", () => {
    for (const field of ["api_key", "apiKey", "token", "password"]) {
      const r = validateLlmConfig({ endpoint: "http://x/v1", model: "m", [field]: "sk-secret" });
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error).toContain("api_key_env");
    }
  });
  test("rejects an unparseable endpoint", () => {
    expect(validateLlmConfig({ endpoint: "not a url", model: "m" }).ok).toBe(false);
  });
  test("rejects a missing model", () => {
    expect(validateLlmConfig({ endpoint: "http://x/v1" }).ok).toBe(false);
  });
  test("rejects non-objects", () => {
    expect(validateLlmConfig("http://x").ok).toBe(false);
    expect(validateLlmConfig(null).ok).toBe(false);
  });
});

describe("resolveApiKey", () => {
  test("env var wins", async () => {
    process.env.TEST_LLM_KEY_XYZ = "sk-test-123";
    const key = await resolveApiKey({ endpoint: "http://x/v1", model: "m", api_key_env: "TEST_LLM_KEY_XYZ" });
    expect(key).toBe("sk-test-123");
    delete process.env.TEST_LLM_KEY_XYZ;
  });
  test("nothing configured yields undefined", async () => {
    expect(await resolveApiKey({ endpoint: "http://x/v1", model: "m" })).toBeUndefined();
  });
});
