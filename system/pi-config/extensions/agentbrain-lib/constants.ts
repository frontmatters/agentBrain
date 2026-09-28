export const MAX_FILE_BYTES = 50_000;
export const MAX_PROJECT_BYTES = 80_000;

// Canonical physical paths. `local/` is a compatibility alias used by UUID/context
// logic; agents must be shown the real `vault/` paths so they can read them.
export const CORE_FILES = [
	"vault/learnings/patterns.md",
	"vault/learnings/troubleshooting.md",
	"system/rules.md",
	"system/agent-config/shared.md",
	"system/skills.md",
	"system/lifecycle.md",
];

export const PROJECT_FILES = [
	"index.md",
	"prd.md",
	"decisions.md",
	"deploy.md",
	"changelog.md",
	"context.md",
];

export const SEARCH_EXCLUDE_DIRS = new Set([
	".git",
	".obsidian",
	"node_modules",
	"sessions",
	"daily-notes",
	"integrations",
]);
