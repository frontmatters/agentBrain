#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# agentbrain-pointer.sh — Single source for the "read at session start" pointer
# block that each setup-<client>.sh installs into its client config file.
#
# Sourced, not run directly: the list of brain files to read lives in exactly
# one place, so it cannot drift between clients (it used to be copy-pasted per
# client, and some copies silently went thin — missing scopes/skills/config).
# Clients differ only by their per-agent config filename.
#
# Usage (after sourcing):
#   agentbrain_pointer_sync "$CLIENT_CONFIG" "$BRAIN" "claude.md" embed

# agentbrain_pointer_target_ok <client-config-file> <checkout>
# A client config that resolves into the agentBrain checkout or its vault is a
# symlink into a git-tracked file: appending the pointer there edits the product
# (or a vault note) instead of the client config, and the privacy scan then flags
# the absolute paths it carries. Refuse, and say which link to replace.
agentbrain_pointer_target_ok() {
	local target="$1" checkout="$2" resolved root
	resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target" 2>/dev/null)" || return 0
	for root in "$checkout" "$checkout/vault"; do
		root="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$root" 2>/dev/null)" || continue
		case "$resolved/" in "$root"/*)
			echo "agentBrain: not writing the pointer into $target: it resolves to $resolved, inside $root." >&2
			echo "  Replace that symlink with a regular file, then re-run setup." >&2
			return 1 ;;
		esac
	done
	return 0
}

agentbrain_pointer_block() {
	local vault="$1" agent_config="$2"
	cat <<POINTER

## agentBrain
# Persistent knowledge base at ${vault}
# Path contract: ${vault} is the checkout root (AGENTBRAIN_DIR).
# Private knowledge is mounted below it at ${vault}/vault (VAULT_DIR), often
# as a symlink to an external directory. Never address private files directly
# below the checkout root (for example <checkout>/learnings); use
# ${vault}/vault/<area>.
# If a tool needs an absolute path, verify the resolved mount first with
# \`realpath ${vault}/vault\` rather than inferring it from the checkout name.
# Read these at session start:
- Architecture: \`${vault}/system/architecture.md\`
- Patterns: \`${vault}/vault/learnings/patterns.md\`
- Troubleshooting: \`${vault}/vault/learnings/troubleshooting.md\`
- Rules: \`${vault}/system/rules.md\`
- Shared agent config: \`${vault}/system/agent-config/shared.md\`
- Agent config: \`${vault}/system/agent-config/${agent_config}\`
- Skills: \`${vault}/system/skills.md\`
- Brain status (live): \`${vault}/vault/sessions/startup-context.md\` — current open findings + alerts (skip if file absent). Mention any "Reminders due" or "Broken brain commands and links" to the owner before anything else.
- Preferences scopes: read any existing files under \`${vault}/vault/preferences/organization/\`, \`${vault}/vault/preferences/team/\`, and \`${vault}/vault/preferences/personal/\`.

# Self-learning: write insights to the brain during sessions.
# See \`${vault}/system/rules.md\` for the full protocol.

# Writing a note under vault/: ALWAYS use \`bash ${vault}/scripts/new-note.sh <type> <vault-relative-path-no-ext> [title]\`
# to get correct frontmatter + computed UUID5. NEVER type the id by hand —
# the brain enforces uuid5-gen.sh parity at write-time (CC PostToolUse hook,
# Pi note-id-validator extension) and will reject mismatches.
POINTER
}

# One boundary definition for install, inspection and uninstall. Embedded files
# are user-owned: never discard bytes outside our marked or legacy region.
agentbrain_pointer_operation() {
 local action="$1" file="$2" brain="${3:-}" config="${4:-}" mode="${5:-}"
 local desired=""
 if [ "$action" != strip ]; then
  [ "$mode" = own ] || [ "$mode" = embed ] || { echo "pointer: expected own|embed" >&2; return 2; }
  if [ "$action" = sync ]; then
   agentbrain_pointer_target_ok "$file" "${VAULT:-${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}}" || return 1
  fi
  desired="$(mktemp)" || return 1
  agentbrain_pointer_block "$brain" "$config" > "$desired"
 fi
 python3 - "$action" "$file" "$mode" "$desired" <<'PYCODE'
import datetime
import os
from pathlib import Path
import re
import shutil
import sys

action, name, mode, wanted = sys.argv[1:]
file = Path(name)
old = file.read_bytes() if file.exists() else b''
begin, end = b'<!-- agentBrain:begin -->', b'<!-- agentBrain:end -->'
# Marker lines include their newline. Legacy starts at a '# agentBrain' or
# '## agentBrain' heading, with or without text after the word (the oldest
# installs wrote '# agentBrain — persistent knowledge base'), the same start
# uninstall.sh always matched, and ends immediately before the next level-two
# heading. No newline normalization.
# Every agentBrain block in the file, in order. Older setups appended a new
# block next to an old one instead of replacing it (a GEMINI.md held two), so
# all of them are ours: sync keeps one, strip removes all. A legacy block never
# runs into a marked one.
marked = [(m.start(), m.end()) for m in re.finditer(rb'(?m)^<!-- agentBrain:begin -->\r?\n.*?^<!-- agentBrain:end -->(?:\r?\n|$)', old, re.S | re.M)]
inside = lambda pos: any(a <= pos < b for a, b in marked)
legacy = [(m.start(), m.end()) for m in re.finditer(rb'(?m)^##? agentBrain\b.*?(?=^## |^<!-- agentBrain:begin -->|\Z)', old, re.S | re.M) if not inside(m.start())]
spans = sorted(marked + legacy)
def without(data):
    out, pos = b'', 0
    for a, b in spans:
        out += data[pos:a]; pos = b
    return out + data[pos:]
canonical = Path(wanted).read_bytes() if wanted else b''
if mode == 'own':
    new = canonical
    status = 'missing' if not file.exists() else ('current' if old == new else 'stale')
else:
    block = begin + b'\n' + canonical.lstrip(b'\n') + end + b'\n'
    if spans:
        # the current block takes the place of the first one; the others go
        parts, pos = [], 0
        for i, (a, b) in enumerate(spans):
            parts.append(old[pos:a])
            if i == 0:
                parts.append(block)
            pos = b
        parts.append(old[pos:])
        new = b''.join(parts)
        status = 'legacy' if legacy else ('current' if old == new else 'stale')
    else:
        new = old + (b'\n' if old and not old.endswith(b'\n') else b'') + block
        status = 'missing'
if action == 'state':
    print(status)
elif action == 'strip':
    if spans:
        file.write_bytes(without(old))
elif action == 'sync':
    if status != 'current':
        file.parent.mkdir(parents=True, exist_ok=True)
        if file.exists() and mode == 'embed':
            stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
            shutil.copy2(file, str(file) + '.agentbrain-' + stamp + '.bak')
        file.write_bytes(new)
    print('current' if status == 'current' else 'installed' if status == 'missing' else 'refreshed')
else:
    sys.exit(2)
PYCODE
 local rc=$?
 [ -z "$desired" ] || rm -f "$desired"
 return "$rc"
}
agentbrain_pointer_strip() { agentbrain_pointer_operation strip "$1"; }
agentbrain_pointer_sync() { agentbrain_pointer_operation sync "$@"; }
agentbrain_pointer_state() { agentbrain_pointer_operation state "$@"; }
