#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-brain-config.sh — Create or update brain.json config.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Maintainer identity — the default `author:` for this vault's own addons. Derived
# from the git identity (no extra onboarding prompt); falls back to "unknown".
MAINTAINER="$(git config user.name 2>/dev/null || true)"; [ -n "$MAINTAINER" ] || MAINTAINER="unknown"

if [ ! -f "${VAULT}/brain.json" ]; then
	NAMESPACE=$(python3 -c "import uuid; print(uuid.uuid4())")
	cat >"${VAULT}/brain.json" <<JSON
{
  "namespace": "${NAMESPACE}",
  "version": "1.0",
  "created": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "path": "${VAULT}",
  "maintainer": "${MAINTAINER}"
}
JSON
	echo -e "${GREEN}Created${NC} brain.json (namespace: ${NAMESPACE}, maintainer: ${MAINTAINER})"
else
	# Idempotent backfill: resolve the "~" path placeholder and add `maintainer`
	# if an older brain.json predates it.
	if python3 - <<PY
import json, sys
from pathlib import Path
path = Path("${VAULT}/brain.json")
cfg = json.loads(path.read_text())
changed = False
if cfg.get("path") in ("~", None):
    cfg["path"] = "${VAULT}"; changed = True
if not cfg.get("maintainer"):
    cfg["maintainer"] = "${MAINTAINER}"; changed = True
if changed:
    path.write_text(json.dumps(cfg, indent=2) + "\n")
sys.exit(0 if changed else 1)
PY
	then
		echo -e "${GREEN}Updated${NC} brain.json (path/maintainer backfilled)"
	else
		echo -e "${YELLOW}Exists${NC}  brain.json"
	fi
fi

# Namespace backup into the private layer — the namespace is the unrecoverable
# part of brain.json (all UUID5 note-ids derive from it). check-anchors.sh
# guards it; fix.sh refreshes it on change.
if [ -d "${VAULT}/vault" ]; then
	NS=$(python3 -c "import json;print(json.load(open('${VAULT}/brain.json')).get('namespace',''))" 2>/dev/null || true)
	BACKUP="${VAULT}/vault/brain-namespace.backup"
	if [ -n "$NS" ] && [ ! -s "$BACKUP" ]; then
		printf '%s\n' "$NS" > "$BACKUP"
		echo -e "${GREEN}Created${NC} vault/brain-namespace.backup"
	elif [ -n "$NS" ] && [ "$(cat "$BACKUP")" != "$NS" ]; then
		# The vault owns the namespace: every id in it was derived from the one in
		# the backup. A checkout whose brain.json says otherwise (a fresh clone
		# mounted on a populated vault) adopts it here, BEFORE templates and the
		# daily note are rendered. Measured once: a checkout with its own namespace
		# seeded 13 notes into a shared vault, each with an id no validator accepts.
		VAULT_NS="$(tr -d '[:space:]' < "$BACKUP")"
		python3 - "${VAULT}/brain.json" "$VAULT_NS" <<'PY'
import json, sys
p, ns = sys.argv[1], sys.argv[2]
d = json.load(open(p)); d["namespace"] = ns
json.dump(d, open(p, "w"), indent=2); open(p, "a").write("\n")
PY
		echo -e "${YELLOW}Adopted${NC} the vault's UUID5 namespace into brain.json (was ${NS:0:8}…, vault has ${VAULT_NS:0:8}…)."
	fi
fi

