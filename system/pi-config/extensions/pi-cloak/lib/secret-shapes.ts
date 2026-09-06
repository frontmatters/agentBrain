// secret-shapes.ts — content-only secret detection for `bash` tool output.
//
// Why this exists (and why env-secrets.ts alone is NOT enough): a `bash`
// tool call runs in its own child process. Anything `export`-ed inside it
// is invisible to Pi's own process.env once the call returns \u2014 env vars
// only flow parent-to-child, never child-to-parent. So exact-matching
// against Pi's own process.env (env-secrets.ts) can only catch secrets that
// were ALREADY in Pi's host environment before the call; it structurally
// cannot catch a credential-helper function that fetches+prints a fresh
// secret bare, inside the bash subprocess itself \u2014 which is exactly the
// leak this module is built to close. Verified empirically: exporting a var
// in one bash tool call is gone in the next, and is never visible to the
// Node process hosting the extension.
//
// This module instead recognizes secret *shapes* directly in the output
// text, regardless of which process produced it:
//   1. A line that, once trimmed, is ENTIRELY a long hex/base62 string and
//      nothing else \u2014 the exact shape `security find-generic-password -w`
//      (or similar) prints when its raw stdout is not captured. Deliberately
//      narrow (whole-line only) to avoid flagging a SHA embedded in a
//      sentence or `git log --oneline` output (SHA + message on the same
//      line doesn't match "entirely").
//   2. Known token-prefix formats (GitHub, OpenAI, Slack, AWS, ...) anywhere
//      in the text, since these are unambiguous by construction.
//
// Trade-off, stated explicitly: a bare `git rev-parse HEAD` (a lone 40-char
// hex SHA on its own line) WILL be redacted by rule 1. Accepted \u2014 a
// falsely-redacted commit SHA costs nothing; a missed credential costs a lot.

const REDACTED = "***REDACTED-SECRET-SHAPE***";

// A line that, once trimmed, is ENTIRELY a long hex string and nothing else.
// Hex-only (not base62-with-separators): kebab-case identifiers — project/
// skill/package/addon dir names routinely `ls`'d one-per-line — would
// otherwise match (e.g. `agentbrain-changelog-convention` is 34 chars of
// [A-Za-z0-9-]). The original Gitea token leak this rule was built for was
// 40 hex chars, so hex-only still catches it. Base62 tokens without a known
// prefix are rare in practice; the ones with prefixes (ghp_/sk-/xox/...) are
// covered by KNOWN_TOKEN_PATTERNS below.
const BARE_LONG_TOKEN_LINE = /^[0-9a-f]{32,64}$/i;

// Canonical UUID (v1-v5), e.g. what `uuid5-gen.sh` prints for every note ID
// in this vault. Structurally indistinguishable from BARE_LONG_TOKEN_LINE
// (36 chars, hex + hyphens) but is NEVER a secret — it's a public,
// deterministic identifier. Explicit exception, found via a real false
// positive: a plain `uuid5-gen.sh` call got its own output redacted.
const UUID_SHAPE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const KNOWN_TOKEN_PATTERNS: RegExp[] = [
	/gh[pousr]_[A-Za-z0-9]{20,}/g, // GitHub PAT / OAuth / App / Server / Refresh tokens
	/github_pat_[A-Za-z0-9_]{20,}/g, // GitHub fine-grained PAT
	/sk-(?:proj-)?[A-Za-z0-9]{20,}/g, // OpenAI-style secret keys
	/xox[baprs]-[A-Za-z0-9-]{10,}/g, // Slack tokens
	/AKIA[0-9A-Z]{16}/g, // AWS access key id
	/AIza[0-9A-Za-z_-]{35}/g, // Google API key
	// Generic 32-64 char hex string, ANYWHERE in the text (not just whole-line).
	// Closes a real gap the whole-line rule misses: a token embedded inside a
	// larger string, e.g. `http://user:<token>@host/...` in a git remote URL
	// (this exact shape leaked in this session). Same accepted trade-off as
	// the whole-line rule: a full 40-char git SHA appearing inline will also
	// get redacted — low-cost false positive vs. a missed credential.
	/\b[0-9a-f]{32,64}\b/gi,
];

export function redactSecretShapes(text: string): { text: string; changed: boolean } {
	let changed = false;
	let out = text;

	for (const pattern of KNOWN_TOKEN_PATTERNS) {
		if (pattern.test(out)) {
			pattern.lastIndex = 0;
			out = out.replace(pattern, REDACTED);
			changed = true;
		}
	}

	const lines = out.split(/\r?\n/).map((line) => {
		const trimmed = line.trim();
		if (UUID_SHAPE.test(trimmed)) return line;
		if (BARE_LONG_TOKEN_LINE.test(trimmed) && trimmed.length >= 20) {
			changed = true;
			return line.replace(trimmed, REDACTED);
		}
		return line;
	});

	return { text: changed ? lines.join(out.includes("\r\n") ? "\r\n" : "\n") : out, changed };
}
