#!/usr/bin/env bash
# Manually archive the current session-journal and start a fresh one.
# Mirrors the session-start flow from system/agent-config/shared.md so users can
# invoke it explicitly via /journal archive.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
SESSIONS_DIR="$BRAIN_ROOT/local/sessions"
JOURNAL="$SESSIONS_DIR/session-journal.md"
ARCHIVE_ROOT="$SESSIONS_DIR/archive"

if [[ ! -f "$JOURNAL" ]]; then
	echo "No session-journal.md to archive."
	exit 0
fi

now=$(date +%Y%m%d-%H%M%S)
month=$(date +%Y-%m)
mkdir -p "$ARCHIVE_ROOT/$month"

# Generate 4-hex PID; retry on collision.
for _ in 1 2 3 4 5; do
	pid=$(openssl rand -hex 2)
	target="$ARCHIVE_ROOT/$month/$now-$pid.md"
	if [[ ! -e "$target" ]]; then
		break
	fi
done

# Compute UUID5 from the archive path (vault-relative, no extension).
rel="local/sessions/archive/$month/$now-$pid"
uuid=$(bash "$BRAIN_ROOT/scripts/uuid5-gen.sh" "$rel" 2>/dev/null || echo "")

# Read existing journal; rewrite frontmatter id->new uuid, status=archived.
python3 - "$JOURNAL" "$target" "$uuid" <<'PYEOF'
import sys, re, os
src, dst, new_id = sys.argv[1:4]
text = open(src).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    # No frontmatter — just copy verbatim
    open(dst,"w").write(text)
    raise SystemExit
fm = m.group(1)
body = text[m.end():]

def set_or_add(fm, key, value):
    if re.search(rf"^{key}:\s*.*$", fm, re.M):
        return re.sub(rf"^{key}:\s*.*$", f"{key}: {value}", fm, flags=re.M)
    return fm + f"\n{key}: {value}"

if new_id:
    fm = set_or_add(fm, "id", new_id)
fm = set_or_add(fm, "status", "archived")
out = f"---\n{fm}\n---\n{body}"
open(dst,"w").write(out)
PYEOF

echo "archived → $target"

# Start a fresh journal with previous = archived basename (no .md).
prev_base="$now-$pid"
new_uuid=$(bash "$BRAIN_ROOT/scripts/uuid5-gen.sh" "local/sessions/session-journal-$now-$pid" 2>/dev/null || echo "")

cat > "$JOURNAL" <<EOF
---
date: $(date +%Y-%m-%d)
type: session-journal
tags: [session]
project:
previous: $prev_base
id: $new_uuid
status: active
---

# Session Journal

## Last updated: $(date +%H:%M) (manual archive)

### Project:
### Task:

### Done
-

### Files changed
-

### Next step
->

### Open questions
-
EOF

echo "fresh journal: $JOURNAL"
