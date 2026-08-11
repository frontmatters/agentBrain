import { writeFile, mkdir, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { brainRoot, localPath } from "./brain";
import { noteId } from "./uuid5";

// Lowercase kebab slug; strips every non-alphanumeric (so "../x" or "a/b" can't traverse).
// This is the primary filename-traversal guard; localPath is the backstop. (Symlinks under
// local/ are not realpath-resolved — acceptable for a local single-user tool.)
function slugify(s: string): string {
  return s.toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "note";
}

async function namespace(): Promise<string> {
  return JSON.parse(await readFile(join(brainRoot(), "brain.json"), "utf8")).namespace as string;
}

const SECRET_RX = /\b(api[_-]?key|secret|token|password|passwd|bearer|private[_-]?key|sk-[a-z0-9]{8,})\b/i;

function stripCodeFences(s: string): string {
  return s.replace(/```[\s\S]*?```/g, "");
}

function assertNoSecret(...texts: string[]): void {
  for (const t of texts) {
    if (SECRET_RX.test(stripCodeFences(t))) throw new Error("Refusing to write: content looks like it contains a secret.");
  }
}

// Relative path of the incognito flag inside the vault. CANONICAL DEFINITION lives in
// system/addons/incognito/is-incognito.sh — keep these two in sync if the path ever moves.
// (Cross-language: bash and TS can't share a literal, so this is the deliberate second copy.)
const INCOGNITO_FLAG = ["local", "sessions", ".incognito"] as const;

// Incognito guard for the MCP write path. The PreToolUse hook only intercepts
// Write/Edit/MultiEdit; brain_save_learning / brain_project_update reach the vault
// through here instead, so the flag must be enforced at the write point too. Checked
// against brainRoot() so it tracks the active vault (flips with `brain use dev|live`)
// and resolves the same vault as the bash CLI (see brainRoot()'s AGENTBRAIN_HOME note).
function assertNotIncognito(): void {
  if (existsSync(join(brainRoot(), ...INCOGNITO_FLAG))) {
    throw new Error("Refusing to write: agentBrain is in incognito mode (read-only this session). Turn it off with `/incognito off` to persist knowledge.");
  }
}

function today(): string { return new Date().toISOString().slice(0, 10); }

// Save a learning to local/learnings/<slug>.md. Returns the brain-relative path.
export async function saveLearning(title: string, body: string, tags: string[] = []): Promise<string> {
  assertNotIncognito();
  assertNoSecret(title, body);
  const slug = slugify(title);
  const rel = `local/learnings/${slug}.md`;
  const dest = localPath("learnings", `${slug}.md`);
  if (existsSync(dest)) throw new Error(`Already exists: ${rel}`);
  const id = noteId(await namespace(), `local/learnings/${slug}`);
  const tagList = (tags.length ? tags : ["session"]).join(", ");
  const fm =
    `---\ndate: ${today()}\ntype: learning\ntags: [${tagList}]\nconfidence: low\nsource: session\nid: ${id}\n---\n\n# ${title}\n\n${body}\n`;
  await mkdir(dirname(dest), { recursive: true });
  await writeFile(dest, fm);
  return rel;
}

// Create/update a project note. No section -> index.md; named section -> <section-slug>.md.
export async function projectUpdate(name: string, section: string | undefined, body: string): Promise<string> {
  assertNotIncognito();
  assertNoSecret(name, section ?? "", body);
  const proj = slugify(name);
  const file = section ? `${slugify(section)}.md` : "index.md";
  const rel = `local/projects/${proj}/${file}`;
  const dest = localPath("projects", proj, file);
  const id = noteId(await namespace(), `local/projects/${proj}/${file.replace(/\.md$/, "")}`);
  const fm =
    `---\ndate: ${today()}\ntype: project\ntags: [${proj}]\nsource: session\nid: ${id}\n---\n\n# ${section ?? name}\n\n${body}\n`;
  await mkdir(dirname(dest), { recursive: true });
  await writeFile(dest, fm);
  return rel;
}
