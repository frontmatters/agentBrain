import * as fs from "node:fs";
import * as fsp from "node:fs/promises";
import * as path from "node:path";
import { brainPath } from "../brain-paths";
import { markdownDateTime, month, pid, stamp } from "./date";
import { replaceFrontmatter } from "./frontmatter";
import { pseudoUuid5 } from "./uuid";

export const JOURNAL = brainPath("local", "sessions", "session-journal.md");

export type SessionArchiveTarget = {
	base: string;
	archiveMonth: string;
	relWithoutExt: string;
	target: string;
};

async function exists(file: string): Promise<boolean> {
	try {
		await fsp.access(file, fs.constants.F_OK);
		return true;
	} catch {
		return false;
	}
}

export function selectSessionArchiveTarget(
	now = new Date(),
	makePid: () => string = pid,
	pathExists: (file: string) => boolean = fs.existsSync,
): SessionArchiveTarget {
	const archiveMonth = month(now);
	for (let attempt = 0; attempt < 10; attempt++) {
		const base = `${stamp(now)}-${makePid()}`;
		const relWithoutExt = `local/sessions/archive/${archiveMonth}/${base}`;
		const target = brainPath(`${relWithoutExt}.md`);
		if (!pathExists(target))
			return { base, archiveMonth, relWithoutExt, target };
	}
	throw new Error("Could not allocate unique session archive filename");
}

export async function archiveCurrentJournal(): Promise<string | undefined> {
	if (!(await exists(JOURNAL))) return undefined;
	const original = await fsp.readFile(JOURNAL, "utf8");
	if (!original.trim()) return undefined;
	const selected = selectSessionArchiveTarget(new Date());
	await fsp.mkdir(archiveDir(selected.archiveMonth), { recursive: true });
	const id = await pseudoUuid5(selected.relWithoutExt);
	const archived = replaceFrontmatter(original, { id, status: "archived" });
	await fsp.writeFile(selected.target, archived, "utf8");
	return selected.base;
}

function archiveDir(archiveMonth: string): string {
	return brainPath("local", "sessions", "archive", archiveMonth);
}

export async function writeFreshJournal(previous?: string): Promise<void> {
	const id = await pseudoUuid5("local/sessions/session-journal");
	const { date, time } = markdownDateTime();
	await fsp.mkdir(path.dirname(JOURNAL), { recursive: true });
	await fsp.writeFile(
		JOURNAL,
		freshJournalContent({ id, date, time, previous }),
		"utf8",
	);
}

function freshJournalContent(options: {
	id: string;
	date: string;
	time: string;
	previous?: string;
}): string {
	return `---
date: ${options.date}
type: session-journal
tags: [session]
project: 
previous: ${options.previous ?? ""}
id: ${options.id}
status: active
---

# Session Journal

## Last updated: ${options.time}

### Project: 
### Task: 

### Done
- 

### Files changed
- 

### Next step
-> 

### Open questions
- 
`;
}
