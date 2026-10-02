#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Side-by-side agent CLI updates. Never replace a running version's files at switch time.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { echo 'usage: brain tool-update <pi|claude|opencode|gemini> <stage|check|switch|status|finish|prune|rollback|adopt> [version|--force]' >&2; exit 2; }
[ "$#" -ge 2 ] || usage
tool="$1"; action="$2"; shift 2
[[ "$tool" =~ ^[a-z][a-z0-9-]*$ ]] || usage
profile="$ROOT/system/tool-profiles/$tool.json"
[ -f "$profile" ] || { echo "Unknown tool: $tool" >&2; exit 2; }
if [ "$tool" = claude ]; then NPM_PREFIX="$(npm prefix -g)"; export NPM_PREFIX; fi
# Profiles are committed data, never shell code. Python resolves only known placeholders.
field() { python3 - "$profile" "$1" <<'PY'
import json,os,sys
v=json.load(open(sys.argv[1]))
for key in sys.argv[2].split('.'):
    v=v[key]
if isinstance(v,list):
    print('\n'.join(v))
else:
    print(str(v).replace('${HOME}',os.environ['HOME']).replace('${NPM_PREFIX}',os.environ.get('NPM_PREFIX','')))
PY
}
field_opt() { python3 - "$profile" "$1" <<'PY'
import json,os,sys
v=json.load(open(sys.argv[1])).get(sys.argv[2],'')
print(str(v).replace('${HOME}',os.environ['HOME']))
PY
}
package="$(field package)"; manager="$(field manager)"; link="$(field symlink)"; entry="$(field entry)"; process="$(field process)"
home="${TOOL_VERSIONS_HOME:-$HOME/.local/share/tool-versions}"
base="$home/$tool"
# No untrusted tool/version may escape the staging root or become a manager flag.
version="${1:-}"
valid_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9.-]+)?$ ]]; }
active_file="$base/active" # version of switched staging directory (not a symlink)
active() { [ -f "$active_file" ] && IFS= read -r version < "$active_file" && valid_version "$version"; }
state() { printf '%s/state.json' "$base/$version"; }
get_state() { python3 - "$(state)" "$1" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))[sys.argv[2]])
PY
}
put_state() { python3 - "$(state)" "$1" "$2" <<'PY'
import json,sys
p=sys.argv[1]
try: d=json.load(open(p))
except FileNotFoundError: d={}
d[sys.argv[2]]=sys.argv[3]
with open(p+'.tmp','w') as f: json.dump(d,f)
import os
os.replace(p+'.tmp',p)
PY
}
# Atomic even on macOS, where mv -h prevents traversing a symlink destination.
flip() {
    local target="$1" tmp
    [ -e "$target" ] || { echo "Missing target: $target" >&2; exit 1; }
    mkdir -p "$(dirname "$link")"
    tmp="${link}.tool-update.$$"
    ln -s "$target" "$tmp"
    mv -fh "$tmp" "$link"
}
command_at() { if [ "$manager" = brew ]; then printf '%s/bin/%s' "$base/$version" "$tool"; else printf '%s/node_modules/%s/%s' "$base/$version" "$package" "$entry"; fi; }
count_processes() {
    local stamp="$1"
    # C locale: lstart is localized otherwise. A start time that cannot be read
    # counts as before the switch, so finish refuses rather than guessing.
    LC_ALL=C ps -A -o pid= -o comm= | LC_ALL=C python3 -c 'import os,sys,subprocess,datetime
name,stamp=sys.argv[1:]; before=after=0
for line in sys.stdin:
    parts=line.split(None,1)
    if len(parts)!=2 or os.path.basename(parts[1].strip())!=name: continue
    try:
        started=subprocess.check_output(["ps","-o","lstart=","-p",parts[0]],text=True,stderr=subprocess.DEVNULL).strip()
        dt=datetime.datetime.strptime(started,"%a %b %d %H:%M:%S %Y").timestamp()
        if dt < float(stamp): before+=1
        else: after+=1
    except ValueError: before+=1
    except subprocess.CalledProcessError: continue
print(f"before: {before}\nafter: {after}")' "$process" "$stamp"
}
case "$action" in
stage)
    valid_version "$version" || { echo 'Invalid version' >&2; exit 2; }
    [ ! -e "$base/$version" ] || { echo 'Version already staged' >&2; exit 1; }
    mkdir -p "$base"
    dir="$base/$version"; mkdir "$dir"
    trap 'rm -rf "$dir"' ERR
    case "$manager" in
        npm) npm install --prefix "$dir" --no-save "$package@$version" ;;
        bun) bun add --cwd "$dir" "$package@$version" ;;
        brew)
            # --skip-link leaves the CLI link untouched; disable automatic keg cleanup.
            HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --skip-link "$package"
            keg="$(brew --prefix "$package")"
            [ "$(basename "$keg")" = "$version" ] || { echo 'Brew did not install requested version' >&2; exit 1; }
            ln -s "$keg/bin" "$dir/bin" ;;
        *) echo 'Unsupported manager' >&2; exit 2 ;;
    esac
    bin="$(command_at)"; [ -f "$bin" ] || { echo 'Package entry missing' >&2; exit 1; }
    output="$("$bin" --version)"; [[ "$output" == *"$version"* ]] || { echo 'Installed version mismatch' >&2; exit 1; }
    put_state staged_version "$version"
    trap - ERR
    echo "Staged $tool $version"
    ;;
