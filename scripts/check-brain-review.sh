#!/usr/bin/env bash
# Automated brain-review: checks content quality of agentBrain notes.
# Complements /doctor (structural health) with semantic quality checks.
# Usage:
#   bash scripts/check-brain-review.sh           # check both public and local
#   bash scripts/check-brain-review.sh --public   # check public layer only
#   bash scripts/check-brain-review.sh --local    # check local layer only

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCOPE="all"
for arg in "$@"; do
	case "$arg" in
	--public) SCOPE="public" ;;
	--local) SCOPE="local" ;;
	*)
		echo "Unknown flag: $arg" >&2
		exit 1
		;;
	esac
done

python3 - "$SCOPE" <<'PY'
import os
import sys
import re
import json
from pathlib import Path
from datetime import datetime, timedelta

scope = sys.argv[1] if len(sys.argv) > 1 else 'all'
now = datetime.now()
six_months = timedelta(days=180)
three_months = timedelta(days=90)
extracted_stale = timedelta(days=7)

# Content with its own schema or auto-generated/templated — not curated notes.
# The note-schema/quality checks below would only produce noise on these
# (public frontmatter is check-frontmatter's job; these are exempt there too).
# 'quarantine' is a deliberate security holding pen for raw imports awaiting
# sanitization/deletion — check-agentbrain-local.sh already excludes it for the
# same reason; reviewing it for note quality is a category error.
# 'archive' holds raw triaged imports retained for later mining (distilled gems
# already promoted to local/learnings/); it is reference material, not curated notes.
skip_segments = {'youtube-knowledge', 'daily-notes', 'sessions', 'setup-history', 'templates', 'quarantine', 'archive'}
skip_files = {'SKILL.md', 'manifest.md'}

warnings = []
errors = []

def parse_frontmatter(text):
    """Extract YAML frontmatter as a dict."""
    if not text.startswith('---\n'):
        return {}
    end = text.find('\n---', 4)
    if end == -1:
        return {}
    fm_text = text[4:end]
    result = {}
    for line in fm_text.split('\n'):
        if ':' in line:
            key, _, val = line.partition(':')
            result[key.strip()] = val.strip()
    return result

def parse_date(date_str):
    """Parse date string from frontmatter."""
    if not date_str:
        return None
    for fmt in ['%Y-%m-%d', '%Y-%m-%dT%H:%M:%SZ', '%Y-%m-%dT%H:%M:%S']:
        try:
            return datetime.strptime(date_str[:19] if 'T' in date_str else date_str, fmt)
        except ValueError:
            continue
    return None

def should_skip(relpath, fname):
    """Own-schema / auto-generated / templated content — not a curated note."""
    if fname in skip_files:
        return True
    return bool(set(Path(relpath).parts) & skip_segments)

def scan_markdown_files(base_path, label):
    """Scan markdown files for quality issues."""
    if not os.path.isdir(base_path):
        return

    for root, dirs, files in os.walk(base_path):
        # Skip hidden dirs and .git
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'node_modules']

        for fname in files:
            if not fname.endswith('.md'):
                continue
            if fname in ('README.md', '.gitkeep', '_example.md'):
                continue

            fpath = os.path.join(root, fname)
            relpath = os.path.relpath(fpath, '.')
            if should_skip(relpath, fname):
                continue

            try:
                text = open(fpath, encoding='utf-8', errors='replace').read()
            except Exception:
                continue

            fm = parse_frontmatter(text)

            # ── Missing required frontmatter fields ────────────
            if not fm:
                warnings.append(f'{label} {relpath}: missing frontmatter entirely')
                continue

            note_date = parse_date(fm.get('date', ''))

            # ── Extracted notes: own schema + review lifecycle ──
            # Machine-generated; no tags/id until promoted. Flag ones left
            # pending-review too long instead of demanding the note schema.
            if fm.get('type', '') == 'extracted-learning':
                if (fm.get('status', '') == 'pending-review' and note_date
                        and (now - note_date) > extracted_stale):
                    age = (now - note_date).days
                    warnings.append(f'{label} {relpath}: extracted note pending-review for {age}d — promote to learnings/ or remove')
                continue

            # Required fields for all notes
            for field in ('date', 'type', 'tags', 'id'):
                if field not in fm or not fm[field]:
                    warnings.append(f'{label} {relpath}: missing frontmatter field: {field}')

            # ── Stale notes (older than 6 months) ──────────────
            if note_date and (now - note_date) > six_months:
                age_days = (now - note_date).days
                warnings.append(f'{label} {relpath}: stale note ({age_days}d old, last updated {fm.get("date", "?")})')

            # ── Low confidence entries ──────────────────────────
            conf = fm.get('confidence', '')
            if conf == 'low':
                if note_date and (now - note_date) > three_months:
                    warnings.append(f'{label} {relpath}: confidence:low for >3 months — confirm or retract')

            # ── Retracted entries older than 3 months ───────────
            if conf == 'retracted':
                if note_date and (now - note_date) > three_months:
                    warnings.append(f'{label} {relpath}: confidence:retracted for >3 months — safe to remove')

            # ── Empty/placeholder content ───────────────────────
            content = text[text.find('---\n', 4) + 4:].strip() if text.startswith('---\n') else text.strip()
            # Remove second frontmatter delimiter
            if content.startswith('---\n'):
                content = content[4:]
            content = content.strip()

            if len(content) < 50 and fm.get('type', '') not in ('system', 'backlog'):
                warnings.append(f'{label} {relpath}: very short content ({len(content)} chars) — is it actionable?')

            # ── Orphaned project check ──────────────────────────
            if fm.get('type', '') == 'project':
                status = fm.get('status', '')
                if status == 'active':
                    if note_date and (now - note_date) > six_months:
                        warnings.append(f'{label} {relpath}: active project with no updates for {(now - note_date).days}d — still active?')

    # ── Check for orphaned projects (project dir exists but not in index.md) ─
    projects_dir = os.path.join(base_path, 'projects')
    index_file = os.path.join(projects_dir, 'index.md')
    if os.path.isdir(projects_dir) and os.path.isfile(index_file):
        # Get project dirs
        project_dirs = set()
        for entry in os.listdir(projects_dir):
            p = os.path.join(projects_dir, entry)
            if os.path.isdir(p) and not entry.startswith('.') and not entry.startswith('_'):
                project_dirs.add(entry)

        # Parse index.md for referenced projects
        index_text = open(index_file, encoding='utf-8', errors='replace').read()

        # Referenced if the folder name appears anywhere in index.md — format
        # agnostic (table cell, link, or wiki-link), not just a trailing slash.
        orphaned = {p for p in project_dirs if p not in index_text}
        for proj in sorted(orphaned):
            warnings.append(f'{label} projects/{proj}: orphaned project — not referenced in index.md')

