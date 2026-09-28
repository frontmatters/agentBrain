#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-factory-bundle.sh — a release bundles its satellites, and says how many.
#
# A tar that returns 0 can still produce a valid but empty archive: an
# unanchored --exclude meant for files in the root matches every path tar
# walks. So this test counts what lands, and asserts the count, in both
# directions.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0
ok()  { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -n "$TMP" ] || exit 1

# The gate is stubbed, the bundle and checksum logic are the real thing. Copying
# bin/ is what allows that: $ROOT inside the script is its own directory, so a
# stub beside it is the one it calls.
BIN="$TMP/bin"
mkdir -p "$BIN"
cp "$ROOT/system/skills/factory-builder/bin/factory-release.sh" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/factory-test.sh"
chmod +x "$BIN/factory-test.sh" "$BIN/factory-release.sh"

# A satellite that looks like a real plugin repository: what the bundle exists
# to carry is exactly what a bare *.sh would remove.
SAT="$TMP/sat"
mkdir -p "$SAT/plugin-a" "$SAT/plugin-b"
printf 'a\n' > "$SAT/plugin-a/plugin.sh"
printf 'b\n' > "$SAT/plugin-b/plugin.sh"
printf 'readme\n' > "$SAT/README.md"
printf 'build\n' > "$SAT/build.sh"

FAC="$TMP/factory"
mkdir -p "$FAC/releases" "$FAC/next"
printf '1.0.0\n' > "$FAC/next/VERSION"
printf 'lane\n'   > "$FAC/next/main.txt"

# Two working directories, one holding a .sh file. A release must produce the
# same archive from both: exclude patterns belong to tar, and a shell that
# expands them first makes the artifact depend on where the release was run from.
NEUTRAL="$TMP/cwd-neutral"; mkdir -p "$NEUTRAL"
HOSTILE="$TMP/cwd-hostile"; mkdir -p "$HOSTILE"; printf 'x\n' > "$HOSTILE/local.sh"

run_release() { # <cwd>
	( cd "$1" && FACTORY_PATH="$FAC" bash "$BIN/factory-release.sh" ) >/dev/null 2>&1
}

write_factory_json() { # <exclude-json>
	cat > "$FAC/factory.json" <<JSON
{ "project": "fixture",
  "lanes": { "next": "$FAC/next" },
  "bundle": [ { "from": "$SAT", "into": "plugins", "exclude": $1 } ] }
JSON
}

# Counted inside the archive, not in the staging directory: the release step
# removes that directory once it has sealed the tarball, and what the consumer
# receives is the tarball. A count taken on disk measures a directory that is
# about to stop existing, which is how a test can pass while the artifact is
# empty, or fail while it is correct.
ART="$FAC/releases/fixture-v1.0.0.tar.gz"
count_plugins() { tar -tzf "$ART" 2>/dev/null | grep -c 'plugins/.*/plugin\.sh$' | tr -d ' '; }
in_artifact()   { tar -tzf "$ART" 2>/dev/null | grep -q "$1"; }

# ── anchored: the two root files go, the plugins stay ────────────────────────
write_factory_json '["./README.md", "./build.sh"]'
if run_release "$NEUTRAL"; then
	n="$(count_plugins)"
	[ "$n" = "2" ] && ok "anchored" "both plugins landed (2 of 2)" || bad "anchored" "expected 2 plugin.sh, found $n"
	in_artifact 'plugins/README.md' && bad "anchored" "the root README was meant to be excluded" || ok "excluded" "the root files named are gone"
else
	bad "anchored" "the release step failed outright"
fi

# ── bare: the same intent, unanchored, takes the plugins with it ─────────────
# Asserted rather than merely noted: this is the difference the anchor makes,
# and if a future tar makes it go away this test should say so.
write_factory_json '["README.md", "*.sh"]'
run_release "$NEUTRAL"; n_neutral="$(count_plugins)"
[ "$n_neutral" = "0" ] && ok "bare" "an unanchored *.sh empties the bundle (0 of 2), silently" || bad "bare" "expected 0 plugin.sh, found $n_neutral"

# The same release, started one directory to the left. Before set -f the shell
# expanded *.sh into that directory's own filenames, tar was handed excludes
# for files the satellite never had, and all 2 plugins sailed through: the trap
# reversed itself depending on the cwd, which is worse than the trap.
run_release "$HOSTILE"; n_hostile="$(count_plugins)"
[ "$n_hostile" = "$n_neutral" ] \
	&& ok "cwd-independent" "same archive from a cwd holding a .sh ($n_hostile = $n_neutral)" \
	|| bad "cwd-independent" "the artifact depends on the working directory: $n_hostile from a cwd with a .sh, $n_neutral without"

# ── the checksum has to work somewhere else than where it was built ──────────
# shasum writes the path it was handed. An absolute path produces a .sha256 that
# verifies only on the build machine; the consumer is told the file is missing,
# for a file sitting right next to it.
write_factory_json '["./README.md", "./build.sh"]'
run_release "$NEUTRAL"
SUM="$FAC/releases/fixture-v1.0.0.sha256"
if [ -f "$SUM" ]; then
	grep -q '/' "$SUM" && bad "checksum-path" "the .sha256 carries a path, so it is machine-bound: $(cat "$SUM")" || ok "checksum-path" "the .sha256 names the bare filename"
	CONS="$TMP/consumer"; mkdir -p "$CONS"
	cp "$FAC/releases/fixture-v1.0.0.tar.gz" "$SUM" "$CONS/"
	( cd "$CONS" && shasum -a 256 -c "$(basename "$SUM")" ) >/dev/null 2>&1 \
		&& ok "checksum-verify" "a consumer can verify the archive in its own directory" \
		|| bad "checksum-verify" "shasum -c failed where the consumer unpacked it"
else
	bad "checksum-path" "no .sha256 was written at all"
fi

if [ "$fail" -eq 0 ]; then echo "PASS test-factory-bundle"; else echo "FAIL test-factory-bundle" >&2; exit 1; fi
