#!/usr/bin/env bash
set -euo pipefail
FACTORY="${FACTORY_PATH:-$PWD}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/factory-test.sh"
# bash 3.2 (macOS default) has no mapfile/readarray: same result via read.
V=()
while IFS= read -r _fb_line; do V+=("$_fb_line"); done < <(python3 - "$FACTORY/factory.json" <<'PY'
import json,sys,os
d=json.load(open(sys.argv[1])); print(d.get('project','tool')); print(d.get('lanes',{}).get('next',''))
PY
)
NAME="${V[0]}"; NEXT="${V[1]/#\~/$HOME}"
VERSION=$(python3 - "$NEXT" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
for name in ('VERSION',):
 p=root/name
 if p.is_file():
  print(p.read_text().strip()); break
else:
 p=root/'package.json'
 print(json.loads(p.read_text()).get('version','') if p.is_file() else '')
PY
)
[ -n "$VERSION" ] || { echo 'factory-release: no version source' >&2; exit 2; }

# Release only what live is, on its tag (the factory rule). The archive is cut
# from next, so next and live must be the same commit and that commit must
# carry vVERSION: otherwise the artifact ships something live never had, or a
# version without a tag.
LIVE="$(python3 - "$FACTORY/factory.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); l=d.get('lanes') or d.get('framework') or {}
print(l.get('live',''))
PY
)"; LIVE="${LIVE/#\~/$HOME}"
_next_head="$(git -C "$NEXT" rev-parse HEAD 2>/dev/null || true)"
_live_head="$(git -C "$LIVE" rev-parse HEAD 2>/dev/null || true)"
if [ -z "$_live_head" ] || [ "$_next_head" != "$_live_head" ]; then
  echo "factory-release: live (${_live_head:0:7}) is not next (${_next_head:0:7}); promote first (factory-promote.sh)" >&2; exit 3
fi
if ! git -C "$LIVE" tag --points-at HEAD | grep -qx "v$VERSION"; then
  echo "factory-release: live is not on tag v$VERSION; tag it in dev and promote" >&2; exit 3
fi
OUT="$FACTORY/releases/$NAME-v$VERSION"
rm -rf "$OUT" "$OUT.tar.gz" "$OUT.sha256" "$OUT-manifest.json"
mkdir -p "$OUT"
# --no-recursion matters: a tracked directory/symlink must not pull its
# untracked children into the artifact. Git supplies the tracked file list.
tracked_tar() {
  local source="$1" destination="$2"; shift 2
  git -C "$source" ls-files -z --cached | python3 -c '
import os,sys
root=sys.argv[1]
for p in sys.stdin.buffer.read().split(b"\0"):
 if p and os.path.lexists(os.path.join(os.fsencode(root), p)):
  sys.stdout.buffer.write(p+b"\0")' "$source" |
    tar -C "$source" --no-recursion --null "$@" -T - -cf - | tar -C "$destination" -xf -
}
tracked_tar "$NEXT" "$OUT" --exclude='logs' --exclude='*.log' --exclude='node_modules' --exclude='R&D'

# Bundle satellites declared in factory.json before sealing the archive.
#
# A product can span more than one repository: a tool and the plugins it ships
# with, a runtime and its templates. Lanes belong to the thing you develop while
# using it; a satellite has its own repository and no lanes. Without this step
# the artifact carries whatever the lane happens to hold, which can differ from
# what a developer machine has installed by hand.
#
# factory.json:
#   "bundle": [ { "from": "~/Developer/x-plugins", "into": "plugins",
#                 "exclude": ["./README.md", "./*.sh"] } ]
#
# Anchor every exclude meant for the source root with ./ and mean it when you
# leave one bare. tar applies --exclude to every path it walks, so "*.sh" reads
# as "no shell script anywhere in this tree" and can silently empty a bundle
# whose payload is shell scripts. Bare is correct for artefacts you want gone
# tree-wide ("*.log"), and wrong for anything the bundle exists to carry.
#
# Only tracked files from the source repository are copied. A release must not
# accidentally include untracked working-tree files.
while IFS=$'\t' read -r _b_from _b_into _b_excl; do
  [ -n "$_b_from" ] || continue
  _b_from="${_b_from/#\~/$HOME}"
  if [ ! -d "$_b_from" ]; then
    echo "factory-release: bundle source missing: $_b_from" >&2; exit 2
  fi
  mkdir -p "$OUT/$_b_into"
  _b_args=""
  # set -f first: these patterns are for tar, not for this shell. Unquoted,
  # `*.sh` is globbed against the release process's working directory before
  # tar ever sees it, so the same factory.json would produce a different archive
  # depending on where the release was started from. Word splitting is still
  # wanted here, which is why this is set -f and not a quoted expansion.
  set -f
  for _b_pat in $_b_excl; do _b_args="$_b_args --exclude=$_b_pat"; done
  set +f
  # shellcheck disable=SC2086
  tracked_tar "$_b_from" "$OUT/$_b_into" $_b_args
  echo "factory-release: bundled $(basename "$_b_from") into $_b_into/"
done < <(python3 - "$FACTORY/factory.json" <<'PYB'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for b in d.get("bundle", []):
    src = b.get("from", "")
    into = b.get("into", "")
    if not src or not into:
        continue
    print("\t".join([src, into, " ".join(b.get("exclude", []))]))
PYB
)

tar -C "$FACTORY/releases" -czf "$OUT.tar.gz" "$(basename "$OUT")"
# Record the checksum against the bare filename. shasum writes the path it was
# given, so an absolute path here produces a .sha256 that only verifies on the
# machine that built it: a consumer running `shasum -c` is told the file does
# not exist, for a file sitting right next to it.
( cd "$FACTORY/releases" && shasum -a 256 "$(basename "$OUT.tar.gz")" ) > "$OUT.sha256"
python3 - "$OUT-manifest.json" "$NAME" "$VERSION" "$OUT.tar.gz" <<'PY'
import hashlib,json,pathlib,sys
out,name,version,archive=sys.argv[1:]; p=pathlib.Path(archive)
json.dump({'name':name,'version':version,'archive':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'source':'next'},open(out,'w'),indent=2)
PY
rm -rf "$OUT"
echo "factory-release: $OUT.tar.gz"
