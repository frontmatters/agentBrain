#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-orphans.sh — report NOTES that hang loose in the knowledge graph.
#
# On-demand report (NOT wired into doctor): surfaces orphans as linking
# opportunities, not as failures. The vault is tags-first by design
# (check-learnings-structure keeps learnings flat, "categorize with tags"),
# so links are a bonus graph layer — an orphan here means "not yet woven in",
# not "broken".
#
# Rule (the "no orphan unless a root" model the graph should satisfy):
#   A note is an ORPHAN when it is NOT a root AND has no incoming [[wiki-link]].
#   A ROOT is an intentional entry point and never counts as an orphan:
#     - basename index.md / README.md / patterns.md, OR
#     - frontmatter `root: true` (also `moc: true` / `entry: true`).
#   Escape hatch: frontmatter `standalone: true` marks a deliberate leaf fact
#   (a self-contained note nothing needs to link to) — excluded from the report.
#   `hidden: true` notes are excluded too (already out of listings).
#
# Scope: the CURATED knowledge layer only — archival/machine-generated/mirror
# folders (archive, sessions, legacy, extracted, addons, skills, ...) are
# legitimately unlinked and never reported.
#
# Usage:
#   bash scripts/check-orphans.sh                 # count + per-folder breakdown
#   bash scripts/check-orphans.sh --list          # also print each orphan path
#   bash scripts/check-orphans.sh --unreachable   # stricter: unreachable from ANY root (transitive)
#   bash scripts/check-orphans.sh --json          # structured output
#   bash scripts/check-orphans.sh local/projects  # scope to given folder(s)
#
# Always exits 0 — this is a report, not a gate.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -d local ]; then
	echo "check-orphans: no local/ — nothing to report (PASS)"
	exit 0
fi

export ORPHAN_LIST=0 ORPHAN_MODE=incoming ORPHAN_JSON=0
SCOPE=()
for arg in "$@"; do
	case "$arg" in
		--list) ORPHAN_LIST=1 ;;
		--unreachable) ORPHAN_MODE=unreachable ;;
		--json) ORPHAN_JSON=1 ;;
		--help|-h) grep '^#' "$0" | sed '1d;s/^# \{0,1\}//'; exit 0 ;;
		--*) echo "check-orphans: unknown flag $arg" >&2; exit 2 ;;
		*) SCOPE+=("$arg") ;;
	esac
done
export ORPHAN_SCOPE="${SCOPE[*]:-}"

node <<'NODE'
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve("local");
const LIST = process.env.ORPHAN_LIST === "1";
const JSON_OUT = process.env.ORPHAN_JSON === "1";
const MODE = process.env.ORPHAN_MODE || "incoming";
const scopeArg = (process.env.ORPHAN_SCOPE || "").trim();

// Curated layer only. Everything else is legitimately unlinked.
const CURATED = new Set([
	"learnings", "projects", "preferences", "troubleshooting", "specs", "tools",
]);
const EXCLUDE_SUBPATH = /\/extracted\//; // machine-generated auto-extraction
const SKIP_DIRS = new Set([
	".git", ".trash", "quarantine", "graphify-out", ".obsidian", "node_modules",
]);

// Symlink-aware walk (local/ and its children can be symlinks — see
// vault-walkers-must-follow-local-symlink).
function walk(dir, out = [], seen = new Set()) {
	let real;
	try { real = fs.realpathSync(dir); } catch { return out; }
	if (seen.has(real)) return out;
	seen.add(real);
	let entries;
	try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
	for (const e of entries) {
		if (e.name.startsWith(".")) continue;
		const full = path.join(dir, e.name);
		let isDir = e.isDirectory();
		if (!isDir && e.isSymbolicLink()) {
			try { isDir = fs.statSync(full).isDirectory(); } catch { continue; }
		}
		if (isDir) {
			if (SKIP_DIRS.has(e.name)) continue;
			walk(full, out, seen);
		} else if (e.name.endsWith(".md")) {
			out.push(full);
		}
	}
	return out;
}

function inScope(file) {
	const rel = path.relative(ROOT, file);
	const top = rel.split(path.sep)[0];
	if (EXCLUDE_SUBPATH.test("/" + rel.split(path.sep).join("/"))) return false;
	if (scopeArg) {
		// scope given as `local/<folder>` paths — match by folder segment
		return scopeArg.split(/\s+/).some((s) => {
			const seg = s.replace(/^local\/?/, "").replace(/\/$/, "");
			return seg === "" ? CURATED.has(top) : rel === seg || rel.startsWith(seg + path.sep);
		});
	}
	return CURATED.has(top);
}

