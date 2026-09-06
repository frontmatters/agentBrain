#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-nda.sh — refuse confidential owner material outside its space.
#
# The spaces model says owner work lives in local/spaces/<slug>/, versioned to its
# own remote. Nothing enforced that. This gate does, at the commit boundary.
#
# Markers are derived from the passports themselves (code-roots, aliases, owner),
# so adding a space extends the gate automatically and no owner name ever has to
# be written into system/. Passports live in local/, which is private.
#
# What it flags: the presence of an owner NAME, which is not the same as the file
# being misplaced. rules.md decides placement by ownership and reach, not by topic —
# reusable knowledge stays in the shared vault and refers to the owner by its neutral
# space slug. This gate finds the name; you decide whether to rename or to move.
#   - a staged path containing a marker  (e.g. a cache directory named after a repo)
#   - staged content containing a marker (e.g. a report that embedded raw rows)
# What it allows:
#   - anything under local/spaces/       (that is where it belongs)
#   - markers shorter than MIN_MARKER    (too generic; would fire on ordinary words)
#   - paths listed in local/.nda-allow   (one path prefix per line, with a reason)
#
# Scope: both layers. The vault must not hold owner material outside a space, and
# system/ — which ships — must not hold an owner name at all. check-space-boundary
# covers only the passport's `owner` field; markers here come from every field.
#
# Where it runs:
#   doctor            --system  (the shipping layer must be clean: this is a gate)
#   pre-commit hooks  --staged  (blocks what is NEW, in both repos)
#   by hand           no flags  (full vault report; expected to list the known
#                                backlog, so it is NOT wired into doctor — a check
#                                that is permanently red teaches you to ignore it)
#
# Usage: check-nda.sh [--staged] [--system] [--list]
#          --staged  only what git has staged (fast; used by the commit hooks)
#          --system  scan system/ + scripts/ instead of the vault
#          --list    print every file, not just the per-kind counts. The summary
#                    tells you how big the backlog is; working through it needs
#                    the paths.
set -uo pipefail

BRAIN="${BRAIN_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
VAULT="$BRAIN/vault"
STAGED=0; SYSTEM=0; LIST=0
for a in "$@"; do
  case "$a" in
    --staged) STAGED=1 ;;
    --system) SYSTEM=1 ;;
    --list)   LIST=1 ;;
    -h|--help) sed -n '2,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "check-nda: unknown option: $a (try --help)" >&2; exit 2 ;;
  esac
done
MIN_MARKER=4

[ -d "$VAULT/spaces" ] || { echo "check-nda: no spaces/ — nothing to enforce"; exit 0; }

python3 - "$VAULT" "$STAGED" "$MIN_MARKER" "$SYSTEM" "$BRAIN" "$LIST" <<'PY'
import json, os, pathlib, re, subprocess, sys

vault, staged_only, min_marker = pathlib.Path(sys.argv[1]), sys.argv[2] == "1", int(sys.argv[3])
scan_system = len(sys.argv) > 4 and sys.argv[4] == "1"
brain = pathlib.Path(sys.argv[5]) if len(sys.argv) > 5 else vault.parent
list_all = len(sys.argv) > 6 and sys.argv[6] == "1"
home = str(pathlib.Path.home())

# --- markers from the passports ------------------------------------------------
by_space = {}          # marker -> slug
handle = {}            # slug   -> opaque handle safe to print
for idx in (vault/"spaces").glob("*/index.md"):
    try:
        fm = idx.read_text(errors="replace").split("---")[1]
    except (OSError, IndexError):
        continue
    def field(k):
        m = re.search(rf"^{k}:\s*(.+)$", fm, re.M)
        return m.group(1).strip() if m else ""
    slug = field("slug") or idx.parent.name
    # Test fixtures use the __name__ form (__astest__, __rntest-owner__,
    # __exhostile__). Their owner is invented and appears in the test files
    # themselves, so a fixture left behind, or merely present while doctor
    # runs, turns scripts/tests/ into "owner material". Not a real space.
    if slug.startswith("__") and slug.endswith("__"):
        continue
    # The handle used in REPORTS. A slug is free text, and three of the spaces
    # on this machine have one that is the owner name itself, so printing the
    # slug leaks exactly what withholding the marker was meant to protect.
    # space-id is a UUID and always safe; fall back to the slug only when a
    # passport carries no id at all.
    sid = field("space-id").strip('"')
    handle[slug] = ("sp-" + sid.replace("-", "")[:8].lower()) if sid else slug
    cand = [a.strip().strip('"').strip("'") for a in field("aliases").strip("[]").split(",")]
    cand.append(field("owner").strip('"'))
    for r in field("code-roots").strip("[]").split(","):
        cand.append(r.strip().strip('"').rstrip("/").split("/")[-1])
    for c in cand:
        if len(c) >= min_marker and not c.startswith("<"):
            by_space[c] = slug
markers = set(by_space)
if not markers:
    print("check-nda: no usable markers in passports — nothing to enforce")
    sys.exit(0)

# --- allowlist -----------------------------------------------------------------
allow = []
af = vault/".nda-allow"
if af.exists():
    for line in af.read_text(errors="replace").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            allow.append(line)

def allowed(rel):
    if scan_system:
        # system/ ships: nothing there may carry an owner name, so no allowlist
        # beyond the checks that legitimately name the marker sources.
        return rel.startswith(("scripts/checks/check-nda.sh",
                               "scripts/checks/check-space-boundary.sh"))
    return rel.startswith("spaces/") or any(rel.startswith(a) for a in allow)

