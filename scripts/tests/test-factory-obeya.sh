#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-factory-obeya.sh: the obeya shows a factory as it is, from every kind of
# factory the builder serves, and says so when a source is missing.
#
# The cases are the factories that exist: plain lane factories, one with its own
# board and no "lanes" (agentBrain), addon factories whose R&D has no dashboards
# yet and whose lanes sit inside another repository, a factory with an ad-hoc
# "open" block, and every way a hand-kept andon or backlog goes wrong.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
OBEYA="$ROOT/system/skills/factory-builder/bin/factory-obeya.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1: expected '$3' in: $(printf '%s' "$2" | head -c 400)" ;; esac; }
lacks(){ case "$2" in *"$3"*) bad "$1: did not expect '$3'" ;; *) ok "$1" ;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FACTORY_OBEYA_TODAY=2026-10-20 GIT_CONFIG_GLOBAL=/dev/null
gitrepo() { # gitrepo <dir> [version]
	mkdir -p "$1"; git -C "$1" init -q; [ -n "${2:-}" ] && printf '%s\n' "$2" > "$1/VERSION"
	git -C "$1" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
	git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}
run() { bash "$OBEYA" --factory "$1" "${@:2}" 2>&1; }

# ── 1. a plain lane factory with nothing configured ──────────────────────────
F="$T/plain factory & R&D"            # spaces and an ampersand in the path
mkdir -p "$F/R&D/dashboards"
gitrepo "$F/tool-dev" 1.2.0-prerelease-01; gitrepo "$F/tool" 1.1.0
mkdir -p "$F/tool-next"                 # next exists but is not a git worktree
printf 'x\n' > "$F/tool-dev/dirty.txt"
cat > "$F/factory.json" <<EOF
{"project":"tool","lanes":{"dev":"tool-dev","next":"tool-next","live":"tool","//":"comment keys are skipped"}}
EOF
out="$(run "$F")"
has "defaults: the page names the project" "$out" "# tool obeya"
has "lanes: dev version and uncommitted count" "$out" "| dev | 1.2.0-prerelease-01 |"
has "lanes: dirty dev is counted" "$out" "1 uncommitted"
has "lanes: a lane that is not a git worktree says so" "$out" "not a git worktree"
lacks "lanes: comment keys are not stations" "$out" "| // |"
has "no andon: the page says how to create it" "$out" "factory-obeya.sh --init"
has "no backlog configured: said, not silent" "$out" "not configured (obeya.backlog)"
has "no log configured: said, not silent" "$out" "not configured (obeya.log)"

# ── 2. --init creates the andon, also where dashboards/ is missing ───────────
A="$T/addon-factory"                    # R&D without dashboards
mkdir -p "$A/R&D/decisions"
gitrepo "$T/host-repo"; mkdir -p "$T/host-repo/system/addons/demo-addon"
printf '{"version":"0.3.1"}\n' > "$T/host-repo/system/addons/demo-addon/package.json"
cat > "$A/factory.json" <<EOF
{"project":"demo-addon","lanes":{"dev":"$T/host-repo/system/addons/demo-addon","live":"~/definitely-not-here-obeya"},"policy":{"logging":"never store payload bodies"}}
EOF
out="$(run "$A" --init)"
has "init: creates the andon" "$out" "created"
[ -f "$A/R&D/dashboards/andon.md" ] && ok "init: dashboards/ created on the way" || bad "init: no andon file"
grep -q '^## Working on$' "$A/R&D/dashboards/andon.md" && ok "init: headings come from the config" || bad "init: headings missing"
grep -q '^# demo-addon andon$' "$A/R&D/dashboards/andon.md" && ok "init: title carries the project" || bad "init: title"
printf -- '- keep me\n' >> "$A/R&D/dashboards/andon.md"
out="$(run "$A" --init)"
has "init: an existing andon is never overwritten" "$out" "left as is"
grep -q 'keep me' "$A/R&D/dashboards/andon.md" && ok "init: its content survives" || bad "init: content lost"
out="$(run "$A")"
has "addon lane inside another repo: version from package.json" "$out" "| dev | 0.3.1 |"
has "addon lane: sha from the containing repository" "$out" "| dev | 0.3.1 | "
has "~ lane that does not exist is marked missing" "$out" "| live | missing |"