# ── Run scans ──────────────────────────────────────────

if scope in ('all', 'public'):
    # Public markdown folders (excluding local/)
    public_dirs = ['learnings', 'projects', 'system', 'templates', 'sessions', 'daily-notes', 'user-preferences', 'youtube-knowledge']
    for d in public_dirs:
        if os.path.isdir(d):
            scan_markdown_files(d, 'public:')

if scope in ('all', 'local'):
    if os.path.isdir('local'):
        scan_markdown_files('local', 'local:')

# ── Duplicate detection (by title/heading) ─────────────

def find_duplicates(base_path, label):
    """Find notes with identical first heading."""
    if not os.path.isdir(base_path):
        return
    headings = {}
    for root, dirs, files in os.walk(base_path):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'node_modules']
        for fname in files:
            if not fname.endswith('.md') or fname in ('README.md', '.gitkeep'):
                continue
            fpath = os.path.join(root, fname)
            if should_skip(os.path.relpath(fpath, '.'), fname):
                continue
            try:
                text = open(fpath, encoding='utf-8', errors='replace').read()
            except Exception:
                continue
            # Compare H1 titles only — section names like "Related" repeat
            # legitimately across notes and are not duplicate titles.
            for line in text.split('\n'):
                if line.startswith('# '):
                    heading = line.lstrip('#').strip()
                    if heading in headings:
                        warnings.append(f'{label} duplicate heading "{heading}": {headings[heading]} and {fpath}')
                    else:
                        headings[heading] = fpath
                    break

if scope in ('all', 'public'):
    for d in ['learnings', 'projects', 'system']:
        if os.path.isdir(d):
            find_duplicates(d, 'public:')

if scope in ('all', 'local'):
    if os.path.isdir('local'):
        find_duplicates('local', 'local:')

# ── Public/private misclassification ───────────────────

def check_misclassification(base_path, label):
    """Check if public notes contain content that should be private."""
    if not os.path.isdir(base_path):
        return

    # Patterns that suggest private content in public notes
    private_patterns = [
        (r'/User' + r's/[a-z]+/', 'absolute home path'),
        (r'192\.168\.\d+\.\d+', 'private IP address'),
        (r'10\.\d+\.\d+\.\d+', 'private IP address'),
        (r'gh[pousr]_[A-Za-z0-9_]{10,}', 'GitHub token pattern'),
        (r'sk-[A-Za-z0-9_-]{20,}', 'API key pattern'),
        (r'AKIA[0-9A-Z]{16}', 'AWS key pattern'),
    ]

    for root, dirs, files in os.walk(base_path):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'node_modules']
        for fname in files:
            if not fname.endswith('.md'):
                continue
            fpath = os.path.join(root, fname)
            relpath = os.path.relpath(fpath, '.')
            try:
                text = open(fpath, encoding='utf-8', errors='replace').read()
            except Exception:
                continue
            for pattern, desc in private_patterns:
                matches = re.findall(pattern, text)
                if matches:
                    errors.append(f'{label} {relpath}: potential private content ({desc}) — {len(matches)} match(es)')

if scope in ('all', 'public'):
    for d in ['learnings', 'projects', 'system', 'templates', 'user-preferences', 'sessions', 'daily-notes', 'youtube-knowledge']:
        if os.path.isdir(d):
            check_misclassification(d, 'public:')

# ── Report ─────────────────────────────────────────────

if errors:
    print('brain-review FAILED:', file=sys.stderr)
    for e in errors:
        print(f'  ✗ {e}', file=sys.stderr)

if warnings:
    print(f'brain-review: {len(warnings)} warning(s)')
    for w in warnings:
        print(f'  ⚠ {w}')

if not errors and not warnings:
    print('brain-review passed. No quality issues found.')
elif not errors:
    print(f'brain-review passed with {len(warnings)} warning(s).')
else:
    raise SystemExit(1)
PY