check)
    valid_version "$version" || usage
    bin="$(command_at)"; [ -f "$bin" ] || { echo 'Stage first' >&2; exit 1; }
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    if [ "$tool" = pi ]; then
        mkdir -p "$tmp/agent/extensions"
        # Symlink extension sources, never credentials or the owner's agent directory.
        for ext in "$ROOT"/system/pi-config/extensions/*; do [ -f "$ext" ] && ln -s "$ext" "$tmp/agent/extensions/$(basename "$ext")"; done
        export PI_CODING_AGENT_DIR="$tmp/agent"
    fi
    while IFS= read -r flag; do [ -z "$flag" ] || "$bin" "$flag" >/dev/null; done < <(field checks)
    # Session compatibility, for a tool whose profile names an export flag and
    # its sessions directory: export a COPY of the newest session with the
    # running and the staged version and compare the entry counts.
    export_flag="$(field_opt session_export)"
    if [ -n "$export_flag" ]; then
        old="$(python3 - "$link" <<'PY'
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
)"
        sessions="$(field_opt sessions)"
        if [ -d "$sessions" ]; then
            newest="$(python3 - "$sessions" <<'PY'
import pathlib,sys
files=pathlib.Path(sys.argv[1]).rglob('*.jsonl')
print(max(files,key=lambda p:p.stat().st_mtime,default=''))
PY
)"
            if [ -n "$newest" ]; then
                cp "$newest" "$tmp/session.jsonl"
                "$old" "$export_flag" "$tmp/session.jsonl" "$tmp/old.html" >/dev/null
                "$bin" "$export_flag" "$tmp/session.jsonl" "$tmp/new.html" >/dev/null
                python3 - "$tmp/old.html" "$tmp/new.html" <<'PY'
import sys,re,base64,json,html
# Pi's HTML export embeds the session as base64 JSON in #session-data (seen on
# 0.87.1 and 0.99.2); count its entries. A regex over the HTML found none.
def count(path):
    s=open(path,errors='replace').read()
    m=re.search(r'id="session-data"[^>]*>([^<]+)<',s)
    if not m: return 0
    raw=m.group(1).strip()
    try: d=json.loads(base64.b64decode(raw))
    except Exception: d=json.loads(html.unescape(raw))
    e=d.get('entries') or d.get('messages') if isinstance(d,dict) else d
    return len(e) if isinstance(e,list) else 0
a,b=map(count,sys.argv[1:]); print(f'Export entries: old={a} new={b}')
if not a or a!=b: sys.exit('Session export entry mismatch')
PY
            fi
        fi
    fi
    put_state checked_at "$(date +%s)"
    echo "Checks passed: $tool $version"
    ;;
switch)
    valid_version "$version" || usage
    [ ! -f "$active_file" ] || { echo 'Already switched; finish or rollback first' >&2; exit 1; }
    bin="$(command_at)"; [ -f "$bin" ] || { echo 'Stage first' >&2; exit 1; }
    get_state checked_at >/dev/null 2>&1 || { echo 'Run check before switch' >&2; exit 1; }
    [ -L "$link" ] || { echo 'Command is not a symlink' >&2; exit 1; }
    previous="$(readlink "$link")"
    # Save relative target as-is; resolved from the link directory for verification.
    case "$previous" in /*) old="$previous";; *) old="$(dirname "$link")/$previous";; esac
    [ -e "$old" ] || { echo 'Previous target missing' >&2; exit 1; }
    put_state previous_target "$previous"
    put_state switched_at "$(date +%s)"
    flip "$bin"
    printf '%s\n' "$version" > "$active_file"
    if [ "${TOOL_UPDATE_NO_REMIND:-0}" != 1 ]; then
        due="$(python3 -c 'import datetime;print((datetime.date.today()+datetime.timedelta(days=2)).isoformat())')"
        AGENTBRAIN_DIR="$ROOT" bash "$ROOT/scripts/remind.sh" "Finish $tool tool update" --on "$due" --scope "tool-update-$tool" >/dev/null
    fi
    echo "Switched $tool to $version"
    ;;
adopt)
    # Explicit version and previous-link file; does not flip, install, or schedule anything.
    valid_version "$version" || usage
    [ ! -f "$active_file" ] || { echo 'Already switched' >&2; exit 1; }
    previous_file="${2:-}"; [ -f "$previous_file" ] || { echo 'Provide previous-link file' >&2; exit 2; }
    bin="$(command_at)"; [ -f "$bin" ] && [ "$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$link")" = "$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$bin")" ] || { echo 'Current command does not point at staged entry' >&2; exit 1; }
    previous="$(<"$previous_file")"
    case "$previous" in /*) old="$previous";; *) old="$(dirname "$link")/$previous";; esac
    [ -e "$old" ] || { echo 'Previous target missing' >&2; exit 1; }
    put_state staged_version "$version"; put_state previous_target "$previous"; put_state switched_at "$(date +%s)"
    printf '%s\n' "$version" > "$active_file"
    echo "Adopted $tool $version (switch time approximated as adoption time)"
    ;;
status)
    if active; then
        echo "switched: $tool $version"
        count_processes "$(get_state switched_at)"
    else echo "not switched: $tool"; fi
    ;;
rollback)
    active || { echo 'Nothing switched' >&2; exit 1; }
    previous="$(get_state previous_target)"
    case "$previous" in /*) old="$previous";; *) old="$(dirname "$link")/$previous";; esac
    [ -e "$old" ] || { echo 'Previous target missing' >&2; exit 1; }
    flip "$old"; rm "$active_file"
    echo "Rolled back $tool"
    ;;
finish)
    active || { echo 'Nothing switched' >&2; exit 1; }
    force=0; [ "${1:-}" != '--force' ] || force=1
    counts="$(count_processes "$(get_state switched_at)")"
    before="$(printf '%s\n' "$counts" | awk '/^before:/ {print $2}')"
    if [ "$before" -gt 0 ] && [ "$force" -ne 1 ]; then echo "Refusing: $before pre-switch processes remain. --force is the owner's call." >&2; exit 1; fi
    previous="$(get_state previous_target)"
    case "$previous" in /*) old="$previous";; *) old="$(dirname "$link")/$previous";; esac
    [ -e "$old" ] || { echo 'Previous global target missing' >&2; exit 1; }
    case "$manager" in
        npm)
            if [ "$tool" = gemini ]; then npm install --global --prefix "$(field global_prefix)" "$package@$version"
            else npm install --global "$package@$version"; fi ;;
        bun) bun add --global "$package@$version" ;;
        brew)
            HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --skip-link "$package"
            old="$(brew --prefix "$package")/$entry" ;;
    esac
    # A manager may rewrite the command link; always atomically reset it to the global entry.
    [ -e "$old" ] || { echo 'Global entry missing after install' >&2; exit 1; }
    flip "$old"
    rm "$active_file"
    put_state finished_at "$(date +%s)"
    if [ "${TOOL_UPDATE_NO_REMIND:-0}" != 1 ]; then
        reminder="$(AGENTBRAIN_DIR="$ROOT" bash "$ROOT/scripts/remind.sh" list --plain | awk -v t="Finish $tool tool update" 'index($0,t)>0 {print $2}')"
        if [ -n "$reminder" ]; then AGENTBRAIN_DIR="$ROOT" bash "$ROOT/scripts/remind.sh" 'done' "$reminder" >/dev/null; fi
    fi
    echo "Finished $tool $version: the command now runs the global install"
    # Sessions started after the switch run from the staged directory. Removing
    # it under them is the very crash this command exists to prevent, so the
    # directory stays until they have ended (prune).
    after="$(printf '%s\n' "$counts" | awk '/^after:/ {print $2}')"
    if [ "${after:-0}" -gt 0 ]; then
        echo "Kept $base/$version: $after session(s) started after the switch still run from it. Run: brain tool-update $tool prune"
        if [ "${TOOL_UPDATE_NO_REMIND:-0}" != 1 ]; then
            due="$(python3 -c 'import datetime;print((datetime.date.today()+datetime.timedelta(days=2)).isoformat())')"
            AGENTBRAIN_DIR="$ROOT" bash "$ROOT/scripts/remind.sh" "Prune $tool tool update" --on "$due" --scope "tool-update-$tool" >/dev/null
        fi
    else
        rm -rf "${base:?}/${version:?}"
        echo "Removed $base/$version"
    fi
    ;;
prune)
    # Remove staged directories of finished updates once no process that
    # could run from them remains: every process started before the finish.
    active && { echo "An update is switched, not finished: run finish first" >&2; exit 1; }
    removed=0; kept=0
    for dir in "$base"/*/; do
        [ -f "$dir/state.json" ] || continue
        version="$(basename "$dir")"; valid_version "$version" || continue
        fin="$(get_state finished_at 2>/dev/null)" || continue
        before="$(count_processes "$fin" | awk '/^before:/ {print $2}')"
        if [ "$before" -gt 0 ]; then
            echo "Kept $tool $version: $before session(s) started before the finish may still run from it"; kept=$((kept+1))
        else
            rm -rf "${base:?}/${version:?}"; echo "Removed $base/$version"; removed=$((removed+1))
        fi
    done
    if [ "$kept" -eq 0 ] && [ "${TOOL_UPDATE_NO_REMIND:-0}" != 1 ]; then
        reminder="$(AGENTBRAIN_DIR="$ROOT" bash "$ROOT/scripts/remind.sh" list --plain | awk -v t="Prune $tool tool update" 'index($0,t)>0 {print $2}')"
        if [ -n "$reminder" ]; then AGENTBRAIN_DIR="$ROOT" bash "$ROOT/scripts/remind.sh" 'done' "$reminder" >/dev/null; fi
    fi
    [ "$removed" -gt 0 ] || [ "$kept" -gt 0 ] || echo "Nothing to prune for $tool"
    ;;
*) usage ;;
esac
