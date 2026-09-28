#!/usr/bin/env bash
set -euo pipefail

FACTORY=""
STRICT=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --factory) FACTORY="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    -h|--help) echo "usage: factory-doctor.sh --factory PATH [--strict]"; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; exit 2 ;;
  esac
done
FACTORY="${FACTORY_PATH:-${FACTORY:-$PWD}}"
FACTORY="$(cd "$FACTORY" && pwd)"
JSON="$FACTORY/factory.json"
[ -f "$JSON" ] || { echo "FAIL missing factory.json: $FACTORY"; exit 1; }

# bash 3.2 (macOS default) has no mapfile/readarray: same result via read.
PROFILE_BIN="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/factory-profile.py"
PROFILE_JSON="$(python3 "$PROFILE_BIN" "$FACTORY")" || exit 1
VALUES=()
while IFS= read -r _fb_line; do VALUES+=("$_fb_line"); done < <(python3 - "$PROFILE_JSON" <<'PY'
import json, sys
d=json.loads(sys.argv[1])
print(d['project'])
for key in ('dev','next','live'):
 print(d['lanes'][key] or '')
print(d['releases'] or '')
print(d['test'])
print('yes' if d['distribution'] else '')
print(d['profile'])
PY
)
PROJECT=${VALUES[0]:-}
DEV=${VALUES[1]:-}; NEXT=${VALUES[2]:-}; LIVE=${VALUES[3]:-}; RELEASES=${VALUES[4]:-}; TEST_CMD=${VALUES[5]:-}; DISTRIBUTION=${VALUES[6]:-}; PROFILE=${VALUES[7]:-}
errors=0; warnings=0
fail(){ echo "FAIL $*"; errors=$((errors+1)); }
note(){ echo "NOTE $*"; warnings=$((warnings+1)); }
check_dir(){ [ -d "$1" ] || fail "missing directory: $2 ($1)"; }
check_file(){ [ -f "$1" ] || fail "missing file: $2 ($1)"; }

[ -n "$PROJECT" ] || fail "factory.json has no project"
check_dir "$FACTORY/R&D" 'R&D'
[ -n "$RELEASES" ] && check_dir "$RELEASES" releases || fail "factory.json has no releases root"
check_file "$FACTORY/README.md" README.md
for lane in dev next live; do
  case "$lane" in
    dev) raw="${DEV:-}" ;;
    next) raw="${NEXT:-}" ;;
    live) raw="${LIVE:-}" ;;
  esac
  [ -n "$raw" ] || { fail "factory.json has no $lane lane"; continue; }
  p="$raw"
  check_dir "$p" "$lane lane"
  [ -d "$p/.git" ] || [ -f "$p/.git" ] || fail "$lane lane is not a git worktree: $p"
  if [ "$lane" != dev ] && [ -n "$(git -C "$p" status --porcelain 2>/dev/null || true)" ]; then
    note "$lane lane has uncommitted changes"
  fi
done
if [ "$PROFILE" = standard ]; then
  for d in dashboards decisions logs experiments captures renders; do check_dir "$FACTORY/R&D/$d" "R&D/$d"; done
fi
if ! find "$FACTORY" -maxdepth 2 -type f \( -name VERSION -o -name '*_VERSION' \) -print -quit | grep -q .; then
  if ! python3 - "$FACTORY" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
found=False
for p in root.glob('*/package.json'):
    try:
        found = bool(json.loads(p.read_text()).get('version'))
    except Exception:
        pass
    if found:
        break
raise SystemExit(0 if found else 1)
PY
  then
    note "no version file or package version found"
  fi
fi
if [ "$PROFILE" = standard ]; then
  [ -n "$TEST_CMD" ] || note "factory.json has no commands.test; automated test gate is not configured"
  [ -n "$DISTRIBUTION" ] || note "factory.json has no distribution block; how a user installs, updates and removes the tool is not written down"
fi
# A succeeded factory lives in its successor's legacy directory. Refuse a
# successor whose lanes still depend on the predecessor's repository, or
# archiving the predecessor would strand the successor's history.
while IFS= read -r _line; do
  case "$_line" in FAIL\ *) fail "${_line#FAIL }" ;; NOTE\ *) note "${_line#NOTE }" ;; esac
done < <(python3 - "$FACTORY" "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" <<'PY'
import importlib.util, json, os, subprocess, sys
from pathlib import Path
root, bin_dir = Path(sys.argv[1]), Path(sys.argv[2])
layout = json.load(open(bin_dir.parent / "layout.json"))
spec = importlib.util.spec_from_file_location("factory_profile", bin_dir / "factory-profile.py")
profile = importlib.util.module_from_spec(spec); spec.loader.exec_module(profile)
d = json.loads((root / "factory.json").read_text())
raw = d.get("legacy_factory")
if not raw:
    sys.exit()
legacy = Path(os.path.expanduser(raw)); legacy = legacy if legacy.is_absolute() else root / legacy
legacy_home = (root / layout["legacyDir"]).resolve()
if not legacy.exists():
    print(f"FAIL legacy_factory does not exist: {legacy}")
    sys.exit()
legacy = legacy.resolve()
if legacy_home not in legacy.parents:
    print(f"NOTE legacy_factory lives outside {layout['legacyDir']}/ ({legacy}); a succeeded factory is archived there")
if legacy.parent == root.resolve().parent and (legacy / "factory.json").exists():
    print("NOTE the succeeded factory still sits beside the others, so the registry lists it as active")
try:
    lanes = profile.normalize(root)["lanes"]
except (OSError, ValueError, TypeError, KeyError):
    lanes = {}
for name, lane in lanes.items():
    if not lane:
        continue
    p = Path(lane)
    try:
        common = subprocess.run(["git", "-C", str(p), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception:
        continue
    if common and (legacy == Path(common).resolve() or legacy in Path(common).resolve().parents):
        print(f"FAIL {name} lane keeps its git history inside the legacy factory ({common}); move the repository into this factory first")
PY
)

# The andon: what is stopped or waiting. factory-obeya.sh reads it; the doctor
# only reports what the obeya's JSON summary says, so both agree by construction.
_obeya="$(bash "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/factory-obeya.sh" --factory "$FACTORY" --json 2>/dev/null || true)"
if [ -z "$_obeya" ]; then
  note "factory-obeya.sh could not read this factory"
else
  while IFS= read -r _line; do [ -n "$_line" ] && note "$_line"; done < <(python3 - "$_obeya" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
a = d.get("andon")
if a is None:
    print("no andon; create it with factory-obeya.sh --init")
else:
    if a["stale"]:
        print(f'andon: {a["stale"]} cord(s) pulled longer than the stale threshold (oldest {a["oldestDays"]} days)')
    if a["undated"]:
        print(f'andon: {a["undated"]} cord(s) without a since-date')
PY
)
fi
if [ "$STRICT" = true ] && [ "$warnings" -gt 0 ]; then errors=$((errors+warnings)); fi
if [ "$errors" -gt 0 ]; then echo "factory-doctor: FAIL ($errors error(s), $warnings warning(s))"; exit 1; fi
echo "factory-doctor: PASS ($warnings warning(s))"
