#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-rename-space.sh — a rename leaves no trace of the old slug and no broken id.
#
# Runs against the real vault with a throwaway slug, the way test-new-space.sh
# does, because uuid5-gen and validate-note-id derive ids from the checkout's
# real local/ path.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
V="$ROOT/vault"
# Unique per run: two doctors at once (a publish and a push) share this vault,
# and a fixed slug made them rename each other's fixture.
OLD="__rntest-$$-owner__"; NEW="__rntest-$$-neutral__"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
cleanup() { rm -rf "$V/spaces/$OLD" "$V/spaces/$NEW"; rm -f "$V/references/__rntest-$$-ref.md" "$V/spaces/.rntest-$$-err" "$V/spaces/__rntest-$$-loose.md"; }
trap cleanup EXIT
cleanup

bash "$ROOT/scripts/new-space.sh" "$OLD" --owner "Rntest Owner" --relation client --sync none >/dev/null 2>&1 \
	|| { bad "scaffold" "new-space.sh failed"; exit 1; }
mkdir -p "$V/spaces/$OLD/notes"
cat > "$V/spaces/$OLD/notes/plan.md" <<EOF
---
date: 2026-09-04
type: project
space: $OLD
tags: [test]
id: $(bash "$ROOT/scripts/uuid5-gen.sh" "local/spaces/$OLD/notes/plan")
---
Open with AGENTBRAIN_CONTEXT=$OLD. Not the word ${OLD}ish.
LDAP_BASE_DN=dc=$OLD,dc=local and mail to jane@$OLD.nl stay as they are.
EOF
mkdir -p "$V/references"
printf -- '---\ndate: 2026-09-04\ntype: reference\ntags: [test]\nid: %s\n---\nsee spaces/%s/notes/plan.md and [[%s]]\n' \
	"$(bash "$ROOT/scripts/uuid5-gen.sh" local/references/__rntest-$$-ref)" "$OLD" "$OLD" > "$V/references/__rntest-$$-ref.md"
printf -- '# loose\n\n- [[%s]] is a space\n' "$OLD" > "$V/spaces/__rntest-$$-loose.md"
git -C "$V/spaces/$OLD" add -A >/dev/null 2>&1 && git -C "$V/spaces/$OLD" -c commit.gpgsign=false commit -qm seed >/dev/null 2>&1

# dry run changes nothing
bash "$ROOT/scripts/rename-space.sh" "$OLD" --to "$NEW" --dry-run >/dev/null 2>&1
[ -d "$V/spaces/$OLD" ] && [ ! -e "$V/spaces/$NEW" ] && ok "dry-run" "nothing moved" || bad "dry-run" "dry run moved something"

# dirty space is refused
printf 'x\n' >> "$V/spaces/$OLD/notes/plan.md"
bash "$ROOT/scripts/rename-space.sh" "$OLD" --to "$NEW" >/dev/null 2>&1 && bad "refuse-dirty" "renamed over uncommitted work" || ok "refuse-dirty" "uncommitted work is refused"
git -C "$V/spaces/$OLD" checkout -q -- notes/plan.md

# the rename
bash "$ROOT/scripts/rename-space.sh" "$OLD" --to "$NEW" >/dev/null 2>"$V/spaces/.rntest-$$-err" || bad "runs" "rename-space.sh exited non-zero"
[ -d "$V/spaces/$NEW" ] && [ ! -e "$V/spaces/$OLD" ] && ok "moved" "directory renamed" || bad "moved" "directory not renamed"
grep -q "^slug: $NEW$" "$V/spaces/$NEW/index.md" && ok "passport" "slug field updated" || bad "passport" "slug field not updated"
grep -q "^space: $NEW$" "$V/spaces/$NEW/notes/plan.md" && ok "space-field" "note space: field follows" || bad "space-field" "note still names the old slug"
grep -q "AGENTBRAIN_CONTEXT=$NEW" "$V/spaces/$NEW/notes/plan.md" && ok "prose-token" "a command in prose follows" || bad "prose-token" "command still names the old slug"
grep -q "${OLD}ish" "$V/spaces/$NEW/notes/plan.md" && ok "word-boundary" "a longer word containing the slug is left alone" || bad "word-boundary" "substring inside a longer word was rewritten"
grep -q "dc=$OLD,dc=local" "$V/spaces/$NEW/notes/plan.md" && grep -q "jane@$OLD.nl" "$V/spaces/$NEW/notes/plan.md" &&
	ok "content-kept" "the owner's name in a DN and a domain is left alone" || bad "content-kept" "technical content carrying the name was rewritten"
grep -q "spaces/$NEW/notes" "$V/references/__rntest-$$-ref.md" && ok "vault-path" "path reference elsewhere in the vault follows" || bad "vault-path" "vault reference still points at the old path"
grep -q "\[\[$NEW\]\]" "$V/references/__rntest-$$-ref.md" && ok "wikilink" "a wiki-link to the space follows" || bad "wikilink" "wiki-link to the space went dead"
grep -q "\[\[$NEW\]\]" "$V/spaces/__rntest-$$-loose.md" && ok "loose-in-spaces" "a loose file under spaces/ follows" || bad "loose-in-spaces" "a file directly under spaces/ was skipped"

for f in "$V/spaces/$NEW/index.md" "$V/spaces/$NEW/notes/plan.md"; do
	bash "$ROOT/scripts/validate-note-id.sh" "$f" >/dev/null 2>&1 || bad "ids" "id no longer matches path: ${f#"$V"/}"
done
[ "$fail" -eq 0 ] && ok "ids" "every note id re-derived from the new path"

# Not `git log | grep -q`: under pipefail, grep -q closing early gives git a
# SIGPIPE and the pipeline fails on timing. Ask git directly.
[ -n "$(git -C "$V/spaces/$NEW" log --oneline --grep="Rename space slug")" ] && ok "history" "the space records its own rename" || { bad "history" "no rename commit in the space"; sed "s/^/      /" "$V/spaces/.rntest-$$-err" >&2; }

# nothing in the vault, in or out of the space, names the old slug any more
left="$({ grep -rIlE --exclude-dir=.git -- "^space: *$OLD *\$|spaces/$OLD|AGENTBRAIN_CONTEXT=$OLD" "$V/spaces/$NEW" "$V/references/__rntest-$$-ref.md" 2>/dev/null || true; } | wc -l | tr -d ' ')"
[ "$left" = "0" ] && ok "no-trace" "old slug is no longer used as an identifier anywhere" || bad "no-trace" "$left file(s) still use the old slug as an identifier"

if [ "$fail" -eq 0 ]; then echo "PASS test-rename-space"; else echo "FAIL test-rename-space" >&2; exit 1; fi
