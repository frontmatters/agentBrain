// env-secrets.ts — redact known-secret env var VALUES from bash tool output.
//
// Rationale: file-glob based cloaking (cloak.ts) only fires on the `read`
// tool, keyed on file path. It cannot catch a secret printed via `bash`
// (e.g. a credential-helper function invoked without capturing its stdout).
// Regex-shape detection (generic "40 hex chars") is too noisy — git commit
// SHAs collide with common token shapes. Instead: mirror how CI systems mask
// secrets — scan process.env for keys that *look* secret-ish, and if their
// *exact current value* appears anywhere in the bash output, redact it. Zero
// shape-guessing, near-zero false positives, catches the exact leak pattern
// this was built for (a credential helper printing its value bare).
const SECRET_NAME_PATTERN =
	/token|secret|password|passwd|api[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret|auth(?:orization)?|credential/i;

const MIN_SECRET_LENGTH = 8;
const REDACTED = "***REDACTED-ENV-SECRET***";

/** Known-secret values currently exported in this process's env. Recomputed
 * per call (cheap) so a freshly-exported token is caught immediately. */
export function knownSecretValues(env: NodeJS.ProcessEnv = process.env): string[] {
	const values = new Set<string>();
	for (const [key, value] of Object.entries(env)) {
		if (!value || value.length < MIN_SECRET_LENGTH) continue;
		if (!SECRET_NAME_PATTERN.test(key)) continue;
		values.add(value);
	}
	// Longest first: prevents a short secret's replacement from mangling a
	// longer secret that contains it as a substring.
	return Array.from(values).sort((a, b) => b.length - a.length);
}

export function redactKnownSecrets(
	text: string,
	secrets: string[],
): { text: string; changed: boolean } {
	if (secrets.length === 0) return { text, changed: false };
	let out = text;
	let changed = false;
	for (const secret of secrets) {
		if (!out.includes(secret)) continue;
		out = out.split(secret).join(REDACTED);
		changed = true;
	}
	return { text: out, changed };
}
