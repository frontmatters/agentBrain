import * as fs from "node:fs/promises";
import * as path from "node:path";
import { brainPath } from "../brain-paths";

const EXTRACTED_DIR = brainPath("local", "learnings", "extracted");

export function getSessionId(sessionFile: string | undefined): string {
	if (!sessionFile) return `session-${Date.now()}`;
	return path.basename(sessionFile, ".json").slice(0, 16);
}

export async function saveExtraction(
	sessionId: string,
	extraction: string,
): Promise<string> {
	await fs.mkdir(EXTRACTED_DIR, { recursive: true });
	const date = new Date().toISOString().slice(0, 10);
	const filePath = path.join(EXTRACTED_DIR, `${date}-${sessionId}.md`);
	await fs.writeFile(
		filePath,
		extractionMarkdown(date, sessionId, extraction),
		"utf-8",
	);
	return filePath;
}

function extractionMarkdown(
	date: string,
	sessionId: string,
	extraction: string,
): string {
	return `---
date: ${date}
type: extracted-learning
source: pi-session
session: ${sessionId}
extracted: ${new Date().toISOString()}
status: pending-review
---

# Extracted Learnings — ${date}

> Auto-extracted by Pi extract-learnings extension.
> Review and promote to \`learnings/\` if broadly useful.
> Delete after review.

${extraction}
`;
}
