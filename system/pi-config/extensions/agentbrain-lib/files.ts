import * as fs from "node:fs";
import * as fsp from "node:fs/promises";
import * as path from "node:path";
import { MAX_FILE_BYTES, SEARCH_EXCLUDE_DIRS } from "./constants";

export async function exists(file: string): Promise<boolean> {
	try {
		await fsp.access(file, fs.constants.F_OK);
		return true;
	} catch {
		return false;
	}
}

export async function readLimited(
	file: string,
	maxBytes = MAX_FILE_BYTES,
): Promise<{ text: string; truncated: boolean }> {
	const buffer = await fsp.readFile(file);
	const truncated = buffer.length > maxBytes;
	return { text: buffer.subarray(0, maxBytes).toString("utf8"), truncated };
}

// pi-lens-ignore: ts-path-traversal — dir is always a brainPath() or scoped vault path
export async function listMarkdownFiles(
	dir: string,
	results: string[] = [],
	seen: Set<string> = new Set(),
): Promise<string[]> {
	// Cycle guard: the vault is built from symlinks (e.g. `local/` → the shared
	// vault), which we follow below. Track visited real paths so a symlink loop
	// can't spin the walker forever.
	let realDir: string;
	try {
		realDir = await fsp.realpath(dir);
	} catch {
		return results;
	}
	if (seen.has(realDir)) return results;
	seen.add(realDir);

	let entries: fs.Dirent[];
	try {
		entries = await fsp.readdir(dir, { withFileTypes: true });
	} catch {
		return results;
	}
	for (const entry of entries) {
		if (entry.name.startsWith(".")) continue;
		const full = path.join(dir, entry.name);
		// A symlinked directory reports isDirectory()===false, so resolve it: the
		// vault's `local/` is a symlink and must be walked, else the entire private
		// knowledge base is invisible to search.
		let isDir = entry.isDirectory();
		if (!isDir && entry.isSymbolicLink()) {
			try {
				isDir = (await fsp.stat(full)).isDirectory();
			} catch {
				continue;
			}
		}
		if (isDir) {
			if (SEARCH_EXCLUDE_DIRS.has(entry.name)) continue;
			await listMarkdownFiles(full, results, seen);
		} else if (entry.name.endsWith(".md")) {
			results.push(full);
		}
	}
	return results;
}
