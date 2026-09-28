export function replaceFrontmatter(
	text: string,
	patch: Record<string, string>,
): string {
	if (!text.startsWith("---\n")) return text;
	const end = text.indexOf("\n---", 4);
	if (end === -1) return text;
	const frontmatter = patchFrontmatterLines(text.slice(4, end), patch);
	return `---\n${frontmatter}\n---${text.slice(end + 4)}`;
}

function patchFrontmatterLines(
	raw: string,
	patch: Record<string, string>,
): string {
	let lines = raw.split(/\r?\n/);
	for (const [key, value] of Object.entries(patch)) {
		lines = patchFrontmatterKey(lines, key, value);
	}
	return lines.join("\n");
}

function patchFrontmatterKey(
	lines: string[],
	key: string,
	value: string,
): string[] {
	let found = false;
	const patched = lines.map((line) => {
		if (!line.startsWith(`${key}:`)) return line;
		found = true;
		return `${key}: ${value}`;
	});
	if (!found) patched.push(`${key}: ${value}`);
	return patched;
}
