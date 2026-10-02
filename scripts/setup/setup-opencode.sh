#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-opencode.sh — Install OpenCode integration.
# Safe to re-run (idempotent).
#
# OpenCode reads instruction file paths from the `instructions` array in
# ~/.config/opencode/opencode.json. We write the canonical pointer block (from
# agentbrain-pointer.sh) to ~/.config/opencode/agentbrain-pointer.md and register
# that path in the array — merging into the existing config, never overwriting.
# uninstall.sh removes both symmetrically.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$VAULT/scripts/agentbrain-pointer.sh"

OPENCODE_DIR="$AGENT_HOME/.config/opencode"
OPENCODE_JSON="${OPENCODE_DIR}/opencode.json"
POINTER_FILE="${OPENCODE_DIR}/agentbrain-pointer.md"

# Not installed → exit 2 (not applicable). Presence = CLI on PATH or an existing
# config dir (current ~/.config/opencode or legacy ~/.opencode).
if ! command -v opencode &>/dev/null && [ ! -d "$OPENCODE_DIR" ] && [ ! -d "$AGENT_HOME/.opencode" ]; then
	exit 2
fi

# Refresh only when the canonical block differs; keep JSON registration below.
mkdir -p "$OPENCODE_DIR"
state="$(agentbrain_pointer_sync "$POINTER_FILE" "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "opencode.md" own)"
# Register the pointer, and drop entries an older agentBrain setup wrote that
# no longer exist (per-file paths into a moved checkout or a test fixture).
# Only missing absolute paths with an agentBrain file name are removed; globs,
# URLs and anything that still exists are the user's and stay. Errors stay
# visible: a malformed user config is never silently skipped or overwritten.
# OpenCode asks before any tool touches a path outside the project and refuses
# in a non-interactive run, so without this the agent saw the pointer but could
# not read one file it names (validated 2026-10-01). Grant the brain alias and
# the vault's real directory (the vault is usually a symlink and OpenCode may
# check the resolved path). Absolute paths, so uninstall.sh can remove exactly
# these; a user's own setting for the same path is never overwritten.
BRAIN_PATH="${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}"
VAULT_REAL="$(cd "$BRAIN_PATH/vault" 2>/dev/null && pwd -P || true)"
result="$(python3 - "$OPENCODE_JSON" "$POINTER_FILE" "$BRAIN_PATH" "$VAULT_REAL" <<'PY'
import json, os, sys
from pathlib import Path

config_path = Path(sys.argv[1])
pointer = sys.argv[2]
grants = [g.rstrip("/") + "/**" for g in sys.argv[3:5] if g]
OURS = {"rules.md", "skills.md", "patterns.md", "troubleshooting.md", "shared.md", "opencode.md", "agentbrain-pointer.md"}

config = {}
if config_path.exists():
    try:
        config = json.loads(config_path.read_text())
    except json.JSONDecodeError as e:
        sys.stderr.write(
            f"setup-opencode: cannot parse {config_path} as JSON: {e}\n"
            "  Fix the file (or move it aside) and re-run.\n")
        sys.exit(1)

instructions = config.get('instructions', [])
if not isinstance(instructions, list):
    sys.stderr.write(
        f"setup-opencode: 'instructions' in {config_path} is not an array; "
        "fix it manually and re-run.\n")
    sys.exit(1)

def dead_ours(entry):
    return (isinstance(entry, str) and entry.startswith("/") and not any(c in entry for c in "*?[")
            and os.path.basename(entry).lower() in OURS and not os.path.exists(entry))

kept = [e for e in instructions if e == pointer or not dead_ours(e)]
removed = len(instructions) - len(kept)
if pointer not in kept:
    kept.append(pointer)
changed = kept != instructions or not config_path.exists()
config['instructions'] = kept

granted, note = 0, ""
perm = config.get('permission')
if perm is None:
    perm = config['permission'] = {}
if not isinstance(perm, dict):
    note = "permission is not an object; grant read access to the brain manually"
else:
    ext = perm.get('external_directory')
    if ext is None:
        ext = perm['external_directory'] = {}
    if isinstance(ext, dict):
        for g in grants:
            if g not in ext:
                ext[g] = "allow"
                granted += 1
    elif ext != "allow":
        note = f"external_directory is '{ext}' for every path; agentBrain files need 'allow'"
    if not ext:
        perm.pop('external_directory', None)
    if not perm:
        config.pop('permission', None)
if changed or granted:
    config_path.write_text(json.dumps(config, indent=2) + '\n')
print(f"{removed} {granted} {note}")
PY
)"
read -r pruned granted note <<<"$result"
if [ "$state" = current ] && [ "${pruned:-0}" = 0 ] && [ "${granted:-0}" = 0 ]; then
	echo -e "${YELLOW}Skip${NC}    OpenCode (already current)"
else
	msg="pointer $state"
	if [ "${pruned:-0}" != 0 ]; then msg="$msg, removed $pruned dead agentBrain path(s)"; fi
	if [ "${granted:-0}" != 0 ]; then msg="$msg, read access to the brain"; fi
	echo -e "${GREEN}✓${NC} OpenCode ($msg)"
fi
if [ -n "${note:-}" ]; then echo -e "${YELLOW}Note${NC}    OpenCode: $note"; fi
