#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# uuid5-gen.sh — Generate a deterministic UUID5 for agentBrain notes.
# The seed is the note's path relative to the brain root, spelled with the
# leading `local/` (the vault's old name). validate-note-id.sh derives its
# expected id the same way; a `vault/` path is folded to that spelling, and any
# other base (e.g. "learnings/MyNote") produces an id the validator will reject.
# Usage: ./uuid5-gen.sh "vault/learnings/MyNote"   (local/learnings/MyNote gives the same id)

set -euo pipefail

VAULT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${1:-}" ]; then
  echo "Usage: $(basename "$0") \"path/to/note\" (without .md extension)"
  echo "Example: $(basename "$0") \"vault/learnings/Docker\""
  exit 1
fi

# Read namespace from brain.json, or use default
if [ -f "${VAULT}/brain.json" ]; then
  NAMESPACE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['namespace'])" "${VAULT}/brain.json")
else
  NAMESPACE="a3b2c1d0-1234-5678-9abc-def012345678"
  echo "Warning: brain.json not found, using default namespace. Run setup.sh first." >&2
fi

# Pass path + namespace as argv (NOT string-interpolated) — file paths can contain
# apostrophes (e.g. "Anthropic's-...", "don't-...") which break single-quoted Python literals.
# The vault lives at `vault/`; `local/` is its old name. Every id in every vault
# is derived from the `local/` spelling, and hashing a `vault/` path as typed
# would produce a different uuid for the same file. Fold `vault/` to `local/`
# before hashing, so either spelling gives the same id.
REL="${1#vault/}"
[ "$REL" != "${1}" ] && REL="local/${REL}"

UUID=$(python3 -c "import uuid,sys; print(uuid.uuid5(uuid.UUID(sys.argv[1]), 'agentBrain/' + sys.argv[2]))" "${NAMESPACE}" "${REL}")
echo "${UUID}"
