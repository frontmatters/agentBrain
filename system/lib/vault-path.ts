import { homedir } from "node:os";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";

/** Resolve the active private vault for standalone TypeScript/Bun tools. */
export function resolveVaultDir(
  brainRoot: string,
  exists: (path: string) => boolean = existsSync,
): string {
  const configured =
    process.env.AGENTBRAIN_VAULT ??
    process.env.AGENTBRAIN_VAULT_DIR ??
    process.env.AGENTBRAIN_LOCAL_DIR;
  if (configured) {
    return resolve(configured.replace(/^~(?=\/|$)/, homedir()));
  }

  const linked = join(brainRoot, "vault");
  return exists(linked) ? linked : join(brainRoot, "local");
}
