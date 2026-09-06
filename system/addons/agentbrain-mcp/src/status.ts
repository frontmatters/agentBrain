import { readFile, realpath } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { brainRoot, brainPath } from "./brain";

// execFile with a fixed argv (never a shell) — no injection surface.
const run = promisify(execFile);

// Read-only framework status for shell-less MCP clients ("which version and
// channel is my brain on?"). Lifecycle MUTATIONS (update, wire, channel set,
// doctor) deliberately stay CLI-only — an MCP client must not administer the
// framework.
//
// Injection hardening: every emitted value is validated against a closed
// pattern. Config values and git tag names are on-disk data a hostile note or
// tool could have tampered with; anything that does not match its pattern is
// replaced by "invalid" so free text can never ride along into model context.
const CHANNELS = new Set(["edge", "prerelease", "stable"]);
const MODES = new Set(["branch", "tag"]);
const APPLY = new Set(["ask", "notify", "auto", "off"]);
const VERSION_RE = /^v?\d+\.\d+\.\d+(-[A-Za-z0-9.-]{1,40})?$/;
const DESCRIBE_RE = /^v\d+\.\d+\.\d+(-[A-Za-z0-9.-]{1,40})?(-\d+-g[0-9a-f]{4,40})?$/;

function inSet(v: unknown, set: Set<string>): string {
  return typeof v === "string" && set.has(v) ? v : "invalid";
}
function matching(v: unknown, re: RegExp): string {
  return typeof v === "string" && re.test(v.trim()) ? v.trim() : "invalid";
}

export async function status(): Promise<object> {
  const root = brainRoot();
  let checkout = root;
  try {
    checkout = await realpath(root);
  } catch {}

  let release = "unknown";
  try {
    release = matching(await readFile(brainPath("VERSION"), "utf8"), VERSION_RE);
  } catch {}

  let version = release === "invalid" || release === "unknown" ? release : `v${release}`;
  try {
    const { stdout } = await run(
      "git", ["-C", checkout, "describe", "--tags", "--match", "v*"],
      { timeout: 3000 },
    );
    const d = matching(stdout, DESCRIBE_RE);
    if (d !== "invalid") version = d;
  } catch {}

  let channel = "unset", mode = "unset", auto_update = "unset";
  try {
    const cfg = JSON.parse(await readFile(brainPath("local/update/config.json"), "utf8"));
    channel = inSet(cfg.channel, CHANNELS);
    mode = inSet(cfg.mode, MODES);
    auto_update = inSet(cfg.auto_update, APPLY);
  } catch {}

  return {
    checkout,
    version,
    release,
    channel,
    mode,
    auto_update,
    note: "read-only — lifecycle ops (update, wire, doctor) run via the brain CLI on the host",
  };
}
