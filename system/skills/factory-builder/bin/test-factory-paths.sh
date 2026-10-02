#!/usr/bin/env bash
# test-factory-paths.sh — one variable per tool, declared in factory.json, one
# central file, loaded the same way by the shell and by <tool>-next.
# Throwaway factories, central file, rc and bin dir; nothing real is touched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok: $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1" >&2; }
export FACTORY_PATHS_FILE="$T/paths.env" FACTORY_RC_FILE="$T/zshrc" FACTORY_ROOT="$T/dev" FACTORY_BIN_DIR="$T/bin"
P=(bash "$HERE/factory-paths.sh")
F="$T/dev/area/tool.factory"
mkdir -p "$F/tool-next/bin" "$F/tool/bin"
printf '#!/usr/bin/env bash\n[ "${1:-}" = --version ] && { echo "tool 1.0.0"; exit 0; }\necho "home=${TOOL_HOME:-unset}"\n' > "$F/tool-next/bin/tool"
cp "$F/tool-next/bin/tool" "$F/tool/bin/tool"; chmod +x "$F"/tool*/bin/tool
cfg() { printf '{"project":"tool","lanes":{"dev":"%s/tool-next","next":"%s/tool-next","live":"%s/tool"},"cli":{"name":"tool","entry":"bin/tool"}%s}\n' "$F" "$F" "$F" "$1" > "$F/factory.json"; }

# --check (factory-doctor)
cfg ''
out="$("${P[@]}" --check --factory "$F" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "NOTE factory.json has a cli but no paths block" && ok "a command without a paths block is noted" || bad "no paths: rc=$rc $out"
cfg ',"paths":{"env":"tool_home","holds":"x"}'
out="$("${P[@]}" --check --factory "$F" 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "env must be an UPPER_CASE" && printf '%s' "$out" | grep -q "default is missing" && ok "a malformed paths block fails" || bad "malformed: rc=$rc $out"
cfg ',"paths":{"env":"TOOL_HOME","default":"~/.tool","holds":"config and data"}'
out="$("${P[@]}" --check --factory "$F" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a good paths block is silent" || bad "good: rc=$rc $out"

# init: every variable commented out, idempotent, never touches a set value
"${P[@]}" init >/dev/null
grep -q '^# TOOL_HOME=~/.tool$' "$T/paths.env" && ok "init writes each variable commented out, with its default" || bad "init: $(cat "$T/paths.env")"
sed -i.bak 's|^# TOOL_HOME=.*|TOOL_HOME=~/elsewhere|' "$T/paths.env"
"${P[@]}" init >/dev/null
[ "$(grep -c 'TOOL_HOME=' "$T/paths.env")" = 1 ] && grep -q '^TOOL_HOME=~/elsewhere$' "$T/paths.env" && ok "init again keeps the value the owner set, adds nothing twice" || bad "init idempotent: $(cat "$T/paths.env")"

# show
out="$(env -u TOOL_HOME "${P[@]}" show 2>&1)"
printf '%s' "$out" | grep -E "tool.factory +TOOL_HOME +~/elsewhere +central file" >/dev/null && ok "show names the value in effect and where it comes from" || bad "show: $out"

# the loader, in bash and in zsh
printf 'TOOL_HOME=~/elsewhere\nOTHER="quoted value"\nBAD=$(touch %s/pwned)\nlower=x\n' "$T" > "$T/paths.env"
for sh in bash zsh; do
	command -v "$sh" >/dev/null || continue
	out="$(env -i HOME=/h FACTORY_PATHS_FILE="$T/paths.env" "$sh" -c "$("${P[@]}" loader)"'; printf "%s|%s|%s|%s" "$TOOL_HOME" "$OTHER" "$BAD" "${lower:-none}"')"
	[ "$out" = '/h/elsewhere|quoted value|$(touch '"$T"'/pwned)|none' ] && ok "$sh: the loader sets the variables, expands ~, drops quotes, skips bad keys" || bad "$sh loader: $out"
	out="$(env -i HOME=/h TOOL_HOME=/oneoff FACTORY_PATHS_FILE="$T/paths.env" "$sh" -c "$("${P[@]}" loader)"'; printf %s "$TOOL_HOME"')"
	[ "$out" = /oneoff ] && ok "$sh: a variable already set wins over the central file" || bad "$sh override: $out"
done
[ ! -e "$T/pwned" ] && ok "the central file cannot run code" || bad "a command in the central file ran"

# rc block: once, refreshed in place
printf 'export KEEP=1\n' > "$T/zshrc"
"${P[@]}" rc >/dev/null; "${P[@]}" rc >/dev/null
[ "$(grep -c '>>> factory paths >>>' "$T/zshrc")" = 1 ] && grep -q '^export KEEP=1$' "$T/zshrc" && ok "rc writes one managed block and keeps the rest" || bad "rc: $(cat "$T/zshrc")"

# <tool>-next loads the same central file
bash "$HERE/factory-link.sh" --factory "$F" >/dev/null
out="$(env -u TOOL_HOME HOME=/h "$T/bin/tool-next")"
[ "$out" = "home=/h/elsewhere" ] && ok "tool-next runs with the central file's value" || bad "wrapper: $out"
out="$(TOOL_HOME=/oneoff "$T/bin/tool-next")"
[ "$out" = "home=/oneoff" ] && ok "a one-off value still wins in tool-next" || bad "wrapper override: $out"

# set: change a path, move the data, never over existing data
printf 'TOOL_HOME=%s/old\n' "$T" > "$T/paths.env"
mkdir -p "$T/old/sub"; echo keep > "$T/old/sub/data"
out="$("${P[@]}" set TOOL_HOME "$T/new" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$T/new/sub/data" ] && [ ! -e "$T/old" ] && ok "set moves the data to the new place" || bad "set move: rc=$rc $out"
grep -q "^TOOL_HOME=$T/new$" "$T/paths.env" && [ "$(grep -c TOOL_HOME= "$T/paths.env")" = 1 ] && ok "set rewrites the one line in the central file" || bad "set file: $(cat "$T/paths.env")"
mkdir -p "$T/busy"; echo other > "$T/busy/x"
out="$("${P[@]}" set TOOL_HOME "$T/busy" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ -f "$T/new/sub/data" ] && [ -f "$T/busy/x" ] && grep -q "^TOOL_HOME=$T/new$" "$T/paths.env" && ok "set refuses to move over data and changes nothing" || bad "set busy: rc=$rc $out"
out="$("${P[@]}" set TOOL_HOME "$T/busy" --no-move 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q "^TOOL_HOME=$T/busy$" "$T/paths.env" && [ -f "$T/new/sub/data" ] && ok "--no-move only changes the setting" || bad "no-move: rc=$rc $out"
out="$("${P[@]}" set NOPE_HOME "$T/x" 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "no factory declares NOPE_HOME" && ok "set refuses a variable no factory declares" || bad "unknown var: rc=$rc $out"

echo "test-factory-paths: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