// allFiles = every note in the vault; files = the curated orphan CANDIDATES.
// The link index is built over allFiles, because an incoming link from a
// daily-note / session / research note still means "something points here" —
// counting only curated sources would over-report orphans.
const allFiles = walk(ROOT);
const files = allFiles.filter(inScope);

function frontmatter(text) {
	const m = text.match(/^---\n([\s\S]*?)\n---/);
	return m ? m[1] : "";
}
function stems(file) {
	// basename (Obsidian [[name]] semantics) + exact vault-relative path.
	return [
		path.basename(file, ".md").toLowerCase(),
		path.relative(ROOT, file).replace(/\.md$/, "").toLowerCase(),
	];
}

// Resolve [[targets]] against a stem index (first note claiming a stem wins).
const byStem = new Map();
for (const f of allFiles) for (const s of stems(f)) if (!byStem.has(s)) byStem.set(s, f);
// A folder link `[[some-project]]` resolves to that folder's index.md — not to
// an arbitrary first file that happens to live in a folder of that name.
for (const f of allFiles) {
	if (path.basename(f).toLowerCase() === "index.md") {
		byStem.set(path.basename(path.dirname(f)).toLowerCase(), f);
	}
}

const fm = {}, outLinks = {};
const linkRe = /\[\[([^\]|#]+)/g;
for (const f of allFiles) {
	const t = fs.readFileSync(f, "utf8");
	fm[f] = frontmatter(t);
	const outs = new Set();
	for (const m of t.matchAll(linkRe)) {
		const tgt = m[1].trim().toLowerCase();
		if (byStem.has(tgt)) outs.add(byStem.get(tgt));
	}
	outLinks[f] = [...outs];
}

const inCount = new Map(allFiles.map((f) => [f, 0]));
for (const f of allFiles) for (const t of outLinks[f]) inCount.set(t, (inCount.get(t) || 0) + 1);

const flag = (f, re) => re.test("\n" + fm[f]);
const isRoot = (f) => {
	const b = path.basename(f).toLowerCase();
	// index.md / README.md / patterns.md, plus category MOCs like CSS-index.md,
	// Tauri-index.md — all intentional entry points, not orphans.
	if (b === "index.md" || b === "readme.md" || b === "patterns.md" || b.endsWith("-index.md")) return true;
	return flag(f, /\n(root|moc|entry):\s*true/i);
};
const isStandalone = (f) => flag(f, /\n(standalone):\s*true/i);
const isHidden = (f) => flag(f, /\nhidden:\s*true/i);

const candidates = files.filter((f) => !isRoot(f) && !isStandalone(f) && !isHidden(f));

let orphans;
if (MODE === "unreachable") {
	// Reachable from any root by following outgoing links (a table-of-contents walk).
	const roots = files.filter(isRoot);
	const reach = new Set(roots);
	const q = [...roots];
	while (q.length) {
		const c = q.pop();
		for (const t of outLinks[c] || []) if (!reach.has(t)) { reach.add(t); q.push(t); }
	}
	orphans = candidates.filter((f) => !reach.has(f));
} else {
	orphans = candidates.filter((f) => (inCount.get(f) || 0) === 0);
}

const rels = orphans.map((f) => path.relative(ROOT, f)).sort();
const byFolder = {};
for (const r of rels) { const t = r.split(path.sep)[0]; byFolder[t] = (byFolder[t] || 0) + 1; }

if (JSON_OUT) {
	console.log(JSON.stringify({
		mode: MODE, curatedNotes: files.length,
		roots: files.filter(isRoot).length, orphans: rels.length,
		byFolder, notes: rels,
	}, null, 2));
} else {
	const label = MODE === "unreachable" ? "unreachable from any root" : "no incoming link, not a root";
	console.log(`check-orphans: ${rels.length} orphan(s) — ${label}`);
	console.log(`  scanned ${files.length} curated note(s), ${files.filter(isRoot).length} root(s)`);
	for (const [k, v] of Object.entries(byFolder).sort((a, b) => b[1] - a[1])) {
		console.log(`    ${String(v).padStart(4)}  ${k}`);
	}
	if (LIST) { console.log(""); for (const r of rels) console.log("  " + r); }
	else if (rels.length) console.log("  (--list for paths; a note is a root — never an orphan — when named index.md/README.md/*-index.md/patterns.md or with `root: true`; mark deliberate leaf facts `standalone: true`)");
}
NODE
