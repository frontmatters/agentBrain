#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Reminders are dated queue tasks; queue.sh remains the sole writer and state machine.
set -euo pipefail
ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=scripts/lib/vault.sh
. "$ROOT/scripts/lib/vault.sh"
usage() { echo 'usage: brain remind "text" --on YYYY-MM-DD [--scope S] [--force] | [list [--wide|--plain]] | done <id>' >&2; exit 2; }
case "${1:-}" in
  ''|list)
    # A table for a person; `--plain` (or output that is not a terminal) keeps
    # the "due  id  title" lines scripts read, such as update-startup-context.
    [ "$#" -gt 0 ] && shift
    fmt=table; [ -t 1 ] || fmt=plain
    while [ "$#" -gt 0 ]; do
      case "$1" in --plain) fmt=plain ;; --table) fmt=table ;; --wide) fmt=wide ;; *) usage ;; esac; shift
    done
    cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 100)}"
    python3 - "$VAULT_DIR/queue" "$fmt" "$cols" <<'PY'
import pathlib, re, sys
from datetime import date

queue, fmt, cols = sys.argv[1], sys.argv[2], int(sys.argv[3] or 100)
rows = []
for file in pathlib.Path(queue).glob('*/*.md'):
    try:
        text = file.read_text()
        front, body = text.split('---', 2)[1:]
        fields = dict(re.findall(r'^([a-z_]+):[ \t]*(.*)$', front, re.M))
        if fields.get('type') != 'task' or fields.get('status') in ('done', 'cancelled'):
            continue
        due = fields.get('due', '')
        date.fromisoformat(due)
        title = re.search(r'^# (.+)$', body, re.M)
        if title and fields.get('id'):
            rows.append((due, fields['id'], title.group(1)))
    except (OSError, ValueError):
        continue
rows.sort()
if fmt == 'plain':
    for due, ident, title in rows:
        print(f'{due}  {ident}  {title}')
    sys.exit(0)
if not rows:
    print('No open reminders. Add one: brain remind "text" --on YYYY-MM-DD')
    sys.exit(0)
today = date.today()
def when(due):
    n = (date.fromisoformat(due) - today).days
    if n == 0:
        return 'today'
    if n < 0:
        return f'overdue {-n} day' + ('s' if n < -1 else '')
    return f'in {n} day' + ('s' if n > 1 else '')
table = [(due, when(due), title, ident[:8]) for due, ident, title in rows]
wd = max(len('When'), *(len(r[1]) for r in table))
room = max(20, cols - (10 + 2 + wd + 2 + 2 + 8))
def cut(t):
    return t if fmt == 'wide' or len(t) <= room else t[:room - 1] + '\u2026'
tw = max(len('Reminder'), *(len(cut(r[2])) for r in table))
print(f"{'Due':<10}  {'When':<{wd}}  {'Reminder':<{tw}}  ID")
for due, w, title, short in table:
    print(f'{due:<10}  {w:<{wd}}  {cut(title):<{tw}}  {short}')
PY
    ;;
  done)
    [ "$#" -eq 2 ] || usage
    # Only close reminders, not arbitrary queue tasks.
    # A full id or a unique prefix of 8+ characters, as `list` shows it.
    [ "${#2}" -ge 8 ] || { echo "remind: give at least 8 characters of the id" >&2; exit 1; }
    ids="$(bash "$ROOT/scripts/remind.sh" list --plain | awk -v p="$2" 'index($2, p) == 1 { print $2 }')"
    case "$(printf '%s\n' "$ids" | grep -c .)" in
      0) echo "remind: no open reminder with id $2" >&2; exit 1 ;;
      1) ;;
      *) echo "remind: $2 matches more than one reminder; give more of the id" >&2; exit 1 ;;
    esac
    exec bash "$ROOT/scripts/queue.sh" "done" "$ids"
    ;;
  *)
    title="$1"; shift
    due='' scope='' force=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --on|--scope) [ "$#" -ge 2 ] || usage
          if [ "$1" = --on ]; then due="$2"; else scope="$2"; fi; shift 2 ;;
        --force) force=1; shift ;;
        *) usage ;;
      esac
    done
    [ -n "$title" ] && [ -n "$due" ] || usage
    python3 - "$due" "$force" <<'PY' || exit 2
import datetime, re, sys
s, force = sys.argv[1:]
try:
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', s): raise ValueError('format')
    day = datetime.date.fromisoformat(s)
    if day < datetime.date.today() and force != '1':
        raise ValueError('past date (use --force)')
except ValueError as e:
    print(f'remind: invalid due date: {s} ({e})', file=sys.stderr)
    sys.exit(2)
PY
    args=(add "$title" --due "$due")
    [ -z "$scope" ] || args+=(--scope "$scope")
    exec bash "$ROOT/scripts/queue.sh" "${args[@]}"
    ;;
esac
