#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# rename-space.sh — give a space a neutral slug.
#
# A slug is free text, and three of the spaces on this machine were created
# with the owner's name as the slug. The slug then travels everywhere the
# space is mentioned: the directory, every path under it, `space:` fields in
# its notes, .space-map.json, the list-spaces output. Sealing the space keeps
# its CONTENT out of the personal vault; it does nothing for a name that sits
# in the path itself.
#
# What a rename touches, in order:
#   1. the directory            local/spaces/<old>/ -> local/spaces/<new>/
#   2. the passport             slug:, and the slug inside tags:
#   3. every note id            UUID5 is derived from the path, so all change
#   4. slug tokens in the space `space: <old>` fields, `--space <old>` commands
#   5. path references          spaces/<old>/ anywhere else in the vault
#   6. .space-map.json          rebuilt from the passports
#   7. .active-space            follows, if it pointed at the old slug
#   8. one commit in the space  so its own history records the rename
#
# Not touched: the remote. Its repository name may carry the old slug too;
# `sync:` keeps working because the URL does not change. Rename it on the host
# when you want the name gone there as well.
#
# Usage:
#   rename-space.sh <old-slug> [--to <new-slug>] [--dry-run]
#     --to       default is the neutral form: sp-<first 8 hex of space-id>
#     --dry-run  print every step, change nothing
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# Physical path on purpose. local/ is a symlink to the vault, and BSD grep does
# not follow a symlink handed to it as an argument: every recursive search
# below would report zero matches and the rename would quietly skip the vault.
VAULT="$(cd -P "$ROOT/vault" && pwd -P)"
OLD=""; NEW=""; DRY=0
while [ $# -gt 0 ]; do
	case "$1" in
	--to) NEW="${2:-}"; shift 2 ;;
	--dry-run) DRY=1; shift ;;
	-h | --help) sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
	-*) echo "rename-space: unknown option: $1" >&2; exit 2 ;;
	*) OLD="$1"; shift ;;
	esac
done
[ -n "$OLD" ] || { echo "rename-space: need <old-slug> (try --help)" >&2; exit 2; }

OLD_DIR="$VAULT/spaces/$OLD"
[ -f "$OLD_DIR/index.md" ] || { echo "rename-space: no space at spaces/$OLD" >&2; exit 1; }

