import { homedir } from "node:os";
import { join, resolve, sep } from "node:path";

// Brain root, resolved LAZILY on each call: explicit env (tests / sandboxes) wins, else the
// switchable ~/agentBrain alias. Lazy rather than a load-time const so that within one process
// — e.g. `bun test` evaluating several test files that each set AGENTBRAIN_DIR — every call
// reads the current env instead of whichever value happened to be cached at first import.
//
// Two env vars, mirroring the bash side so the TS guard and shell tooling never resolve to
// different vaults (notably the incognito flag check, which must agree with `/incognito on`):
//   - AGENTBRAIN_DIR  — the vault path DIRECTLY (no suffix); used by tests/sandboxes, wins.
//   - AGENTBRAIN_HOME — a HOME dir; vault is <home>/agentBrain. This matches the bash semantics
//     in system/addons/incognito/{is-incognito.sh,bin/incognito} (`${AGENTBRAIN_HOME:-$HOME}/agentBrain`).
export function brainRoot(): string {
  if (process.env.AGENTBRAIN_DIR) return process.env.AGENTBRAIN_DIR;
  return join(process.env.AGENTBRAIN_HOME ?? homedir(), "agentBrain");
}

function within(root: string, full: string): boolean {
  return full === root || full.startsWith(root + sep);
}

// Resolve a brain-relative path, refusing anything that escapes the brain root.
export function brainPath(...parts: string[]): string {
  const root = brainRoot();
  const full = resolve(root, ...parts);
  if (!within(root, full)) {
    throw new Error(`Path escapes agentBrain root: ${parts.join("/")}`);
  }
  return full;
}

// Resolve a write target, refusing anything outside local/.
export function localPath(...parts: string[]): string {
  const localRoot = join(brainRoot(), "local");
  const full = resolve(localRoot, ...parts);
  if (!within(localRoot, full)) {
    throw new Error(`Write target must be under local/: ${parts.join("/")}`);
  }
  return full;
}
