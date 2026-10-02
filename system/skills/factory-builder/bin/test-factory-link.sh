#!/usr/bin/env bash
# test-factory-link.sh — <tool>-next runs the next lane, side by side with the
# live command, and factory-doctor reports a missing or stale one.
# Throwaway factory and bin dir; nothing reaches the real PATH.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok: $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1" >&2; }
export FACTORY_BIN_DIR="$T/bin"
F="$T/tool.factory"
mkdir -p "$F/tool-dev/bin" "$F/tool-next/bin" "$F/tool/bin" "$F/releases"
mk() { printf '#!/usr/bin/env bash\n[ "${1:-}" = --version ] && { echo "tool 1.2.3"; exit 0; }\necho "lane=%s args=$*"\n' "$1" > "$F/$1/bin/tool"; chmod +x "$F/$1/bin/tool"; }
for l in tool-dev tool-next tool; do mk "$l"; done
json() { printf '{"project":"tool","lanes":{"dev":"%s/tool-dev","next":"%s/tool-next","live":"%s/tool"},"releases":"%s/releases"%s}\n' "$F" "$F" "$F" "$F" "$1" > "$F/factory.json"; }
LINK=(bash "$HERE/factory-link.sh" --factory "$F")

json ''
out="$("${LINK[@]}" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/bin/tool-next" ] && ok "no cli block: nothing is linked" || bad "no cli: rc=$rc $out"

json ',"cli":{"name":"tool","entry":"bin/tool"}'
out="$("${LINK[@]}" --check 2>&1)"
printf '%s' "$out" | grep -q "NOTE tool-next is not on the PATH yet" && ok "check notes a missing tool-next" || bad "missing not noted: $out"
"${LINK[@]}" >/dev/null 2>&1
[ -x "$T/bin/tool-next" ] && ok "link writes an executable tool-next" || bad "no wrapper"
[ "$("$T/bin/tool-next" a b)" = "lane=tool-next args=a b" ] && ok "tool-next runs the next lane with its arguments" || bad "runs: $("$T/bin/tool-next" a b)"
[ ! -e "$T/bin/tool" ] && ok "the live command is left alone" || bad "a bare tool was written"
out="$("${LINK[@]}" --check 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check is silent when tool-next is current" || bad "current: rc=$rc $out"

json ',"cli":{"name":"tool","entry":"bin/tool","nextChangesData":"config v2 in ~/.config/tool"}'
out="$("${LINK[@]}" --check 2>&1)"
printf '%s' "$out" | grep -q "out of date" && ok "check notes a tool-next that factory.json changed" || bad "stale not noted: $out"
"${LINK[@]}" >/dev/null 2>&1
err="$("$T/bin/tool-next" 2>&1 >/dev/null)"
printf '%s' "$err" | grep -q "changes data live shares: config v2" && ok "a lane that changes shared data says so on every run" || bad "no data warning: $err"

rm -f "$F/tool-next/bin/tool"
out="$("${LINK[@]}" --check 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "FAIL tool-next: bin/tool is missing" && ok "a missing entry in the next lane fails" || bad "missing entry: rc=$rc $out"
mk tool-next

printf '#!/bin/sh\necho mine\n' > "$T/bin/tool-next"
out="$("${LINK[@]}" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(cat "$T/bin/tool-next")" = "$(printf '#!/bin/sh\necho mine')" ] && ok "a tool-next someone else made is never overwritten" || bad "foreign overwritten: rc=$rc"
rm -f "$T/bin/tool-next"

json ',"cli":{"name":"tool","entry":"bin/tool","run":"bash"}'
"${LINK[@]}" >/dev/null 2>&1
grep -q "^exec bash \"$F/tool-next/bin/tool\"" "$T/bin/tool-next" && ok "run names the program that starts the entry" || bad "run: $(tail -1 "$T/bin/tool-next")"

out="$(bash "$HERE/factory-doctor.sh" --factory "$F" 2>&1)"
printf '%s' "$out" | grep -q "tool-next" && ok "factory-doctor relays the link check" || true
json ',"cli":{"name":"tool","entry":"bin/tool","run":"sh"}'
out="$(bash "$HERE/factory-doctor.sh" --factory "$F" 2>&1)"
printf '%s' "$out" | grep -q "NOTE tool-next is out of date" && ok "factory-doctor notes a stale tool-next" || bad "doctor: $(printf '%s' "$out" | grep -i next)"

# Hard rule: every command answers --version, in live and in next.
printf '#!/usr/bin/env bash\necho "unknown command: $1"; exit 1\n' > "$F/tool-next/bin/tool"
out="$("${LINK[@]}" --check 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "FAIL tool (next lane): --version must exit 0" && ok "a next lane without --version fails" || bad "next --version: rc=$rc $out"
mk tool-next
printf '#!/usr/bin/env bash\necho "tool"\n' > "$F/tool/bin/tool"
out="$("${LINK[@]}" --check 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "INFO tool (live lane): --version must.*promoting next fixes live" && ok "live without --version is information while next has it (the pipeline can fix it)" || bad "live --version with good next: rc=$rc $out"
echo 0.1.0 > "$F/VERSION"
out="$(bash "$HERE/factory-doctor.sh" --factory "$F" --strict 2>&1)"; rc=$?
printf '%s' "$out" | grep -q "INFO tool (live lane)" && ! printf '%s' "$out" | grep -q "^FAIL tool (live lane): --version" && ok "a strict doctor (factory-check, before promote) does not block on it" || bad "strict blocks: $(printf '%s' "$out" | grep -- "--version")"
rm -f "$F/VERSION"
printf '#!/usr/bin/env bash\necho "tool"\n' > "$F/tool-next/bin/tool"
out="$("${LINK[@]}" --check 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "FAIL tool (live lane): --version must" && ok "live without --version fails when next lacks it too" || bad "live+next --version: rc=$rc $out"
mk tool-next
mk tool
out="$(bash "$HERE/factory-doctor.sh" --factory "$F" 2>&1)"
printf '%s' "$out" | grep -q "FAIL no version file or package version found" && ok "factory-doctor fails a factory without a version of record" || bad "no version not failed: $(printf '%s' "$out" | grep -i version)"
echo 1.2.3 > "$F/VERSION"
out="$(bash "$HERE/factory-doctor.sh" --factory "$F" 2>&1)"
printf '%s' "$out" | grep -q "no version file" && bad "VERSION present but still reported" || ok "a VERSION file satisfies the version of record"

echo "test-factory-link: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