field() { sed -n '2,/^---$/p' "$OLD_DIR/index.md" | sed -n "s/^$1:[[:space:]]*//p" | head -1 | tr -d '"'; }
SPACE_ID="$(field space-id)"
[ -n "$SPACE_ID" ] || { echo "rename-space: passport has no space-id; cannot derive a neutral slug" >&2; exit 1; }
[ -n "$NEW" ] || NEW="sp-$(printf '%s' "$SPACE_ID" | tr -d '-' | cut -c1-8 | tr 'A-F' 'a-f')"
case "$NEW" in
*/* | *..* | "") echo "rename-space: invalid new slug: '$NEW'" >&2; exit 2 ;;
esac
NEW_DIR="$VAULT/spaces/$NEW"
[ "$OLD" != "$NEW" ] || { echo "rename-space: '$OLD' already has that slug" >&2; exit 0; }
[ ! -e "$NEW_DIR" ] || { echo "rename-space: spaces/$NEW already exists" >&2; exit 1; }

# The space must be committed first: a rename on top of uncommitted work makes
# the space's own history unable to say what the rename changed. .DS_Store is
# Finder noise and does not count.
if [ -d "$OLD_DIR/.git" ]; then
	dirty="$(git -C "$OLD_DIR" status --porcelain 2>/dev/null | grep -v 'DS_Store' || true)"
	[ -z "$dirty" ] || { echo "rename-space: spaces/$OLD has uncommitted changes; commit or stash them first:" >&2; printf '%s\n' "$dirty" | sed 's/^/   /' >&2; exit 1; }
fi

# Everything that will change, counted before anything moves.
# `grep` exits 1 when it finds nothing, and under pipefail that would end the
# script right here, silently, with the space untouched. Zero is an answer.
notes="$(find "$OLD_DIR" -name '*.md' -not -path '*/.git/*' | wc -l | tr -d ' ')"
inside="$({ grep -rIlE --exclude-dir=.git -- "^space: *$OLD *\$|spaces/$OLD|(AGENTBRAIN_CONTEXT|--space|--context)[= ]$OLD|\"space\": *\"$OLD\"|^tags:.*[\[, ]${OLD}[],]" "$OLD_DIR" 2>/dev/null || true; } | wc -l | tr -d ' ')"
outside="$({ grep -rIlE --exclude-dir=.git --exclude-dir=spaces -- "spaces/$OLD|\[\[${OLD}[]|/#]|^space: *$OLD *\$" "$VAULT" 2>/dev/null || true
             find "$VAULT/spaces" -maxdepth 1 -type f -print0 2>/dev/null | xargs -0 grep -IlE -- "spaces/$OLD|\[\[${OLD}[]|/#]" 2>/dev/null || true; } | wc -l | tr -d ' ')"

say() { printf '%s\n' "$*" >&2; }
say "rename-space: spaces/$OLD -> spaces/$NEW"
say "  notes to re-id:        $notes"
say "  files inside using it:  $inside"
say "  vault files using it:   $outside"
[ "$DRY" -eq 0 ] || { say "  (dry run: nothing changed)"; exit 0; }

# 1. the directory
mv "$OLD_DIR" "$NEW_DIR"

# 2. the passport
python3 - "$NEW_DIR/index.md" "$OLD" "$NEW" <<'PY'
import pathlib, re, sys
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
s = re.sub(r"^slug:\s*.*$", f"slug: {new}", s, count=1, flags=re.M)
s = re.sub(r"^(tags:\s*\[.*)\b" + re.escape(old) + r"\b(.*\])$", rf"\g<1>{new}\g<2>", s, count=1, flags=re.M)
p.write_text(s)
PY

# 4. the slug where it is an IDENTIFIER. Not every token: a slug that is also
#    the owner's name appears in LDAP base DNs, domain names, e-mail addresses
#    and source paths, and rewriting those would corrupt the very content the
#    space exists to keep. Measured before this was narrowed: 240 hits in one
#    space, of which perhaps 20 were the slug.
#
#    The same rules run inside the space and across the rest of the vault,
#    including loose files directly under spaces/ (a README there linked to
#    the space by slug and went dead on the first rename).
rewrite_identifiers() { # <file>
	python3 - "$1" "$OLD" "$NEW" <<'PY'
import pathlib, re, sys
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
o = re.escape(old); end = r"(?![A-Za-z0-9_-])"
rules = [
    (r"^(space:\s*)" + o + r"\s*$",                              r"\g<1>" + new),  # frontmatter field
    (r"(spaces/)" + o + end,                                      r"\g<1>" + new),  # path
    (r"((?:AGENTBRAIN_CONTEXT|--space|--context)[= ])" + o + end, r"\g<1>" + new),  # commands
    (r'("space":\s*")' + o + r'(")',                              r"\g<1>" + new + r"\g<2>"),  # json
    (r"(\[\[)" + o + r"(?=[\]|/#])",                              r"\g<1>" + new),  # wiki-link to the space
]
s = p.read_text(errors="surrogateescape")
for pat, rep in rules:
    s = re.sub(pat, rep, s, flags=re.M)
def tags(m):  # the bare slug inside a tags: list, and nowhere else
    return re.sub(r"(?<![A-Za-z0-9_-])" + o + end, new, m.group(0))
s = re.sub(r"^tags:\s*\[.*\]\s*$", tags, s, flags=re.M)
p.write_text(s, errors="surrogateescape")
PY
}
while IFS= read -r f; do rewrite_identifiers "$f"
done < <(grep -rIl --exclude-dir=.git -- "$OLD" "$NEW_DIR" 2>/dev/null || true)

# 3. note ids follow the path
reid=0
while IFS= read -r f; do
	grep -q '^id: ' "$f" || continue
	# Relative to the checkout. uuid5-gen.sh folds vault/ to local/, the spelling
	# every id was derived from. $f is a physical path, so strip $NEW_DIR.
	rel="vault/spaces/$NEW/${f#"$NEW_DIR"/}"; rel="${rel%.md}"
	want="$(bash "$ROOT/scripts/uuid5-gen.sh" "$rel")"
	sed -i.bak "s/^id: .*/id: $want/" "$f" && rm -f "$f.bak"
	reid=$((reid + 1))
done < <(find "$NEW_DIR" -name '*.md' -not -path '*/.git/*')

# 5. identifiers elsewhere: the vault minus spaces/, plus the loose files in spaces/
while IFS= read -r f; do rewrite_identifiers "$f"
done < <({ grep -rIl --exclude-dir=.git --exclude-dir=spaces -- "$OLD" "$VAULT" 2>/dev/null || true
           find "$VAULT/spaces" -maxdepth 1 -type f -print0 2>/dev/null | xargs -0 grep -Il -- "$OLD" 2>/dev/null || true; })

# 6. the map, when this brain has one
[ -f "$VAULT/.space-map.json" ] && bash "$ROOT/scripts/build-space-map.sh" >/dev/null 2>&1 || true

# 7. the active space follows
if [ -f "$VAULT/.active-space" ] && [ "$(cat "$VAULT/.active-space")" = "$OLD" ]; then
	printf '%s\n' "$NEW" > "$VAULT/.active-space"
fi

# 8. the space records its own rename
if [ -d "$NEW_DIR/.git" ]; then
	git -C "$NEW_DIR" add -A >/dev/null 2>&1
	git -C "$NEW_DIR" -c commit.gpgsign=false commit -q -m "Rename space slug to $NEW" ||
		say "  warning: the space did not record the rename (see above); commit it by hand."
fi

say "rename-space: done. re-derived $reid id(s)."
remote="$(field sync 2>/dev/null || true)"
case "$remote" in
*"$OLD"*) say "  note: sync remote still carries the old slug in its URL; rename the repository on the host when you want it gone there too." ;;
esac