# ── 3. the andon: ages, stale, undated, bad dates, sections ──────────────────
cat > "$A/R&D/dashboards/andon.md" <<'EOF'
---
date: 2026-10-01
id: x
---
# demo-addon andon
## Working on
- wiring the sender
## Stopped or waiting on
- vendor approval pending. Since 2026-10-19.
- vendor reply on the rate limit, since 2026-09-01
- a cord without a date
- a cord with a broken date since 2026-02-31
* star bullets count too since 2026-10-20
## Something else
- not a cord
EOF
out="$(run "$A")"
has "andon: working items are listed" "$out" "- wiring the sender"
has "andon: age in days, singular" "$out" "(1 day)"
has "andon: an old cord is STALE" "$out" "since 2026-09-01 (49 days) **STALE**"
has "andon: a cord without a date is UNDATED" "$out" "a cord without a date (no date) **UNDATED**"
has "andon: an impossible date counts as undated" "$out" "2026-02-31 (no date) **UNDATED**"
has "andon: '*' bullets and case-insensitive 'Since'" "$out" "star bullets count too since 2026-10-20 (0 days)"
lacks "andon: items under other headings are ignored" "$out" "not a cord"
lacks "andon: frontmatter is not read as content" "$out" "id: x"
j="$(run "$A" --json)"
has "json: stopped count" "$j" '"stopped": 5'
has "json: oldest age" "$j" '"oldestDays": 49'
has "json: stale count" "$j" '"stale": 1'
has "json: undated count" "$j" '"undated": 2'

printf '# empty\n## Working on\n## Stopped or waiting on\n' > "$A/R&D/dashboards/andon.md"
out="$(run "$A")"
has "andon: empty sections say (none)" "$out" "- (none)"

# ── 4. the backlog: project filter, status, priority, rank, broken notes ─────
B="$T/backlog"; mkdir -p "$B"
note() { printf -- '---\n%s\n---\n\n# %s\n' "$2" "$3" > "$B/$1.md"; }
note a "project: demo-addon
status: todo
priority: medium
rank: 2" "Medium second"
note b "project: demo-addon
status: todo
priority: medium
rank: 1" "Medium first"
note c "project: demo-addon
status: todo
priority: high" "High without rank"
note d "project: demo-addon
status: done
priority: high" "Done is not next"
note e "project: other
status: todo
priority: high" "Other factory"
note f "project: demo-addon
status: doing" "No priority | pipe"
printf 'no frontmatter at all\n' > "$B/g.md"
note h "project: demo-addon
status: TODO
priority: HIGH
rank: x" "Case and a bad rank"
python3 - "$A/factory.json" "$B" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["obeya"]={"backlog":sys.argv[2],"next":10}; json.dump(d,open(p,"w"))
EOF
out="$(run "$A")"
order="$(printf '%s\n' "$out" | sed -n 's/^[0-9]*\. \[\([a-z]*\)\] \(.*\) (`.*$/\1 \2/p')"
exp="$(printf 'high High without rank\nhigh Case and a bad rank\nmedium Medium first\nmedium Medium second\nnone No priority \\| pipe')"   # equal priority and no rank: by file name (c before h)
[ "$order" = "$exp" ] && ok "backlog: priority, then rank, then name; case-insensitive; unknown last" || bad "backlog order was:
$order"
lacks "backlog: done items are not next" "$out" "Done is not next"
lacks "backlog: another project's items are not next" "$out" "Other factory"
has "backlog: count of open items" "$out" "_5 open_"
python3 - "$A/factory.json" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["obeya"]["next"]=2; json.dump(d,open(p,"w"))
EOF
out="$(run "$A")"
has "backlog: next is capped by config" "$out" "2. [high] Case and a bad rank"
lacks "backlog: the cap holds" "$out" "3. ["
python3 - "$A/factory.json" "$T/nope" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["obeya"]["backlog"]=sys.argv[2]; json.dump(d,open(p,"w"))
EOF
has "backlog: a missing directory is named" "$(run "$A")" "missing: $T/nope"

