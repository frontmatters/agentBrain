#!/usr/bin/env bash
set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

usage() {
  echo "Usage: bash scripts/scanman-init.sh <repo-slug> [repo-path] [goal...]" >&2
  echo "Example: bash scripts/scanman-init.sh babysitter ~/.opensrc/repos/github.com/a5c-ai/babysitter/main Distill orchestration architecture" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

REPO_SLUG="$1"
shift || true

if [[ ! "$REPO_SLUG" =~ ^[a-z0-9-]+$ ]]; then
  echo "repo-slug must be lowercase kebab-case: $REPO_SLUG" >&2
  exit 1
fi

REPO_PATH="${1:-}"
if [[ $# -gt 0 ]]; then shift; fi
GOAL="${*:-}"

TARGET_DIR="$AGENTBRAIN_DIR/local/research/repo-distill/$REPO_SLUG"
if [[ -e "$TARGET_DIR" ]]; then
  echo "Scanman target already exists: $TARGET_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
cp "$AGENTBRAIN_DIR/templates/repo-distill-index.md" "$TARGET_DIR/index.md"
cp "$AGENTBRAIN_DIR/templates/repo-distill-file-inventory.md" "$TARGET_DIR/00-file-inventory.md"
cp "$AGENTBRAIN_DIR/templates/repo-distill-dependency-map.md" "$TARGET_DIR/00b-dependency-map.md"
cp "$AGENTBRAIN_DIR/templates/repo-distill-system-map.md" "$TARGET_DIR/01-system-map.md"
cp "$AGENTBRAIN_DIR/templates/repo-distill-runtime-model.md" "$TARGET_DIR/02-runtime-model.md"
cp "$AGENTBRAIN_DIR/templates/repo-distill-core-primitives.md" "$TARGET_DIR/03-core-primitives.md"
cp "$AGENTBRAIN_DIR/templates/repo-distill-risk-and-bloat.md" "$TARGET_DIR/04-risk-and-bloat.md"
cp "$AGENTBRAIN_DIR/templates/repo-distill-redesign-v1.md" "$TARGET_DIR/05-redesign-v1.md"

TODAY=$(date +%F)

REPO_SLUG="$REPO_SLUG" REPO_PATH="$REPO_PATH" GOAL="$GOAL" TODAY="$TODAY" TARGET_DIR="$TARGET_DIR" AGENTBRAIN_DIR="$AGENTBRAIN_DIR" python3 - <<'PY'
from pathlib import Path
import os
import subprocess

slug = os.environ['REPO_SLUG']
repo_path = os.environ.get('REPO_PATH', '').strip()
goal = os.environ.get('GOAL', '').strip()
today = os.environ['TODAY']
target = Path(os.environ['TARGET_DIR'])
agentbrain_dir = Path(os.environ['AGENTBRAIN_DIR'])
uuid_script = agentbrain_dir / 'scripts' / 'uuid5-gen.sh'
scanman_version = (agentbrain_dir / 'system' / 'skills' / 'scanman' / 'VERSION').read_text().strip()


def make_uuid(rel_path: str) -> str:
    return subprocess.check_output([str(uuid_script), rel_path], text=True).strip()

artifact_map = {
    'index.md': 'index',
    '00-file-inventory.md': 'file-inventory',
    '00b-dependency-map.md': 'dependency-map',
    '01-system-map.md': 'system-map',
    '02-runtime-model.md': 'runtime-model',
    '03-core-primitives.md': 'core-primitives',
    '04-risk-and-bloat.md': 'risk-and-bloat',
    '05-redesign-v1.md': 'redesign-v1',
}

for filename, artifact in artifact_map.items():
    path = target / filename
    text = path.read_text()
    # uuid5-gen.sh expects path WITHOUT .md extension (the agentBrain validate-hook
    # uses the same convention). Pass the stem, not the filename.
    stem = filename[:-3] if filename.endswith('.md') else filename
    rel = f'local/research/repo-distill/{slug}/{stem}'
    uid = make_uuid(rel)
    if filename == 'index.md':
        text = text.replace('YYYY-MM-DD', today)
        text = text.replace('<UUID5>', uid)
        text = text.replace('<repo-name>', slug)
    elif not text.startswith('---\n'):
        frontmatter = '\n'.join([
            '---',
            f'date: {today}',
            'type: research',
            'tags: [repo-distill, architecture, analysis]',
            'status: active',
            f'id: {uid}',
            f'repo: {slug}',
            f'artifact: {artifact}',
            'source: session',
            '---',
            '',
        ])
        text = frontmatter + text
    path.write_text(text if text.endswith('\n') else text + '\n')

path = target / 'index.md'
text = path.read_text()
text = text.replace('- Repo URL/path', f'- Repo URL/path: `{repo_path}`' if repo_path else '- Repo URL/path:')
text = text.replace('- Version/ref/commit analyzed', '- Version/ref/commit analyzed:')
text = text.replace('- Related notes/docs', '- Related notes/docs:')
text = text.replace('- Scanman method version', f'- Scanman method version: `{scanman_version}`')
text = text.replace('- Current phase', '- Current phase: initialized')
text = text.replace('- Known blockers', '- Known blockers:')
text = text.replace('- Next action', '- Next action: run `bash scripts/scanman-scan.sh <repo-path> {}` and then manually enrich the generated docs'.format(slug) if repo_path else '- Next action: populate `00-file-inventory.md`')
text = text.replace('- Coverage status: sampled / selective / focused / broad / near-exhaustive', '- Coverage status: sampled')
text = text.replace('- Bootstrap status: not started / bootstrap generated / manually enriched / verified enough for current conclusions', '- Bootstrap status: not started')
text = text.replace('| `00-file-inventory.md` | no | no | no | no | |', '| `00-file-inventory.md` | yes | no | no | no | template created |')
text = text.replace('| `00b-dependency-map.md` | no | no | no | no | |', '| `00b-dependency-map.md` | yes | no | no | no | template created |')
text = text.replace('| `01-system-map.md` | no | no | no | no | |', '| `01-system-map.md` | yes | no | no | no | template created |')
text = text.replace('| `02-runtime-model.md` | no | no | no | no | |', '| `02-runtime-model.md` | yes | no | no | no | template created |')
text = text.replace('| `03-core-primitives.md` | no | no | no | no | |', '| `03-core-primitives.md` | yes | no | no | no | template created |')
text = text.replace('| `04-risk-and-bloat.md` | no | no | no | no | |', '| `04-risk-and-bloat.md` | yes | no | no | no | template created |')
text = text.replace('| `05-redesign-v1.md` | no | no | no | no | |', '| `05-redesign-v1.md` | yes | no | no | no | template created |')
if goal:
    text = text.replace('- What target system/use case the distillation serves', f'- {goal}')
path.write_text(text if text.endswith('\n') else text + '\n')
PY

echo "Initialized scanman workspace: $TARGET_DIR"
if [[ -n "$REPO_PATH" ]]; then
  echo "Next: bash scripts/scanman-scan.sh '$REPO_PATH' '$REPO_SLUG'"
else
  echo "Next: run scripts/scanman-scan.sh with a repo path or fill files manually"
fi
