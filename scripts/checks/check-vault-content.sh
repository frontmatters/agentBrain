#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-vault-content.sh — validate the KNOWLEDGE layer (local/), not just the framework.
#
# Closes the gap documented in "the doctor guards the machine, not the knowledge":
# check-frontmatter/check-links exempt local/, so real notes go unvalidated. This check
# validates local/ notes directly:
#   1. frontmatter present (starts with ---)
#   2. id: present
#   3. id matches uuid5-gen.sh for the note's vault-relative path
#   4. [[wiki-links]] resolve to an existing note (by basename, Obsidian semantics)
#
# Exit policy:
#   default      — fail on frontmatter/id issues (hard schuld), warn on dead wiki-links
#                  (dead-links are content-debt, often resolved by migrations/renames;
#                   keeping them as warn means doctor stays green on transient state).
#   --strict     — fail on ANY finding, including dead wiki-links.
#   --json       — emit structured findings as JSON (for the self-improving-loop
#                  framework). Always exits 0 unless the detector itself broke
#                  (self-test fail, missing brain.json). --strict is ignored in
#                  --json mode — severity travels with each finding; the framework
#                  decides what to do with it.
#
# Scope defaults to all of local/; pass dirs to scope.
#   bash scripts/checks/check-vault-content.sh                      # whole local/
#   bash scripts/checks/check-vault-content.sh local/flux local/learnings   # scoped
#   bash scripts/checks/check-vault-content.sh --strict             # hard-fail on everything
#   bash scripts/checks/check-vault-content.sh --json               # structured output for the loop
#
# Lives in local_checks (doctor full local run); --ci skips it, so CI stays public-safe.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"

if [ ! -d local ]; then
	echo "check-vault-content: no vault/ — skip (PASS)"
	exit 0
fi

# Parse --strict, --json, and scope dirs
STRICT=0
JSON=0
SCOPE=()
for arg in "$@"; do
	case "$arg" in
		--strict) STRICT=1 ;;
		--json) JSON=1 ;;
		*) SCOPE+=("$arg") ;;
	esac
