#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# uuid5-gen.sh — Generate a deterministic UUID5 for agentBrain notes.
# The seed is the note's path relative to the brain root, INCLUDING the leading
# `local/` — this is what validate-note-id.sh derives its expected id from, so any
# other base (e.g. "learnings/MyNote") produces an id the validator will reject.
# Usage: ./uuid5-gen.sh "local/learnings/MyNote"

set -euo pipefail

VAULT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${1:-}" ]; then
  echo "Usage: $(basename "$0") \"path/to/note\" (without .md extension)"
  echo "Example: $(basename "$0") \"local/learnings/Docker\""
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
# `vault/` is an alias for `local/` (setup-vault.sh links them), but an id
# must never depend on which name the caller typed: every id in every vault is
# already derived from the `local/` spelling, and re-deriving one under `vault/`
# would produce a different uuid for the same file. Normalise before hashing.
REL="${1#vault/}"
[ "$REL" != "${1}" ] && REL="local/${REL}"

UUID=$(python3 -c "import uuid,sys; print(uuid.uuid5(uuid.UUID(sys.argv[1]), 'agentBrain/' + sys.argv[2]))" "${NAMESPACE}" "${REL}")
echo "${UUID}"
