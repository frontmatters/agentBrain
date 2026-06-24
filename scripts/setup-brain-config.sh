#!/usr/bin/env bash
# setup-brain-config.sh — Create or update brain.json config.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -f "${VAULT}/brain.json" ]; then
	NAMESPACE=$(python3 -c "import uuid; print(uuid.uuid4())")
	cat >"${VAULT}/brain.json" <<JSON
{
  "namespace": "${NAMESPACE}",
  "version": "1.0",
  "created": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "path": "${VAULT}"
}
JSON
	echo -e "${GREEN}Created${NC} brain.json (namespace: ${NAMESPACE})"
else
	if grep -q '"path": "~"' "${VAULT}/brain.json" 2>/dev/null; then
		python3 - <<PY
import json
from pathlib import Path
path = Path("${VAULT}/brain.json")
cfg = json.loads(path.read_text())
cfg["path"] = "${VAULT}"
path.write_text(json.dumps(cfg, indent=2) + "\n")
PY
		echo -e "${GREEN}Updated${NC} brain.json path -> ${VAULT}"
	else
		echo -e "${YELLOW}Exists${NC}  brain.json"
	fi
fi

# Namespace backup into the private layer — the namespace is the unrecoverable
# part of brain.json (all UUID5 note-ids derive from it). check-anchors.sh
# guards it; fix.sh refreshes it on change.
if [ -d "${VAULT}/local" ]; then
	NS=$(python3 -c "import json;print(json.load(open('${VAULT}/brain.json')).get('namespace',''))" 2>/dev/null || true)
	if [ -n "$NS" ] && [ "$(cat "${VAULT}/local/brain-namespace.backup" 2>/dev/null)" != "$NS" ]; then
		printf '%s\n' "$NS" > "${VAULT}/local/brain-namespace.backup"
		echo -e "${GREEN}Created${NC} local/brain-namespace.backup"
	fi
fi