# ── 5. the log ───────────────────────────────────────────────────────────────
L="$T/index.md"
printf '# p\n\n## Goal\n- not done\n\n## Progress\n- newest, wrapped\n  over two lines\n- older\n- oldest\n\n## Related\n- not done either\n' > "$L"
python3 - "$A/factory.json" "$L" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["obeya"].update({"log":sys.argv[2],"done":2}); json.dump(d,open(p,"w"))
EOF
out="$(run "$A")"
has "log: newest entries of the log section" "$out" "- newest"
has "log: a wrapped entry is joined" "$out" "- newest, wrapped over two lines"
lacks "log: capped by config" "$out" "- oldest"
lacks "log: other sections are not done work" "$out" "not done either"
printf '# p\n\n## Goal\n- x\n' > "$L"
has "log: no log section is said" "$(run "$A")" 'no "Progress" section'

# ── 6. a factory with its own board and no lanes (agentBrain) ────────────────
G="$T/agentbrain-like"; mkdir -p "$G/tools"
printf '#!/usr/bin/env bash\necho %s\n' "'{\"framework\":{\"dev\":{\"version\":\"1.14.0\",\"sha\":\"abc\"}},\"tags\":{\"stable\":\"v1.13.2\"},\"harness\":{\"version\":\"0.1.0-rc.12\"}}'" > "$G/tools/board.sh"
printf '{"root":"x","framework":{"dev":"d"},"obeya":{"stations":"bash tools/board.sh"}}\n' > "$G/factory.json"
out="$(run "$G")"
has "own board: nested stations are flattened" "$out" "| framework.dev |  | version 1.14.0, sha abc |"
has "own board: flat values" "$out" "| tags | stable | v1.13.2 |"
has "no project key: the folder name is the project" "$out" "# agentbrain-like obeya"
printf '#!/usr/bin/env bash\necho not json\n' > "$G/tools/board.sh"
has "own board that prints no JSON: not measured" "$(run "$G")" "not measured"
printf '#!/usr/bin/env bash\nexit 3\n' > "$G/tools/board.sh"
has "own board that fails: not measured" "$(run "$G")" "not measured"
printf '{"project":"nolanes"}\n' > "$G/factory.json"
has "neither lanes nor stations: not measured, and why" "$(run "$G")" "declares no lanes"

# ── 6b. profiles: the obeya reads lanes through the same normalizer as doctor ─
C="$T/composite"; mkdir -p "$C"
gitrepo "$C/fw-dev" 2.0.0; gitrepo "$C/fw-live" 1.9.0
printf '{"profile":"composite","framework":{"dev":"fw-dev","live":"fw-live"},"releases":{"root":"arch"},"obeya":{"project":"comp"}}' > "$C/factory.json"
out="$(run "$C")"
has "composite without own board: lanes from framework.*" "$out" "| dev | 2.0.0 |"
has "composite: live lane too" "$out" "| live | 1.9.0 |"
has "composite: an undeclared lane says so" "$out" "| next | missing | not declared |"
has "composite: the source names the profile" "$out" "lanes of the composite profile"
has "composite: project from obeya.project" "$out" "# comp obeya"
printf '{"profile":"weird","lanes":{}}' > "$C/factory.json"
has "unknown profile: not measured, never guessed" "$(run "$C")" "unknown factory profile"

# ── 7. writing: vault frontmatter, plain file, idempotent ───────────────────
V="$T/brain/vault"; mkdir -p "$V/projects/p"
printf '#!/usr/bin/env bash\nprintf "id-for-%%s\\n" "$1"\n' > "$T/brain/idtool.sh"
python3 - "$A/factory.json" "$V" "$T/brain/idtool.sh" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["obeya"].update({"page":sys.argv[2]+"/projects/p/obeya.md","vault":sys.argv[2],"noteId":sys.argv[3]}); json.dump(d,open(p,"w"))
EOF
out="$(run "$A" --write)"
has "write: a vault page is written" "$out" "wrote"
grep -q '^id: id-for-vault/projects/p/obeya$' "$V/projects/p/obeya.md" && ok "write: id seeded on the path from the brain root" || bad "write: id was $(grep '^id:' "$V/projects/p/obeya.md")"
m1="$(stat -f %m "$V/projects/p/obeya.md")"; sleep 1
out="$(run "$A" --write)"
m2="$(stat -f %m "$V/projects/p/obeya.md")"
has "write: the same state reports unchanged" "$out" "unchanged"
[ "$m1" = "$m2" ] && ok "write: the same state leaves the file untouched" || bad "write: file rewritten without a change"
python3 - "$A/factory.json" "$T/plain/obeya.md" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["obeya"]["page"]=sys.argv[2]; json.dump(d,open(p,"w"))
EOF
run "$A" --write >/dev/null
head -1 "$T/plain/obeya.md" | grep -q '^# demo-addon obeya$' && ok "write: outside the vault, plain Markdown without frontmatter" || bad "write: plain page starts with $(head -1 "$T/plain/obeya.md")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/brain/idtool.sh"
python3 - "$A/factory.json" "$V" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["obeya"]["page"]=sys.argv[2]+"/projects/p/obeya2.md"; json.dump(d,open(p,"w"))
EOF
bash "$OBEYA" --factory "$A" --write >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ ! -f "$V/projects/p/obeya2.md" ] && ok "write: an id tool that gives nothing stops, and writes nothing" || bad "write: rc=$rc with an empty id"

