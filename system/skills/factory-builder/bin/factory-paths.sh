#!/usr/bin/env bash
# factory-paths.sh — one knob per tool for where it keeps its state, and one
# central file to set them all.
#
# Every tool kept its config and data somewhere of its own, set (if at all) by
# a variable of its own, a borrowed XDG_CONFIG_HOME, or nothing at all.
# Moving one meant finding out how. The pattern:
#
#   factory.json  "paths": {"env": "MYTOOL_HOME", "default": "~/.mytool",
#                           "holds": "config, sessions, browser profiles",
#                           "extra": [{"env": ..., "default": ..., "holds": ...}]}
#                 One variable per tool, named <TOOL>_HOME for new tools; "extra"
#                 only for a tool that keeps a second place (secrets: keychains).
#   central file  ~/.config/factories/paths.env: KEY=value lines, only for what
#                 you want elsewhere. Loaded by your shell (a managed block in
#                 the rc) and by every <tool>-next wrapper. A variable already
#                 set in the environment wins, so a one-off override still works.
#
# Usage:
#   factory-paths.sh show [--root DIR]         per tool: variable, default, in effect
#   factory-paths.sh init [--root DIR]         write the central file, every variable
#                                              commented out; adds new tools later
#   factory-paths.sh set VAR PATH [--no-move]  point a tool somewhere else: writes the
#                                              central file and moves the data from the
#                                              old place (refuses if the new one holds data)
#   factory-paths.sh rc                        write or refresh the block in the rc
#   factory-paths.sh loader                    print the loader (factory-link.sh puts it
#                                              in every <tool>-next wrapper)
#   factory-paths.sh --check --factory PATH    factory-doctor's check of one factory
# Env: FACTORY_PATHS_FILE (default ~/.config/factories/paths.env),
#      FACTORY_RC_FILE (default ~/.zshrc), FACTORY_ROOT (default ~/Developer).
set -euo pipefail

HERE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
PATHS_FILE="${FACTORY_PATHS_FILE:-$HOME/.config/factories/paths.env}"
RC_FILE="${FACTORY_RC_FILE:-$HOME/.zshrc}"
ROOT="${FACTORY_ROOT:-$HOME/Developer}"
MODE=""; FACTORY=""; SET_VAR=""; SET_PATH=""; MOVE=true
while [ "$#" -gt 0 ]; do
	case "$1" in
		show|init|rc|loader) MODE="$1"; shift ;;
		set) MODE="set"; SET_VAR="${2:-}"; SET_PATH="${3:-}"; shift 3 || { echo "usage: factory-paths.sh set VAR PATH [--no-move]" >&2; exit 2; } ;;
		--no-move) MOVE=false; shift ;;
		--check) MODE=check; shift ;;
		--factory) FACTORY="$2"; shift 2 ;;
		--root) ROOT="$2"; shift 2 ;;
		-h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "error: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$MODE" ] || { echo "usage: factory-paths.sh show|init|rc|--check --factory PATH" >&2; exit 2; }

# The loader, shared by the rc block and the <tool>-next wrappers: KEY=value
# lines, ~ expanded, surrounding quotes dropped, never overriding a variable
# that is already set. Parsed, never sourced: the file cannot run code.
loader() {
	cat <<'SH'
_fp="${FACTORY_PATHS_FILE:-$HOME/.config/factories/paths.env}"
if [ -f "$_fp" ]; then
  while IFS= read -r _l || [ -n "$_l" ]; do
    case "$_l" in ''|'#'*) continue ;; esac
    _k="${_l%%=*}"; _v="${_l#*=}"
    case "$_k" in *[!A-Z0-9_]*|[0-9]*|'') continue ;; esac
    _v="${_v#\"}"; _v="${_v%\"}"; _v="${_v#\'}"; _v="${_v%\'}"
    case "$_v" in '~'|'~/'*) _v="$HOME${_v#\~}" ;; esac
    eval "[ -n \"\${$_k+x}\" ]" || export "$_k=$_v"
  done < "$_fp"
fi
unset _fp _l _k _v
SH
}

case "$MODE" in
loader) loader; exit 0 ;;
rc)
	BEGIN="# >>> factory paths >>>"; END="# <<< factory paths <<<"
	block="$(printf '%s\n# Managed by factory-paths.sh: loads %s\n' "$BEGIN" "$PATHS_FILE"; loader; printf '%s\n' "$END")"
	touch "$RC_FILE"
	python3 - "$RC_FILE" "$BEGIN" "$END" "$block" <<'PY'
import sys, pathlib
p, b, e, block = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
s = p.read_text()
if b in s and e in s:
    i, j = s.index(b), s.index(e) + len(e)
    s = s[:i] + block + s[j:]
else:
    s = s.rstrip("\n") + ("\n\n" if s.strip() else "") + block + "\n"
p.write_text(s)
PY
	echo "factory-paths: block in $RC_FILE loads $PATHS_FILE (open a new shell to use it)"
	exit 0 ;;
esac

python3 - "$MODE" "$ROOT" "$FACTORY" "$PATHS_FILE" "$HERE" "$SET_VAR" "$SET_PATH" "$MOVE" <<'PY'
import importlib.util, json, os, re, shutil, sys
from pathlib import Path
mode, root, factory, paths_file, here = sys.argv[1], Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4]), Path(sys.argv[5])
set_var, set_path, move = sys.argv[6], sys.argv[7], sys.argv[8] == "true"
ENV = re.compile(r"^[A-Z][A-Z0-9_]*$")