# --- files to inspect ----------------------------------------------------------
scan_root = brain if scan_system else vault
args = (["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"] if staged_only
        else ["git", "ls-files"])
out = subprocess.run(args, cwd=scan_root, capture_output=True, text=True).stdout
files = [f for f in out.splitlines() if f.strip()]
if scan_system:
    # only the shipping layers; local/ is a symlink git cannot enter anyway
    files = [f for f in files if f.startswith(("system/", "scripts/", "templates/", "docs/"))]

def kind(rel):
    """What sort of material this is — decides how it should be handled."""
    first = rel.split("/", 1)[0]
    if first == "graphify-out":                       return "generated cache"
    if first in ("archive", "quarantine", "legacy"):  return "archive"
    if first in ("events", "sessions", "metrics", "findings", "loops", "update"):
        return "runtime state"
    if first in ("explainers", "exports", "reports"): return "published artefact"
    if first in ("learnings", "projects", "references", "memories", "preferences",
                 "troubleshooting", "specs", "decisions"):
        return "knowledge note"
    if first == "addons":                             return "addon data"
    if first == "analyses":                           return "analysis output"
    return "other"

pats = [(m, re.compile(rf"(?<![A-Za-z0-9]){re.escape(m)}(?![A-Za-z0-9])", re.I)) for m in sorted(markers)]

SKIP_SUFFIX = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf", ".zip", ".gz",
               ".tar", ".mp4", ".mov", ".safetensors", ".gguf", ".ico", ".woff",
               ".woff2", ".ttf", ".otf")

path_hits, content_hits = [], []
for rel in files:
    if allowed(rel):
        continue
    if rel.lower().endswith(SKIP_SUFFIX):
        # binary: path is still checked below, content is not readable text
        for m, pat in pats:
            if pat.search(rel):
                path_hits.append((rel, m)); break
        continue
    for m, pat in pats:
        if pat.search(rel):
            path_hits.append((rel, m)); break
    p = scan_root/rel
    try:
        if p.stat().st_size > 4_000_000:
            continue
        text = p.read_text(errors="replace")
    except OSError:
        continue
    for m, pat in pats:
        if pat.search(text):
            content_hits.append((rel, m)); break

if not path_hits and not content_hits:
    print(f"check-nda: ok ({len(files)} file(s) checked against {len(markers)} marker(s))")
    sys.exit(0)

# --- redaction ------------------------------------------------------------
# This report withholds the marker but used to print the path, and a path like
# projects/<owner>-page-builder-poc carries the name just as plainly. Every
# path printed below is masked against ALL markers, not just the one that
# matched: a content hit can sit in a file whose path names a different owner.
_redact_pats = [(re.compile(re.escape(m), re.I), m) for m in sorted(markers, key=len, reverse=True)]

def safe(rel):
    for pat, m in _redact_pats:
        slug_of = by_space.get(m, "")
        rel = pat.sub("<" + handle.get(slug_of, "owner") + ">", rel)
    return rel

# Group by space candidate and by kind, so the list says what to DO with it.
import collections
grouped = collections.defaultdict(lambda: collections.defaultdict(list))
for where, hits in (("path", path_hits), ("content", content_hits)):
    for rel, m in hits:
        grouped[by_space.get(m, "?")][kind(rel)].append((where, rel))

total = len(path_hits) + len(content_hits)
print(f"check-nda: FAILED — {total} file(s) with owner material outside a space", file=sys.stderr)
for slug in sorted(grouped):
    n = sum(len(v) for v in grouped[slug].values())
    print(f"\n  space candidate: {handle.get(slug, slug)}   ({n} file(s))", file=sys.stderr)
    for k in sorted(grouped[slug], key=lambda k: -len(grouped[slug][k])):
        items = grouped[slug][k]
        dirs = collections.Counter(safe("/".join(r.split("/")[:2])) for _, r in items)
        top = ", ".join(f"{d} ({c})" for d, c in dirs.most_common(3))
        print(f"    {len(items):>4}  {k:<20} {top}", file=sys.stderr)
        if list_all:
            for where, rel in sorted(items, key=lambda x: x[1]):
                print(f"          [{where}] {safe(rel)}", file=sys.stderr)
print("", file=sys.stderr)
print("  A hit means an owner NAME appears here — not necessarily that the file is", file=sys.stderr)
print("  misplaced. rules.md decides by ownership and reach, not by topic:", file=sys.stderr)
print("    reusable / your own knowledge  -> KEEP it in the shared vault, replace the", file=sys.stderr)
print("                                      name with the neutral space slug", file=sys.stderr)
print("    material the owner owns        -> move into vault/spaces/<slug>/", file=sys.stderr)
print("    generated cache                -> drop from the index; it is regenerable", file=sys.stderr)
print("    archive                        -> move to the space or off to storage", file=sys.stderr)
print("  Never move a shared dependency into a space: default recall skips the seal,", file=sys.stderr)
print("  so it goes invisible in exactly the contexts that consume it.", file=sys.stderr)
print("  Exempt a prefix with a reason in vault/.nda-allow. Neither marker names nor", file=sys.stderr)
print("  the paths that contain them are printed; a masked path shows <slug> instead.", file=sys.stderr)
sys.exit(1)
PY
