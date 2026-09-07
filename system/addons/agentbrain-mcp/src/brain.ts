import { homedir } from "node:os";
import { existsSync } from "node:fs";
import { join, relative, resolve, sep } from "node:path";

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

// The vault's link in a checkout is vault/; local/ is the older name, kept as an
// alias. Every id, skip list and access-index key inside this server is spelled
// local/, the same rule uuid5-gen.sh applies, so a path handed in as vault/...
// is folded to local/... at the boundary and the two spellings name one note.
export function canonRel(p: string): string {
  return p.replace(/^\.?\/?vault(\/|$)/, "local$1");
}

// Where the vault sits on disk: vault/ in a current checkout, local/ in an
// older one. Only disk access goes through here; ids and index keys keep the
// local/ spelling, see brainRel().
export function localDisk(): string {
  const root = brainRoot();
  const v = join(root, "vault");
  return existsSync(v) ? v : join(root, "local");
}

// The identity of a file under the vault: local/<path>, whatever directory it
// was read from. Search keys, access records and ids all use this form.
export function brainRel(full: string): string {
  const disk = localDisk();
  if (within(disk, full)) return "local" + full.slice(disk.length).split(sep).join("/");
  return relative(brainRoot(), full);
}

// Resolve a brain-relative path, refusing anything that escapes the brain root.
// A local/... path is a vault path and lands where the vault is on disk.
export function brainPath(...parts: string[]): string {
  const root = brainRoot();
  const rel = parts.join("/");
  const full = rel === "local" || rel.startsWith("local/")
    ? resolve(localDisk(), rel.slice("local/".length))
    : resolve(root, ...parts);
  if (!within(root, full)) {
    throw new Error(`Path escapes agentBrain root: ${parts.join("/")}`);
  }
  return full;
}

// Resolve a write target, refusing anything outside local/.
export function localPath(...parts: string[]): string {
  const localRoot = localDisk();
  const full = resolve(localRoot, ...parts);
  if (!within(localRoot, full)) {
    throw new Error(`Write target must be under local/: ${parts.join("/")}`);
  }
  return full;
}
