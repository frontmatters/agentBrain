#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test.sh — project-init applies a decision; it must not invent one.
#
# Everything here is about restraint. The skill writes to a git repository and
# reads a note it does not own, so the failures that matter are: touching the
# global identity, half-applying a type that is not finished, rewriting a
# licence, and falling over on a machine that has defined no types at all.
#
# The types come from a fixture, never from the running machine's vault: a test
# that reads the owner's real note would pass or fail depending on whose laptop
# it runs on.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
BIN="$HERE/bin/project-init"

pass=0; fail=0
t_ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
t_bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-project-init.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# A fixture HOME, so a stray --global can be detected instead of damaging the
# machine that runs the suite.
export HOME="$TMP/home"
mkdir -p "$HOME"
printf '[user]\n\tname = UNTOUCHED\n\temail = untouched@example.invalid\n' > "$HOME/.gitconfig"

TYPES="$TMP/types.md"
cat > "$TYPES" <<'EOF'
---
date: 2026-01-01
type: user-preference
id: 00000000-0000-5000-8000-000000000000
project-types-default: published
project-types:
  published:
    label: Published
    git-name: Pub Brand
    git-email: pub@example.invalid
    license-holder: Pub Brand
    visibility: public
    detect: []
  storefront:
    label: Storefront
    git-name: Store Brand
    git-email: ""
    license-holder: Store Brand
    visibility: public
    detect: [Package.swift, "*.xcodeproj"]
  incoming:
    label: Incoming
    git-name: In Brand
    git-email: in@example.invalid
    license-holder: ""
    visibility: private
    detect: []
---

# fixture
EOF

repo() { local d="$TMP/$1"; mkdir -p "$d"; git -C "$d" init -q; printf '%s' "$d"; }
run()  { PROJECT_TYPES_FILE="$TYPES" bash "$BIN" --no-rnd "$@" 2>&1; }

# --- 1. the types are read, and an empty field does not shift the columns ----
# Regression: the rows were tab separated, bash `read` collapses runs of tabs,
# and the type with no address moved every later column one to the left.
out="$(run --list)"
case "$out" in
	*"storefront"*"<no email>"*"public"*) t_ok "a type with an empty field keeps its columns" ;;
	*) t_bad "empty field shifted the columns: $(printf '%s' "$out" | grep storefront)" ;;
esac
case "$out" in *"(default)"*) t_ok "the default is marked" ;; *) t_bad "no default marked" ;; esac

# --- 2. the default applies when nothing identifies the repo ------------------
R="$(repo plain)"
run --dir "$R" >/dev/null
[ "$(git -C "$R" config --local user.email)" = "pub@example.invalid" ] \
	&& t_ok "the default type is applied to an unmarked repo" \
	|| t_bad "default not applied"

# --- 3. the global identity is never touched ---------------------------------
# This is the one mistake that reaches beyond the repository being set up.
[ "$(git config --global user.email)" = "untouched@example.invalid" ] \
	&& t_ok "the global git identity is untouched" \
	|| t_bad "project-init wrote to the global git config"

# --- 4. a marker identifies the exception to the default ---------------------
R="$(repo app)"; mkdir -p "$R/MyApp.xcodeproj"
case "$(run --dir "$R")" in
	*"Storefront"*) t_ok "a glob marker identifies the type" ;;
	*) t_bad "glob marker did not match" ;;
esac

# --- 5. an incomplete type is skipped, never half applied --------------------
# A name without an address produces commits nobody can attribute back.
R="$(repo swift)"; : > "$R/Package.swift"
out="$(run --dir "$R")"
case "$out" in *"no git-email"*) t_ok "an incomplete type is reported" ;; *) t_bad "did not report the missing address" ;; esac
[ -z "$(git -C "$R" config --local user.name || true)" ] \
	&& t_ok "an incomplete type sets no identity at all" \
	|| t_bad "wrote a name without an address"

# --- 6. an explicit type beats detection -------------------------------------
R="$(repo override)"; mkdir -p "$R/MyApp.xcodeproj"
case "$(run --dir "$R" --type incoming)" in
	*"Incoming"*) t_ok "--type wins over detection" ;;
	*) t_bad "--type was ignored" ;;
esac

# --- 7. an unknown type is refused and says what exists ----------------------
out="$(run --dir "$(repo bogus)" --type nope 2>&1)"
case "$out" in
	*"unknown type"*published*) t_ok "an unknown type is refused and lists the known ones" ;;
	*) t_bad "unknown type not handled" ;;
esac

# --- 8. a LICENSE is read, never rewritten -----------------------------------
R="$(repo licensed)"; printf 'Copyright (c) 2020 Someone Else\n' > "$R/LICENSE"
before="$(shasum -a 256 "$R/LICENSE" | cut -d' ' -f1)"
out="$(run --dir "$R")"
[ "$(shasum -a 256 "$R/LICENSE" | cut -d' ' -f1)" = "$before" ] \
	&& t_ok "an existing LICENSE is left byte-identical" \
	|| t_bad "rewrote the LICENSE"
case "$out" in *"left untouched"*) t_ok "the licence mismatch is reported" ;; *) t_bad "silent about the licence holder" ;; esac

# --- 9. a dry run writes nothing ---------------------------------------------
R="$(repo dry)"
run --dir "$R" --dry-run >/dev/null
[ -z "$(git -C "$R" config --local user.email || true)" ] \
	&& t_ok "a dry run sets no identity" \
	|| t_bad "dry run wrote the git config"

# --- 10. a machine with no types defined still works -------------------------
# Zero configuration is a supported state: a fresh user has no vault note yet.
R="$(repo notypes)"
out="$(PROJECT_TYPES_FILE="$TMP/does-not-exist.md" bash "$BIN" --dir "$R" --no-rnd 2>&1)"
case "$out" in *"no project types defined"*) t_ok "no types defined is reported, not an error" ;; *) t_bad "did not handle a machine without types"; esac
[ -z "$(git -C "$R" config --local user.email || true)" ] \
	&& t_ok "without types the repository identity is left alone" \
	|| t_bad "invented an identity"

# --- 11. running twice changes nothing ---------------------------------------
R="$(repo twice)"
run --dir "$R" >/dev/null
case "$(run --dir "$R")" in
	*"already"*) t_ok "a second run reports the identity is already set" ;;
	*) t_bad "second run did not report an existing identity" ;;
esac

# Never a verdict without a denominator.
if [ "$((pass + fail))" -lt 15 ]; then
	printf 'project-init: only %d assertion(s) ran, expected at least 15\n' "$((pass + fail))" >&2
	exit 1
fi
printf 'project-init: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
