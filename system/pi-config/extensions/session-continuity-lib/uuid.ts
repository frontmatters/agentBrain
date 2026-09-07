import * as fsp from "node:fs/promises";
import { createHash } from "node:crypto";
import { brainPath } from "../brain-paths";

const FALLBACK_NAMESPACE = "a3b2c1d0-1234-5678-9abc-def012345678";

export async function readNamespace(): Promise<string> {
	try {
		const raw = await fsp.readFile(brainPath("brain.json"), "utf8");
		const parsed = JSON.parse(raw) as { namespace?: string };
		return parsed.namespace || FALLBACK_NAMESPACE;
	} catch {
		return FALLBACK_NAMESPACE;
	}
}

export async function pseudoUuid5(notePathWithoutExt: string): Promise<string> {
	const namespace = await readNamespace();
	// Ids hash the local/ spelling; vault/ is the link's name on disk (uuid5-gen.sh folds the same way).
	notePathWithoutExt = notePathWithoutExt.replace(/^vault(\/|$)/, "local$1");
	const hash = createHash("sha1")
		.update(`${namespace}:agentBrain/${notePathWithoutExt}`)
		.digest("hex");
	return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-5${hash.slice(13, 16)}-${((parseInt(hash.slice(16, 18), 16) & 0x3f) | 0x80).toString(16)}${hash.slice(18, 20)}-${hash.slice(20, 32)}`;
}
