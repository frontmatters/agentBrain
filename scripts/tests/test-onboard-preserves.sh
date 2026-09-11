#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-onboard-preserves.sh — the onboard wizard owns a few answer bullets, not
# the preference files.
#
# The regression: write_pref rebuilt each file from its own bullets. Preference
# notes get enriched over time with headings, tables, code blocks, prose and
# [[links]], and every one of those was dropped. Measured on a real identity.md
# the day this was found: 0 of 43 content lines survived, and a bullet whose
# sentence ran onto the next line was left truncated mid-sentence.
#
# It is not enough to assert the answers are written. The assertion is that
# nothing else moved: byte for byte, the file after a run must still contain
# every line it had before.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-onboard-preserves.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PREFS="$TMP/vault/preferences/personal"
mkdir -p "$PREFS"
ln -sfn "$ROOT_DIR/system" "$TMP/system"
ln -sfn "$ROOT_DIR/scripts" "$TMP/scripts"

run_wizard() {
	VAULT="$TMP" AB_WIZARD_DEFAULTS=1 AB_WIZARD_PLAIN=1 \
		bash "$ROOT_DIR/scripts/onboard-wizard.sh" >"$TMP/run.log" 2>&1
}

# A preference file shaped like the real ones: frontmatter, headings, a table, a
# fenced code block, a wiki link, prose, and one bullet the wizard owns.
cat > "$PREFS/identity.md" <<'EOF'
---
date: 2026-01-01
type: preference
id: 00000000-0000-5000-8000-000000000000
---

# Identity

## Name

- **A Person** — used where authorship genuinely belongs to a
  person: LICENSE files, copyright lines, colophons.

## Git identities

| Case | Identity | Applies to |
| --- | --- | --- |
| Storefront | `BrandA` | end-user software |

```sh
git config user.name "BrandA"
- Name: this bullet lives in a code fence and is an example, not an answer
```

See [[author-identity-by-project-type]] for the full routing.

- Verbosity: terse

## Credentials

Tokens never live in the brain. See [[secrets-management]].
EOF

cp "$PREFS/identity.md" "$TMP/identity.orig"
run_wizard || true

# --- 1. nothing is lost ------------------------------------------------------
missing=0
while IFS= read -r line; do
	[ -n "$line" ] || continue
	grep -Fqx -- "$line" "$PREFS/identity.md" || { missing=$((missing+1)); printf '    lost: %s\n' "$line" >&2; }
done < "$TMP/identity.orig"
[ "$missing" -eq 0 ] \
	&& ok "every line of the original survives the run" \
	|| bad "$missing line(s) were destroyed"

# --- 2. the structure is intact, not just the text ---------------------------
for marker in '## Credentials' '| Storefront |' '[[secrets-management]]' '```sh'; do
	grep -Fq -- "$marker" "$PREFS/identity.md" \
		&& ok "kept: $marker" \
		|| bad "lost: $marker"
done

# --- 3. a bullet inside a code fence is an example, not an answer ------------
# It matches "- Name:" but must never be rewritten: it is documentation.
grep -Fq -- '- Name: this bullet lives in a code fence' "$PREFS/identity.md" \
	&& ok "a bullet inside a fence is left alone" \
	|| bad "rewrote a bullet inside a code fence"

# --- 4. the answers actually land --------------------------------------------
grep -q '^- Name: ' "$PREFS/identity.md" \
	&& ok "the wizard's own answers are written" \
	|| bad "no answer bullet was written"

# --- 5. running twice changes nothing ----------------------------------------
# An append-only merge duplicates on every run, which is the other way to lose
# a file: by burying it.
before="$(shasum -a 256 "$PREFS/identity.md" | cut -d' ' -f1)"
run_wizard || true
after="$(shasum -a 256 "$PREFS/identity.md" | cut -d' ' -f1)"
[ "$before" = "$after" ] \
	&& ok "a second run is a no-op" \
	|| bad "a second run changed the file"

# --- 6. an owned bullet is updated in place, never duplicated ----------------
sed -i '' 's/^- Verbosity: .*/- Verbosity: EDITED-BY-HAND/' "$PREFS/identity.md" 2>/dev/null \
	|| sed -i 's/^- Verbosity: .*/- Verbosity: EDITED-BY-HAND/' "$PREFS/identity.md"
run_wizard || true
n="$(grep -c '^- Verbosity:' "$PREFS/identity.md")"
[ "$n" = "1" ] \
	&& ok "an owned bullet stays single after a rerun" \
	|| bad "expected 1 Verbosity bullet, found $n"

printf 'onboard-preserves: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