done
[ ${#SCOPE[@]} -eq 0 ] && SCOPE=("vault")
export STRICT JSON

python3 - "${SCOPE[@]}" <<'PY'
import json, os, sys, uuid, pathlib, re, subprocess
from datetime import datetime, timezone

VAULT = pathlib.Path.cwd()  # bash cd'd to ROOT_DIR; absolute so relative_to works
NS = uuid.UUID(json.loads((VAULT / "brain.json").read_text())["namespace"])

# Third-party / generated dirs whose *.md are docs shipped by a dependency (numpy
# LICENSE.md, package templates, ...), never vault notes. Prune them like
# check-frontmatter skips node_modules/ — otherwise a single `.venv` under an addon
# floods the scan with hundreds of no-frontmatter false positives.
_PRUNE_DIRS = {".git", ".venv", "venv", "env", "site-packages", "node_modules", "__pycache__",
               ".build"}   # SwiftPM: dependency checkouts, same shape as node_modules

def walk_md(root):
    """Yield all .md files under root, following symlinks (vault/ is itself a
    symlink to the live install, so followlinks must stay on). Prunes
    third-party/generated dirs (see _PRUNE_DIRS) in-place.

    Also prunes *internal* directory symlinks — a dir symlink whose target
    resolves back inside root (e.g. a stray `vault/memory -> memories`). Left
    followed, os.walk re-yields the entire aliased subtree under a second logical
    path, so every note gets its path->id computed twice and the alias route
    floods the scan with phantom id-mismatches. The real directory is still
    walked under its canonical path; only the duplicate alias route is dropped.
    External dir symlinks (target outside root) stay followed."""
    root_real = os.path.realpath(root)
    for dirpath, dirnames, filenames in os.walk(root, followlinks=True):
        kept = []
        for d in dirnames:
            if d in _PRUNE_DIRS:
                continue
            full = os.path.join(dirpath, d)
            if os.path.islink(full):
                tgt = os.path.realpath(full)
                if tgt == root_real or tgt.startswith(root_real + os.sep):
                    continue  # internal alias -> canonical subtree walked elsewhere
            kept.append(d)
        dirnames[:] = kept
        for fn in filenames:
            if fn.endswith(".md"):
                yield pathlib.Path(dirpath) / fn

def expected_id(rel_no_ext: str) -> str:
    # Ids hash the local/ spelling; vault/ is the link's name on disk (uuid5-gen.sh folds the same way).
    rel_no_ext = re.sub(r"^vault(/|$)", r"local\1", rel_no_ext)
    return str(uuid.uuid5(NS, f"agentBrain/{rel_no_ext}"))

# --- Self-test: our inline formula MUST match the canonical uuid5-gen.sh ---
# Failure goes to stderr so --json mode keeps stdout clean (valid JSON or nothing).
probe = "vault/__selftest_probe__"   # uuid5-gen.sh and expected_id both fold this to local/
mine = expected_id(probe)
out = subprocess.run(["bash", "scripts/uuid5-gen.sh", probe],
                     capture_output=True, text=True)
canonical = out.stdout.strip()
if mine != canonical:
    print("FAIL self-test: inline UUID5 formula drifted from uuid5-gen.sh", file=sys.stderr)
    print(f"  inline={mine}  canonical={canonical}", file=sys.stderr)
    sys.exit(1)

scope = sys.argv[1:]

# Build basename index of ALL notes (public + local) for wiki-link resolution.
# local/ is a symlink to the live install -> must follow symlinks to see real content.
#
# In addition to basename, also index the frontmatter `name:` field where present.
# This lets memory-style notes (e.g. local/memories/feedback_X.md with
# `name: kebab-X`) resolve via `[[kebab-X]]` — important after the 2026-05-24
# claude-memory migration moved auto-memory files into agentBrain with their
# original Claude-side filenames but canonical slugs in the `name:` field.
_NAME_RE = re.compile(r"^name:\s*(\S+)\s*$", re.M)

def _extract_name(fpath):
    try:
        text = fpath.read_text(encoding="utf-8", errors="replace")
        if not text.startswith("---"):
            return None
        end = text.find("\n---", 3)
        if end == -1:
            return None
        m = _NAME_RE.search(text[:end])
        return m.group(1) if m else None
    except Exception:
        return None

index = set()
for _p in walk_md(VAULT):
    index.add(_p.stem)
    # agentBrain references a project (and similar folder-notes) by its folder
    # slug: [[<slug>]] points at the <slug>/index.md note. The note's own basename
    # is "index", so also index the parent dir name for index files.
    if _p.stem == "index":
        index.add(_p.parent.name)
    _n = _extract_name(_p)
    if _n:
        index.add(_n)

import os as _os
STRICT = _os.environ.get("STRICT", "0") == "1"
JSON = _os.environ.get("JSON", "0") == "1"
findings = []  # structured; severity travels with each, format chosen at emit time
checked = 0
ID_RE = re.compile(r"^id:\s*(\S+)\s*$", re.M)
# Top-level YAML key at the start of a frontmatter line (no indentation).
TOP_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):")
# Claude auto-memory mirrors wrap fields under `metadata:`. Tolerate that vorm
# so externally-managed schemas (Claude auto-memory, future client mirrors) pass
# id-presence checks. uuid5-parity is not enforced for nested ids — they come
# from external id-strategies and aren't computed from the vault-relative path.
METADATA_ID_RE = re.compile(r"^metadata:\s*\n(?:\s+\S+.*\n)*?\s+id:\s*(\S+)\s*$", re.M)
LINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
FENCED_RE = re.compile(r"```.*?```", re.S)
INLINE_RE = re.compile(r"`[^`]*`")

# Suggested actions per finding-kind — hint for an agent acting on the finding.
SUGGESTED = {
    "no-frontmatter": "add YAML frontmatter starting with ---",
    "unterminated-frontmatter": "close frontmatter with --- on its own line",
    "missing-id": "add `id:` field with `bash scripts/uuid5-gen.sh <path-no-ext>` output",
    "id-mismatch": "regenerate id with `bash scripts/uuid5-gen.sh <path-no-ext>`",
    "dead-link": "rename or remove the link target, or restore the missing note",
}

def add_finding(kind: str, severity: str, file: str, message: str, extra: str = ""):
    fid = f"check-vault-content:{kind}:{file}"
    if extra:
        fid += f":{extra}"
    findings.append({
        "id": fid,
        "severity": severity,
        "file": file,
        "kind": kind,
        "message": message,
        "suggested_action": SUGGESTED.get(kind, ""),
    })

def strip_code(s: str) -> str:
    # wiki-links inside code blocks / inline code are not links (e.g. grep '[[:space:]]')
    return INLINE_RE.sub("", FENCED_RE.sub("", s))

# SKILL.md and addon manifest.md use their own schemas (no agentBrain `id:`).
# Same exemption as scripts/checks/check-frontmatter.sh — don't force note-schema on them.
# local/quarantine/** is content under sanitization-watch — out of scope here
# (see local/quarantine/README.md and check-vault-private.sh).
# local/sessions/session-journal.md and local/sessions/archive/** are machine-generated
# by the session-continuity Pi extension; their `id:` field uses the extension's own
# id-strategy, not uuid5-gen(path). Exempt from id-validation (they're ephemeral
# session logs, not knowledge that needs the note-schema invariant).
EXEMPT_FILE = pathlib.Path("scripts/lib/exempt-schema-paths.txt")

def load_exempt_patterns() -> list:
    """Note-schema exemptions, shared with system/skills/wash-vault.

    Single source of truth: the detector and the fixer used to keep separate
    hand-copied lists that drifted in both directions. Reading one file makes
    that class of bug structural rather than a thing to remember.
    """
    if not EXEMPT_FILE.is_file():
        print(f"check-vault-content: missing {EXEMPT_FILE}", file=sys.stderr)
        raise SystemExit(1)
    pats = []
    for line in EXEMPT_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            pats.append(line)
    if not pats:
        print(f"check-vault-content: {EXEMPT_FILE} has no patterns", file=sys.stderr)
        raise SystemExit(1)
    return pats

EXEMPT_PATTERNS = load_exempt_patterns()

def is_exempt(rel_path: str) -> bool:
    import fnmatch
    return any(fnmatch.fnmatch(rel_path, pat) for pat in EXEMPT_PATTERNS)

for root in scope:
    for f in sorted(walk_md(VAULT / root)):
        rel_with_ext = f.relative_to(VAULT).as_posix()
        # The exempt list and every id are spelled local/; vault/ is the link's name on disk.
        ident_with_ext = re.sub(r"^vault/", "local/", rel_with_ext)
        if is_exempt(ident_with_ext):
            continue
        checked += 1
        rel = f.relative_to(VAULT).with_suffix("").as_posix()
        text = f.read_text(encoding="utf-8", errors="replace")
        # 1. frontmatter
        if not text.startswith("---"):
            add_finding("no-frontmatter", "error", f"{rel}.md", "no frontmatter")
            continue
        end = text.find("\n---", 3)
        if end == -1:
            add_finding("unterminated-frontmatter", "error", f"{rel}.md", "unterminated frontmatter")
            continue
        fm = text[:end]
        # 2. frontmatter must be well-formed: no repeated top-level key.
        # The fixer (system/skills/wash-vault) writes into this block, and a
        # bug there once appended a second `id:` next to an empty one. The
        # detector accepted it, because it only asked whether *an* id was
        # present and correct. A detector that cannot see the damage its
        # paired fixer produces is blind exactly where it matters.
        seen_keys = {}
        for line in fm.split("\n")[1:]:
            km = TOP_KEY_RE.match(line)
            if km:
                seen_keys[km.group(1)] = seen_keys.get(km.group(1), 0) + 1
        dupes = sorted(k for k, n in seen_keys.items() if n > 1)
        if dupes:
            add_finding("duplicate-frontmatter-key", "error", f"{rel}.md",
                        "repeated key(s) in frontmatter: " + ", ".join(dupes))
            continue
        # 3 + 4. id present and correct
        m = ID_RE.search(fm)
        nested = False
        if not m:
            m = METADATA_ID_RE.search(fm)
            nested = bool(m)
        if not m:
            add_finding("missing-id", "error", f"{rel}.md", "missing id")
        elif not nested and m.group(1) != expected_id(rel):
            add_finding("id-mismatch", "error", f"{rel}.md",
                        f"id mismatch (got {m.group(1)}, want {expected_id(rel)})")
        # 4. wiki-links resolve (ignore links inside code blocks / inline code)
        # Transitional / archief buckets: wiki-links daarbinnen niet valideren.
        # - local/legacy/         = point-in-time archief van ClaudeBrain (frozen)
        # - local/learnings/extracted/ = pending-review auto-extracts, refs by H1-title
        if ident_with_ext.startswith(("local/legacy/", "local/learnings/extracted/")):
            continue
        # Wiki-link scan with forward-ref marker support.
        # Two ways to mark a link as an intentional forward-ref (not a dead-link):
        #   1. Prefix syntax: `[[forward:X]]` — target itself starts with "forward:"
        #   2. Justification comment on same line: `[[X]] <!-- forward: reason -->`
        # Forward-marked links are silently accepted (per agentBrain "link liberally" rule).
        # Unmarked unresolved links remain warnings.
        for line in strip_code(text).split("\n"):
            has_forward_comment = "<!-- forward:" in line
            for link in LINK_RE.findall(line):
                target = link.split("|")[0].split("#")[0].strip()
                # Code/JSON fragments like [['Date',…]] or [["file","x.json"]] get matched
                # by the bracket regex but are not wiki-links — a note name never starts
                # with a quote. Skip them so they don't show up as dead links.
                if target[:1] in ("'", '"'):
                    continue
                target = target.rsplit("/", 1)[-1]  # allow path-style links
                target = target.rstrip("\\")  # strip markdown-table escape
                # A link may carry the file extension ([[note.md]], [[x/README.md]],
                # [[foo.html]]); the index holds extension-less basenames, so drop a
                # known document extension before matching.
                for _ext in (".md", ".markdown", ".html", ".htm"):
                    if target.endswith(_ext):
                        target = target[: -len(_ext)]
                        break
                if target.startswith("forward:"):
                    continue  # explicit prefix marker
                if has_forward_comment and target not in index:
                    continue  # same-line justification comment
                if target and target not in index:
                    add_finding("dead-link", "warning", f"{rel}.md",
                                f"dead wiki-link [[{link}]]", extra=target)

# Output mode: JSON for the self-improving-loop framework, human-readable otherwise.
if JSON:
    out = {
        "detector": "check-vault-content",
        "run_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "checked": checked,
        "findings": findings,
    }
    print(json.dumps(out, indent=2))
    sys.exit(0)

# Human report (unchanged from pre-JSON-mode behaviour)
hard = [f for f in findings if f["severity"] == "error"]
warn = [f for f in findings if f["severity"] == "warning"]

if hard:
    print(f"check-vault-content: {len(hard)} hard issue(s) in {checked} note(s):")
    for f in hard[:200]:
        print(f"  ✗ {f['file']} — {f['message']}")
    if len(hard) > 200:
        print(f"  … +{len(hard)-200} more")
if warn:
    label = "issue" if STRICT else "warning"
    print(f"check-vault-content: {len(warn)} dead-link {label}(s):")
    for f in warn[:50]:
        print(f"  ⚠ {f['file']} — {f['message']}")
    if len(warn) > 50:
        print(f"  … +{len(warn)-50} more")

if hard or (STRICT and warn):
    sys.exit(1)
print(f"check-vault-content: ✅ {checked} note(s) valid"
      + (f" ({len(warn)} dead-link warning(s))" if warn else ""))
PY