def entries(d):
    p = d.get("paths")
    if not isinstance(p, dict):
        return []
    return [p] + [x for x in (p.get("extra") or []) if isinstance(x, dict)]

def central():
    out = {}
    if paths_file.is_file():
        for line in paths_file.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out

if mode == "check":
    d = json.loads((Path(factory) / "factory.json").read_text())
    p = d.get("paths")
    if p is None:
        if d.get("cli"):
            print("NOTE factory.json has a cli but no paths block: where does the tool keep its state? (factory-paths.sh)")
        sys.exit(0)
    bad = []
    if not isinstance(p, dict):
        bad.append("paths must be an object")
    else:
        for i, e in enumerate(entries(d)):
            where = "paths" if i == 0 else f"paths.extra[{i-1}]"
            if not ENV.match(str(e.get("env", ""))):
                bad.append(f"{where}.env must be an UPPER_CASE variable name")
            if not str(e.get("default", "")).strip():
                bad.append(f"{where}.default is missing")
            if not str(e.get("holds", "")).strip():
                bad.append(f"{where}.holds is missing (what lives there)")
    for b in bad:
        print(f"FAIL {b}")
    sys.exit(1 if bad else 0)

spec = importlib.util.spec_from_file_location("factory_discover", here / "factory-discover.py")
disc = importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)
rows = []
for cfg in disc.factories(root):
    d = json.loads(cfg.read_text())
    for e in entries(d):
        rows.append((cfg.parent.name, e.get("env", ""), e.get("default", ""), e.get("holds", "")))
    if not entries(d) and d.get("cli"):
        rows.append((cfg.parent.name, "", "", "(no paths block yet)"))
known = {r[1] for r in rows if r[1]}
c = central()

if mode == "show":
    print(f"central file: {paths_file}{'' if paths_file.is_file() else '  (not created; factory-paths.sh init)'}")
    print(f"{'FACTORY':<24} {'VARIABLE':<24} {'IN EFFECT':<44} FROM")
    for name, env, default, holds in rows:
        if not env:
            print(f"{name:<24} {'-':<24} {holds}")
            continue
        if os.environ.get(env) and os.environ[env] != os.path.expanduser(c.get(env, "\0")):
            val, src = os.environ[env], "environment"
        elif env in c:
            val, src = c[env], "central file"
        else:
            val, src = default, "default"
        print(f"{name:<24} {env:<24} {val:<44} {src}")
    for k in sorted(set(c) - known):
        print(f"NOTE {paths_file}: {k} is set but no factory declares it")
    sys.exit(0)

if mode == "set":
    declared = {r[1]: r for r in rows if r[1]}
    if set_var not in declared:
        print(f"factory-paths: no factory declares {set_var} (known: {', '.join(sorted(declared)) or 'none'})", file=sys.stderr); sys.exit(2)
    if not set_path:
        print("usage: factory-paths.sh set VAR PATH [--no-move]", file=sys.stderr); sys.exit(2)
    old = Path(os.path.expanduser(c.get(set_var, declared[set_var][2]))).resolve()
    new = Path(os.path.expanduser(set_path)).resolve()
    if old == new:
        print(f"factory-paths: {set_var} is already {new}"); sys.exit(0)
    has = lambda p: p.exists() and (p.is_file() or any(p.iterdir()))
    if move and has(old):
        if has(new):
            print(f"factory-paths: {new} already holds data; not moving {old} over it.", file=sys.stderr)
            print(f"  Empty or remove {new} first, or keep both and run with --no-move to only change the setting.", file=sys.stderr)
            sys.exit(1)
        new.parent.mkdir(parents=True, exist_ok=True)
        if new.exists():
            new.rmdir()  # empty directory: the move takes its place
        shutil.move(str(old), str(new))
        print(f"factory-paths: moved {old} -> {new}")
    elif move:
        print(f"factory-paths: nothing at {old} to move")
    # the setting: replace the variable's line (set or commented), else append
    text = paths_file.read_text() if paths_file.is_file() else ""
    line = f"{set_var}={set_path}"
    pat = re.compile(rf"^\s*#?\s*{set_var}=.*$", re.M)
    text = pat.sub(line, text, count=1) if pat.search(text) else text.rstrip("\n") + f"\n{line}\n"
    paths_file.parent.mkdir(parents=True, exist_ok=True)
    paths_file.write_text(text)
    print(f"factory-paths: {paths_file}: {line}")
    print(f"  Shells already open still have the old value; open a new one (or: exec $SHELL).")
    sys.exit(0)

if mode == "init":
    paths_file.parent.mkdir(parents=True, exist_ok=True)
    existing = paths_file.read_text() if paths_file.is_file() else (
        "# Central paths for the factory tools (factory-paths.sh).\n"
        "# Uncomment a line and set a value to move that tool's state; a variable\n"
        "# already set in the environment still wins. Parsed as KEY=value, never run.\n")
    added = 0
    for name, env, default, holds in rows:
        if env and not re.search(rf"^\s*#?\s*{env}=", existing, re.M):
            existing += f"\n# {name}: {holds}\n# {env}={default}\n"
            added += 1
    paths_file.write_text(existing)
    print(f"factory-paths: {paths_file} ({added} variable(s) added, commented out)")
PY