# ── 8. factory.json itself ───────────────────────────────────────────────────
E="$T/broken"; mkdir -p "$E"
bash "$OBEYA" --factory "$E" >/dev/null 2>&1; [ $? = 2 ] && ok "no factory.json: exit 2" || bad "no factory.json: wrong exit"
printf '{not json' > "$E/factory.json"
bash "$OBEYA" --factory "$E" >/dev/null 2>&1; [ $? = 2 ] && ok "invalid factory.json: exit 2" || bad "invalid factory.json: wrong exit"
printf '{"project":"x","obeya":"yes"}' > "$E/factory.json"
bash "$OBEYA" --factory "$E" >/dev/null 2>&1; [ $? = 2 ] && ok "obeya that is not an object: exit 2" || bad "obeya string accepted"
printf '{"project":"x","lanes":{},"obeya":{"sections":{"stopped":"Blocked"}}}' > "$E/factory.json"
mkdir -p "$E/R&D/dashboards"; printf '## Blocked\n- waiting since 2026-10-10\n## Working on\n- a\n' > "$E/R&D/dashboards/andon.md"
out="$(run "$E")"
has "custom heading from config is honoured" "$out" "(10 days)"
has "unchanged default heading still works" "$out" "- a"

# ── 9. doctor and registry read the same summary ────────────────────────────
BIN="$ROOT/system/skills/factory-builder/bin"
R="$T/registry-root"; mkdir -p "$R/withcords/R&D/dashboards" "$R/bare"
printf '{"project":"withcords","lanes":{},"obeya":{"backlog":"%s","project":"demo-addon"}}' "$B" > "$R/withcords/factory.json"
printf '## Stopped or waiting on\n- old one since 2026-09-01\n- no date\n' > "$R/withcords/R&D/dashboards/andon.md"
printf '{"project":"bare","lanes":{}}' > "$R/bare/factory.json"
mkdir -p "$B"; note c "project: demo-addon
status: todo
priority: high" "High without rank"
doc="$(bash "$BIN/factory-doctor.sh" --factory "$R/withcords" 2>&1)"
has "doctor: stale cords are a note" "$doc" "cord(s) pulled longer than the stale threshold (oldest 49 days)"
has "doctor: undated cords are a note" "$doc" "cord(s) without a since-date"
has "doctor: a factory without andon is told how to make one" "$(bash "$BIN/factory-doctor.sh" --factory "$R/bare" 2>&1)" "no andon; create it with factory-obeya.sh --init"
bash "$BIN/factory-registry.sh" --root "$R" --out "$T/reg" >/dev/null 2>&1
dash="$(cat "$T/reg/dashboard.md" 2>/dev/null)"
has "registry: andon column for a factory with cords" "$dash" "2 stopped, oldest 49d, 1 stale, 1 undated"
has "registry: a factory without andon says so" "$dash" "no andon"
has "registry: the next step comes from the backlog" "$dash" "High without rank"
lacks "registry: no emoji in the dashboard" "$dash" "✅"
lacks "registry: no warning sign either" "$dash" "⚠"

# ── 10. nothing is fixed in the script ───────────────────────────────────────
lit="$(grep -n -E '"(R&D/|Working on|Stopped or waiting on|Progress|high|medium|low|todo)' "$OBEYA" || true)"
[ -z "$lit" ] && ok "no spec value is written into the script" || bad "literals in the script: $lit"

printf 'factory-obeya: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
