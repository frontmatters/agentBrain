#!/usr/bin/env bash
# Behavioural tests for the add-ons layer. Uses a temp ADDONS root so it never
# touches real system/addons or local/addons.
# Usage: bash scripts/test-addons.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export ADDONS_REGISTRY="$TEST_DIR/system/addons"
export ADDONS_STATE="$TEST_DIR/local/addons"
mkdir -p "$ADDONS_REGISTRY/graphify" "$ADDONS_STATE"

# Hermetic agent home + brain root so the enable/disable skill-sync links into a
# throwaway ~/.claude, never the developer's real one. VAULT=$TEST_DIR makes
# setup-skills.sh scan this temp registry; BRAIN_ALIAS is the symlink-target prefix.
export AGENTBRAIN_HOME="$TEST_DIR/home"
export VAULT="$TEST_DIR"
export BRAIN_ALIAS="$TEST_DIR"
mkdir -p "$AGENTBRAIN_HOME/.claude/skills"

cat > "$ADDONS_REGISTRY/graphify/manifest.md" <<'EOF'
---
id: graphify
name: Graphify
install: echo installing-graphify
command: __graphify_test_fixture_bin__
privacy: sends-docs
install_method: self
support:
  claude: full
  windsurf: rules
  pi: full
---
# Graphify
EOF
echo "# Graphify" > "$ADDONS_REGISTRY/graphify/README.md"
cat > "$ADDONS_REGISTRY/graphify/SKILL.md" <<'EOF'
---
name: graphify
description: Graphify test skill fixture.
user-invocable: true
---
# Graphify skill
EOF

ADDONS="bash scripts/addons.sh"

passed=0
failed=0
failures=()
assert() {
	local desc="$1" actual="$2" expected="$3"
	if [ "$actual" = "$expected" ]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		failures+=("$desc: expected '$expected', got '$actual'")
	fi
}

# --- Task 1: field readers ---
assert "field name"       "$($ADDONS _field "$ADDONS_REGISTRY/graphify/manifest.md" name)" "Graphify"
assert "field privacy"    "$($ADDONS _field "$ADDONS_REGISTRY/graphify/manifest.md" privacy)" "sends-docs"
assert "support claude"   "$($ADDONS _support "$ADDONS_REGISTRY/graphify/manifest.md" claude)" "full"
assert "support windsurf" "$($ADDONS _support "$ADDONS_REGISTRY/graphify/manifest.md" windsurf)" "rules"
assert "support missing"  "$($ADDONS _support "$ADDONS_REGISTRY/graphify/manifest.md" cursor)" "unknown"

# --- Task 2: status ---
status_out="$($ADDONS status)"
assert "status lists id"        "$(echo "$status_out" | grep -c 'graphify')" "1"
assert "status shows available" "$(echo "$status_out" | grep -c 'available')" "1"
assert "status hides _template" "$(echo "$status_out" | grep -c 'your-addon')" "0"
mkdir -p "$ADDONS_STATE/graphify" && : > "$ADDONS_STATE/graphify/enabled"
assert "status shows enabled" "$($ADDONS status | grep graphify | grep -c 'enabled')" "1"

# --- Task 3: enable/disable ---
rm -f "$ADDONS_STATE/graphify/enabled"
ADDONS_ASSUME_YES=1 $ADDONS enable graphify >/dev/null
assert "enable creates touch"  "$([ -f "$ADDONS_STATE/graphify/enabled" ] && echo yes || echo no)" "yes"
assert "enable creates dir"    "$([ -d "$ADDONS_STATE/graphify" ] && echo yes || echo no)" "yes"
$ADDONS disable graphify >/dev/null
assert "disable removes touch" "$([ -f "$ADDONS_STATE/graphify/enabled" ] && echo yes || echo no)" "no"
assert "enable unknown fails"  "$(ADDONS_ASSUME_YES=1 $ADDONS enable nope >/dev/null 2>&1; echo $?)" "1"
assert "disable unknown fails" "$(ADDONS_ASSUME_YES=1 $ADDONS disable nope >/dev/null 2>&1; echo $?)" "1"

# --- Task 3b: enable/disable wires the addon's SKILL.md into agent skill dirs ---
# An addon that ships a SKILL.md becomes a usable skill exactly when it's enabled,
# and is removed again on disable. This is the whole point of enable/disable.
CLAUDE_SKILL="$AGENTBRAIN_HOME/.claude/skills/graphify/SKILL.md"
ADDONS_ASSUME_YES=1 $ADDONS enable graphify >/dev/null
assert "enable links addon skill"      "$([ -L "$CLAUDE_SKILL" ] && echo yes || echo no)" "yes"
assert "skill link points into addon"  "$(readlink "$CLAUDE_SKILL" 2>/dev/null | grep -c 'system/addons/graphify/SKILL.md')" "1"
$ADDONS disable graphify >/dev/null
assert "disable removes addon skill"   "$([ -e "$CLAUDE_SKILL" ] && echo yes || echo no)" "no"

# --- Task 3c: doctor (check-skill-links) enforces the addon-skill invariant ---
CHK="bash scripts/check-skill-links.sh"
ADDONS_ASSUME_YES=1 $ADDONS enable graphify >/dev/null
assert "linked+enabled passes check"        "$($CHK >/dev/null 2>&1; echo $?)" "0"
# Drift: enabled addon whose skill link is missing must be flagged.
rm -rf "$AGENTBRAIN_HOME/.claude/skills/graphify"
assert "missing enabled-addon skill flagged" "$($CHK >/dev/null 2>&1; echo $?)" "1"
# Orphan: a skill link left behind after the addon was disabled must be flagged.
ADDONS_ASSUME_YES=1 $ADDONS enable graphify >/dev/null
rm -f "$ADDONS_STATE/graphify/enabled"
assert "orphaned addon skill link flagged"   "$($CHK >/dev/null 2>&1; echo $?)" "1"
# Clean: re-enable so disable can prune the link, then disable.
ADDONS_ASSUME_YES=1 $ADDONS enable graphify >/dev/null
$ADDONS disable graphify >/dev/null

# --- Task 3d: uninstall prunes the addon's skill link (true inverse of install) ---
ADDONS_ASSUME_YES=1 $ADDONS enable graphify >/dev/null
assert "precondition: enable linked skill"  "$([ -L "$CLAUDE_SKILL" ] && echo yes || echo no)" "yes"
$ADDONS uninstall graphify >/dev/null
assert "uninstall removes addon skill"      "$([ -e "$CLAUDE_SKILL" ] && echo yes || echo no)" "no"

# --- Task 3e: `test` validates LOCAL addons too (no false "valid" pass) ---
mkdir -p "$ADDONS_STATE/brokenlocal"
cat > "$ADDONS_STATE/brokenlocal/manifest.md" <<'EOF'
---
id: brokenlocal
name: Broken Local
install: echo x
command: bash
privacy: bogus-not-an-enum
install_method: self
support:
  pi: full
---
EOF
echo "# Broken Local" > "$ADDONS_STATE/brokenlocal/README.md"
assert "test flags invalid LOCAL addon" "$($ADDONS test brokenlocal 2>&1 | grep -c 'manifest invalid')" "1"
rm -rf "$ADDONS_STATE/brokenlocal"

# --- Task 3f: portable sha256 helper (shasum on macOS, sha256sum on Linux) ---
printf 'abc' > "$TEST_DIR/sha-fixture"
assert "sha256 helper matches known 'abc' digest" \
	"$($ADDONS _sha256 "$TEST_DIR/sha-fixture" 2>/dev/null)" \
	"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

# --- Task 3g: launchd setup resolves addons via dual-root (local + system) [macOS] ---
# The bug: setup-addon-launchd.sh hardcoded system/addons/<id>, so a registry-
# installed addon (lives in local/addons/) could never get its launchd job.
# Path resolution happens before any launchctl call, so it's testable here.
if [ "$(uname -s)" = "Darwin" ]; then
	LD="bash scripts/setup-addon-launchd.sh"
	mkdir -p "$ADDONS_STATE/schedaddon"
	cat > "$ADDONS_STATE/schedaddon/manifest.md" <<'EOF'
---
id: schedaddon
name: Sched Addon
install: echo x
command: bash
privacy: local
install_method: self
schedule:
  cron: "0 3 * * *"
  entrypoint: bin/schedaddon
---
EOF
	echo "# Sched" > "$ADDONS_STATE/schedaddon/README.md"
	# uninstall is idempotent + safe (no real job loaded). It must get PAST the
	# manifest-resolution check (no "no manifest" error) and exit 0 for a LOCAL addon.
	ld_out="$($LD uninstall schedaddon 2>&1; echo "rc=$?")"
	assert "launchd resolves a LOCAL addon"   "$(echo "$ld_out" | grep -c 'no manifest')" "0"
	assert "launchd uninstall local addon ok" "$(echo "$ld_out" | grep -c 'rc=0')" "1"
	# A genuinely missing addon still fails loudly.
	ld_miss="$($LD uninstall nope-missing 2>&1; echo "rc=$?")"
	assert "launchd still fails on missing addon" "$(echo "$ld_miss" | grep -c 'rc=1')" "1"
	rm -rf "$ADDONS_STATE/schedaddon"
fi

# --- Task 4: privacy prompt ---
priv_out="$(printf '' | $ADDONS _privacy graphify 2>&1; echo "rc=$?")"
assert "privacy shows level"    "$(echo "$priv_out" | grep -c 'sends-docs')" "1"
assert "privacy non-tty aborts" "$(echo "$priv_out" | grep -c 'rc=3')" "1"
assert "privacy assume-yes ok"  "$(ADDONS_ASSUME_YES=1 $ADDONS _privacy graphify >/dev/null 2>&1; echo $?)" "0"

# --- Task 5: install ---
rm -f "$ADDONS_STATE/graphify/enabled"
inst_out="$(ADDONS_ASSUME_YES=1 ADDONS_DRY_RUN=1 $ADDONS install graphify 2>&1)"
assert "install dry-runs cmd"  "$(echo "$inst_out" | grep -c 'echo installing-graphify')" "1"
assert "install enables addon" "$([ -f "$ADDONS_STATE/graphify/enabled" ] && echo yes || echo no)" "yes"

# --- Task 6: runtime health check ---
mkdir -p "$ADDONS_STATE/graphify" && : > "$ADDONS_STATE/graphify/enabled"
chk_out="$($ADDONS check 2>&1; echo "rc=$?")"
assert "check flags broken"    "$(echo "$chk_out" | grep -c 'graphify')" "1"
assert "check fails on broken" "$(echo "$chk_out" | grep -c 'rc=1')" "1"
sed -i.bak 's/^command: __graphify_test_fixture_bin__/command: bash/' "$ADDONS_REGISTRY/graphify/manifest.md"
assert "check passes when healthy" "$($ADDONS check >/dev/null 2>&1; echo $?)" "0"
sed -i.bak 's/^command: bash/command: __graphify_test_fixture_bin__/' "$ADDONS_REGISTRY/graphify/manifest.md"
# ai-driven/no-command add-on: enabled but no binary -> health OK (nothing to probe)
: > "$ADDONS_STATE/graphify/enabled"
sed -i.bak 's/^command: __graphify_test_fixture_bin__/command:/' "$ADDONS_REGISTRY/graphify/manifest.md"
assert "check ok when no command" "$($ADDONS check >/dev/null 2>&1; echo $?)" "0"
sed -i.bak 's/^command:$/command: __graphify_test_fixture_bin__/' "$ADDONS_REGISTRY/graphify/manifest.md"

# --- Task 7: static manifest validation ---
export ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY"
assert "valid manifest passes" "$(bash scripts/check-addons.sh >/dev/null 2>&1; echo $?)" "0"
cp "$ADDONS_REGISTRY/graphify/manifest.md" "$TEST_DIR/good.md"
sed 's/^privacy: sends-docs/privacy: bogus/' "$TEST_DIR/good.md" > "$ADDONS_REGISTRY/graphify/manifest.md"
assert "bad privacy fails" "$(bash scripts/check-addons.sh >/dev/null 2>&1; echo $?)" "1"
cp "$TEST_DIR/good.md" "$ADDONS_REGISTRY/graphify/manifest.md"

# --- Task 8: per-add-on validation + test command ---
assert "check-addons single id ok" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh graphify >/dev/null 2>&1; echo $?)" "0"
# README is required by check-addons
rm -f "$ADDONS_REGISTRY/graphify/README.md"
assert "missing README fails" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh graphify >/dev/null 2>&1; echo $?)" "1"
echo "# Graphify" > "$ADDONS_REGISTRY/graphify/README.md"
assert "check-addons unknown id ok (no match, no error)" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh nope >/dev/null 2>&1; echo $?)" "0"
# 'test' on the enabled-but-broken fixture: manifest valid, runtime broken -> overall FAIL (rc 1)
mkdir -p "$ADDONS_STATE/graphify" && : > "$ADDONS_STATE/graphify/enabled"
test_out="$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" $ADDONS test graphify 2>&1; echo "rc=$?")"
assert "test reports manifest valid" "$(echo "$test_out" | grep -c 'manifest valid')" "1"
assert "test fails on broken runtime" "$(echo "$test_out" | grep -c 'rc=1')" "1"
# Disabled + command missing -> static-only, overall PASS (rc 0)
rm -f "$ADDONS_STATE/graphify/enabled"
assert "test disabled is static-only pass" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" $ADDONS test graphify >/dev/null 2>&1; echo $?)" "0"

# --- Task 9: per-add-on test suite (`test:` field) runner ---
mkdir -p "$ADDONS_REGISTRY/suiteaddon"
cat > "$ADDONS_REGISTRY/suiteaddon/manifest.md" <<'EOF'
---
id: suiteaddon
name: Suite Addon
install: echo installing-suiteaddon
command: bash
privacy: local
install_method: self
test: true
support:
  pi: full
---
# Suite Addon
EOF
echo "# Suite Addon" > "$ADDONS_REGISTRY/suiteaddon/README.md"
# Passing suite (`true` is always on PATH) -> suite runs and passes.
suite_out="$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" $ADDONS test suiteaddon 2>&1; echo "rc=$?")"
assert "suite runs when runtime present" "$(echo "$suite_out" | grep -c 'test suite passed')" "1"
assert "suite pass keeps overall PASS"   "$(echo "$suite_out" | grep -c 'rc=0')" "1"
# Missing runtime -> suite is skipped (static-only), not a failure.
sed -i.bak 's/^test: true/test: __no_such_runtime__ run/' "$ADDONS_REGISTRY/suiteaddon/manifest.md"
skip_out="$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" $ADDONS test suiteaddon 2>&1; echo "rc=$?")"
assert "suite skipped when runtime absent" "$(echo "$skip_out" | grep -c 'skipping suite')" "1"
assert "suite skip keeps overall PASS"     "$(echo "$skip_out" | grep -c 'rc=0')" "1"
# Failing suite (`false`) -> overall FAIL.
sed -i.bak 's/^test: __no_such_runtime__ run/test: false/' "$ADDONS_REGISTRY/suiteaddon/manifest.md"
fail_out="$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" $ADDONS test suiteaddon 2>&1; echo "rc=$?")"
assert "suite fail flips overall FAIL" "$(echo "$fail_out" | grep -c 'rc=1')" "1"
rm -rf "$ADDONS_REGISTRY/suiteaddon"

# --- Task 10: referenced-file existence (install: + schedule.entrypoint) ---
# A manifest whose install command points at a missing .sh must FAIL; it passes
# once the file exists. Mirrors the event-bus regression (manifest referenced a
# non-existent install.sh).
mkdir -p "$ADDONS_REGISTRY/reffile"
cat > "$ADDONS_REGISTRY/reffile/manifest.md" <<'EOF'
---
id: reffile
name: Ref File
install: bash system/addons/reffile/install.sh
command: bash
privacy: local
install_method: self
support:
  pi: full
---
# Ref File
EOF
echo "# Ref File" > "$ADDONS_REGISTRY/reffile/README.md"
assert "missing install.sh fails" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "1"
ref_err="$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile 2>&1 || true)"
assert "missing install.sh names the file" "$(echo "$ref_err" | grep -c 'install references missing file')" "1"
echo '#!/usr/bin/env bash' > "$ADDONS_REGISTRY/reffile/install.sh"
# Install/uninstall symmetry: an install.sh without a matching uninstall.sh must
# FAIL (the "true inverse" contract). It passes once uninstall.sh exists.
assert "install.sh without uninstall.sh fails" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "1"
sym_err="$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile 2>&1 || true)"
assert "missing uninstall.sh names it" "$(echo "$sym_err" | grep -c 'no uninstall.sh')" "1"
echo '#!/usr/bin/env bash' > "$ADDONS_REGISTRY/reffile/uninstall.sh"
assert "install.sh present passes" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "0"
# A bare `cd <dir> && bash install.sh` form also resolves against the addon dir.
sed -i.bak 's#^install: .*#install: cd system/addons/reffile \&\& bash install.sh#' "$ADDONS_REGISTRY/reffile/manifest.md"
assert "bare install.sh form passes" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "0"
# schedule.entrypoint must exist too.
cat > "$ADDONS_REGISTRY/reffile/manifest.md" <<'EOF'
---
id: reffile
name: Ref File
install: bash system/addons/reffile/install.sh
command: bash
privacy: local
install_method: self
schedule:
  cron: "0 3 * * *"
  entrypoint: bin/reffile
support:
  pi: full
---
# Ref File
EOF
assert "missing entrypoint fails" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "1"
ep_err="$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile 2>&1 || true)"
assert "missing entrypoint names the file" "$(echo "$ep_err" | grep -c 'schedule.entrypoint references missing file')" "1"
mkdir -p "$ADDONS_REGISTRY/reffile/bin" && echo '#!/usr/bin/env bash' > "$ADDONS_REGISTRY/reffile/bin/reffile"
assert "present entrypoint passes" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "0"
# External (npm/git) install commands are not treated as local script refs.
cat > "$ADDONS_REGISTRY/reffile/manifest.md" <<'EOF'
---
id: reffile
name: Ref File
install: npm install -g some-tool && some-tool install
command: bash
privacy: local
install_method: self
support:
  pi: full
---
# Ref File
EOF
assert "external install not flagged" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "0"
rm -rf "$ADDONS_REGISTRY/reffile"

# --- Task 11: dual-root discovery + version/source columns ---
mkdir -p "$ADDONS_STATE/localaddon"
cat > "$ADDONS_STATE/localaddon/manifest.md" <<'EOF'
---
id: localaddon
name: Local Addon
version: 0.2.0
install: echo installing-localaddon
command: bash
privacy: local
install_method: self
support:
  pi: full
---
# Local Addon
EOF
status_out="$($ADDONS status)"
assert "status lists local addon"   "$(echo "$status_out" | grep -c 'localaddon')" "1"
assert "status shows local source"  "$(echo "$status_out" | grep localaddon | grep -c ' local ')" "1"
assert "status shows version"       "$(echo "$status_out" | grep localaddon | grep -c '0.2.0')" "1"
assert "status bundled source"      "$(echo "$status_out" | grep 'graphify' | grep -c 'bundled')" "1"
assert "status no-version dash"     "$(echo "$status_out" | grep 'graphify' | grep -c ' - ')" "1"
# local manifest overrides bundled for the same id
mkdir -p "$ADDONS_STATE/graphify"
cat > "$ADDONS_STATE/graphify/manifest.md" <<'EOF'
---
id: graphify
name: Graphify Local
version: 9.0.0
install: echo local-graphify
command: bash
privacy: local
install_method: self
support:
  pi: full
---
EOF
assert "local overrides bundled"    "$($ADDONS status | grep -c 'Graphify Local')" "1"
assert "no duplicate row for id"    "$($ADDONS status | grep -c '^graphify ')" "1"
rm -f "$ADDONS_STATE/graphify/manifest.md"
# check/test must also see local addons
: > "$ADDONS_STATE/localaddon/enabled"
assert "check covers local addon"   "$($ADDONS check 2>&1 | grep -c 'localaddon')" "1"
rm -f "$ADDONS_STATE/localaddon/enabled"

# --- Task 12: scaffold own addon into local/addons ---
mkdir -p "$ADDONS_REGISTRY/_template"
cp "$ROOT_DIR/system/addons/_template/manifest.md" "$ADDONS_REGISTRY/_template/manifest.md"
cp "$ROOT_DIR/system/addons/_template/README.md" "$ADDONS_REGISTRY/_template/README.md"
$ADDONS new myown "My Own Addon" >/dev/null 2>&1
assert "new creates manifest"    "$([ -f "$ADDONS_STATE/myown/manifest.md" ] && echo yes || echo no)" "yes"
assert "new substitutes id"      "$(grep -c '^id: myown' "$ADDONS_STATE/myown/manifest.md")" "1"
assert "new substitutes name"    "$(grep -c '^name: My Own Addon' "$ADDONS_STATE/myown/manifest.md")" "1"
assert "new shows in status"     "$($ADDONS status | grep myown | grep -c 'local')" "1"
assert "new rejects bad id"      "$($ADDONS new 'Bad_ID' x >/dev/null 2>&1; echo $?)" "1"
assert "new rejects existing"    "$($ADDONS new myown x >/dev/null 2>&1; echo $?)" "1"

# --- Task 13: registry config CRUD ---
export ADDONS_REGISTRIES_FILE="$TEST_DIR/registries.json"
# Network isolation: default points at a local EMPTY index for all registry
# tests below (no GitHub fetch). default is always present but contributes no
# candidates; individual tests override it via ADDONS_DEFAULT_URL when needed.
echo '{"registry":"default","addons":[]}' > "$TEST_DIR/empty-default.json"
echo "file://$TEST_DIR/empty-default.json" > "$TEST_DIR/test-default-url"
export ADDONS_DEFAULT_URL_FILE="$TEST_DIR/test-default-url"
reg_out="$($ADDONS registry list)"
assert "default default present"  "$(echo "$reg_out" | grep -c 'default')" "1"
$ADDONS registry add myreg "file://$TEST_DIR/registry/index.json" >/dev/null
assert "registry add persists"     "$($ADDONS registry list | grep -c 'myreg')" "1"
assert "add keeps default"        "$($ADDONS registry list | grep -c 'default')" "1"
assert "dupe name fails"           "$($ADDONS registry add myreg http://x >/dev/null 2>&1; echo $?)" "1"
assert "bad name fails"            "$($ADDONS registry add 'a/b' http://x >/dev/null 2>&1; echo $?)" "1"
assert "cannot add default"       "$($ADDONS registry add default http://x >/dev/null 2>&1; echo $?)" "1"
assert "cannot remove default"    "$($ADDONS registry remove default >/dev/null 2>&1; echo $?)" "1"
$ADDONS registry remove myreg >/dev/null
assert "registry remove works"     "$($ADDONS registry list | grep -c 'myreg')" "0"
# default stays present (dynamic, empty index) — never removable, no network
assert "default still present"    "$($ADDONS registry list | grep -c 'default')" "1"

# --- Task 14: fixture registry (file://) + search ---
mkdir -p "$TEST_DIR/pkg/remoteaddon"
cat > "$TEST_DIR/pkg/remoteaddon/manifest.md" <<'EOF'
---
id: remoteaddon
name: Remote Addon
version: 1.1.0
install: echo installing-remoteaddon
command: bash
privacy: local
install_method: self
support:
  pi: full
---
# Remote Addon
EOF
echo "# Remote Addon" > "$TEST_DIR/pkg/remoteaddon/README.md"
mkdir -p "$TEST_DIR/registry"
(cd "$TEST_DIR/pkg" && zip -r -q "$TEST_DIR/registry/addon-remoteaddon-v1.1.0.zip" remoteaddon)
FIX_SHA=$(shasum -a 256 "$TEST_DIR/registry/addon-remoteaddon-v1.1.0.zip" | awk '{print $1}')
cat > "$TEST_DIR/registry/index.json" <<EOF
{ "registry": "myreg", "addons": [ { "id": "remoteaddon", "name": "Remote Addon",
  "version": "1.1.0", "description": "Test fixture",
  "url": "file://$TEST_DIR/registry/addon-remoteaddon-v1.1.0.zip",
  "sha256": "$FIX_SHA", "privacy": "local" } ] }
EOF
$ADDONS registry add myreg "file://$TEST_DIR/registry/index.json" >/dev/null
search_out="$($ADDONS search 2>/dev/null)"
assert "search lists registry addon" "$(echo "$search_out" | grep -c 'remoteaddon')" "1"
assert "search shows reg source"     "$(echo "$search_out" | grep remoteaddon | grep -c 'myreg')" "1"
assert "search shows version"        "$(echo "$search_out" | grep remoteaddon | grep -c '1.1.0')" "1"
assert "search lists local too"      "$(echo "$search_out" | grep -c 'localaddon')" "1"
assert "search term filters"         "$($ADDONS search graphify 2>/dev/null | grep -c 'remoteaddon')" "0"
# dupe across registries: newest first, marked
cat > "$TEST_DIR/registry/index2.json" <<EOF
{ "registry": "secondreg", "addons": [ { "id": "remoteaddon", "name": "Remote Addon",
  "version": "1.0.0", "description": "Older copy",
  "url": "file://$TEST_DIR/registry/addon-remoteaddon-v1.1.0.zip",
  "sha256": "$FIX_SHA", "privacy": "local" } ] }
EOF
$ADDONS registry add secondreg "file://$TEST_DIR/registry/index2.json" >/dev/null
dupe_out="$($ADDONS search remoteaddon 2>/dev/null)"
assert "dupe shows both sources" "$(echo "$dupe_out" | grep -c 'remoteaddon')" "2"
assert "newest is marked"        "$(echo "$dupe_out" | grep '1.1.0' | grep -c 'newest')" "1"
assert "older not marked"        "$(echo "$dupe_out" | grep '1.0.0' | grep -c 'newest')" "0"
$ADDONS registry remove secondreg >/dev/null

# --- Task 15: install from registry ---
inst_out="$(ADDONS_ASSUME_YES=1 ADDONS_DRY_RUN=1 $ADDONS install remoteaddon 2>&1)"
assert "install names source"     "$(echo "$inst_out" | grep -c "registry 'myreg'")" "1"
assert "install unpacks to local" "$([ -f "$ADDONS_STATE/remoteaddon/manifest.md" ] && echo yes || echo no)" "yes"
assert "install enables"          "$([ -f "$ADDONS_STATE/remoteaddon/enabled" ] && echo yes || echo no)" "yes"
assert "installed shows local"    "$($ADDONS status | grep remoteaddon | grep -c 'local')" "1"
# second install resolves locally (no re-download)
inst2_out="$(ADDONS_ASSUME_YES=1 ADDONS_DRY_RUN=1 $ADDONS install remoteaddon 2>&1)"
assert "reinstall stays local"    "$(echo "$inst2_out" | grep -c "registry 'myreg'")" "0"
rm -rf "$ADDONS_STATE/remoteaddon"
# sha256 mismatch must hard-fail and not unpack
sed "s/$FIX_SHA/0000000000000000000000000000000000000000000000000000000000000000/" \
	"$TEST_DIR/registry/index.json" > "$TEST_DIR/registry/index.bad.json"
$ADDONS registry remove myreg >/dev/null
$ADDONS registry add myreg "file://$TEST_DIR/registry/index.bad.json" >/dev/null
bad_out="$(ADDONS_ASSUME_YES=1 $ADDONS install remoteaddon 2>&1; echo "rc=$?")"
assert "sha mismatch fails"       "$(echo "$bad_out" | grep -c 'sha256 mismatch')" "1"
assert "sha mismatch rc nonzero"  "$(echo "$bad_out" | grep -c 'rc=1')" "1"
assert "sha mismatch no unpack"   "$([ -f "$ADDONS_STATE/remoteaddon/manifest.md" ] && echo yes || echo no)" "no"
$ADDONS registry remove myreg >/dev/null
$ADDONS registry add myreg "file://$TEST_DIR/registry/index.json" >/dev/null
# default precedence: an 'default' registry carrying 1.0.0 beats third-party 9.9.9
mkdir -p "$TEST_DIR/pkg2/remoteaddon"
sed 's/^version: 1.1.0/version: 1.0.0/' "$TEST_DIR/pkg/remoteaddon/manifest.md" > "$TEST_DIR/pkg2/remoteaddon/manifest.md"
(cd "$TEST_DIR/pkg2" && zip -r -q "$TEST_DIR/registry/addon-remoteaddon-v1.0.0.zip" remoteaddon)
OFF_SHA=$(shasum -a 256 "$TEST_DIR/registry/addon-remoteaddon-v1.0.0.zip" | awk '{print $1}')
cat > "$TEST_DIR/registry/index.default.json" <<EOF
{ "registry": "default", "addons": [ { "id": "remoteaddon", "name": "Remote Addon",
  "version": "1.0.0", "url": "file://$TEST_DIR/registry/addon-remoteaddon-v1.0.0.zip",
  "sha256": "$OFF_SHA", "privacy": "local" } ] }
EOF
cat > "$TEST_DIR/registry/index.evil.json" <<EOF
{ "registry": "evilreg", "addons": [ { "id": "remoteaddon", "name": "Remote Addon",
  "version": "9.9.9", "url": "file://$TEST_DIR/registry/addon-remoteaddon-v1.1.0.zip",
  "sha256": "$FIX_SHA", "privacy": "local" } ] }
EOF
$ADDONS registry remove myreg >/dev/null
# default is set via ADDONS_DEFAULT_URL (env beats the per-machine file);
# evilreg is a normal named registry.
$ADDONS registry add evilreg "file://$TEST_DIR/registry/index.evil.json" >/dev/null
off_out="$(ADDONS_DEFAULT_URL="file://$TEST_DIR/registry/index.default.json" ADDONS_ASSUME_YES=1 ADDONS_DRY_RUN=1 $ADDONS install remoteaddon 2>&1)"
assert "default wins over higher third-party" "$(echo "$off_out" | grep -c "registry 'default'")" "1"
assert "default version installed" "$(grep -c '^version: 1.0.0' "$ADDONS_STATE/remoteaddon/manifest.md")" "1"
rm -rf "$ADDONS_STATE/remoteaddon"
# explicit registry/id pin overrides default precedence
pin_out="$(ADDONS_ASSUME_YES=1 ADDONS_DRY_RUN=1 $ADDONS install evilreg/remoteaddon 2>&1)"
assert "pin selects pinned registry" "$(echo "$pin_out" | grep -c "registry 'evilreg'")" "1"
rm -rf "$ADDONS_STATE/remoteaddon"
$ADDONS registry remove evilreg >/dev/null
$ADDONS registry add myreg "file://$TEST_DIR/registry/index.json" >/dev/null
# unknown id in registries fails cleanly
assert "unknown registry id fails" "$(ADDONS_ASSUME_YES=1 $ADDONS install nope-addon >/dev/null 2>&1; echo $?)" "1"

# --- Task 16: update + status --remote ---
# install fixture 1.1.0, then registry moves to 1.2.0
ADDONS_ASSUME_YES=1 ADDONS_DRY_RUN=1 $ADDONS install remoteaddon >/dev/null 2>&1
mkdir -p "$TEST_DIR/pkg3/remoteaddon"
sed 's/^version: 1.1.0/version: 1.2.0/' "$TEST_DIR/pkg/remoteaddon/manifest.md" > "$TEST_DIR/pkg3/remoteaddon/manifest.md"
(cd "$TEST_DIR/pkg3" && zip -r -q "$TEST_DIR/registry/addon-remoteaddon-v1.2.0.zip" remoteaddon)
NEW_SHA=$(shasum -a 256 "$TEST_DIR/registry/addon-remoteaddon-v1.2.0.zip" | awk '{print $1}')
cat > "$TEST_DIR/registry/index.json" <<EOF
{ "registry": "myreg", "addons": [ { "id": "remoteaddon", "name": "Remote Addon",
  "version": "1.2.0", "url": "file://$TEST_DIR/registry/addon-remoteaddon-v1.2.0.zip",
  "sha256": "$NEW_SHA", "privacy": "local" } ] }
EOF
remote_out="$($ADDONS status --remote 2>/dev/null)"
assert "remote shows update"       "$(echo "$remote_out" | grep remoteaddon | grep -c '1.2.0')" "1"
assert "remote names registry"     "$(echo "$remote_out" | grep remoteaddon | grep -c 'myreg')" "1"
upd_out="$($ADDONS update remoteaddon 2>&1)"
assert "update reports versions"   "$(echo "$upd_out" | grep -c '1.1.0 -> 1.2.0')" "1"
assert "update replaces manifest"  "$(grep -c '^version: 1.2.0' "$ADDONS_STATE/remoteaddon/manifest.md")" "1"
upd2_out="$($ADDONS update remoteaddon 2>&1)"
assert "update idempotent"         "$(echo "$upd2_out" | grep -c 'up-to-date')" "1"
assert "update unknown fails"      "$($ADDONS update nope >/dev/null 2>&1; echo $?)" "1"
rm -rf "$ADDONS_STATE/remoteaddon"

# --- Task 17: privacy-scan --dir ---
mkdir -p "$TEST_DIR/clean" "$TEST_DIR/dirty"
echo "just docs" > "$TEST_DIR/clean/README.md"
# Fake secret assembled at runtime so the repo's own privacy scan never matches
# this test file itself.
FAKE_TOKEN="gh""p_0123456789abcdef0123456789abcdef"
echo "token: $FAKE_TOKEN" > "$TEST_DIR/dirty/leak.txt"
assert "privacy --dir clean passes" "$(bash scripts/privacy-scan.sh --dir "$TEST_DIR/clean" >/dev/null 2>&1; echo $?)" "0"
assert "privacy --dir dirty fails"  "$(bash scripts/privacy-scan.sh --dir "$TEST_DIR/dirty" >/dev/null 2>&1; echo $?)" "1"

# --- Task 18: package-addon ---
pkg_out="$(OUT_DIR="$TEST_DIR/out" bash scripts/package-addon.sh localaddon \
	--roots "$ADDONS_STATE:$ADDONS_REGISTRY" 2>&1; echo "rc=$?")"
assert "package builds zip"     "$([ -f "$TEST_DIR/out/addon-localaddon-v0.2.0.zip" ] && echo yes || echo no)" "yes"
assert "package writes sha256"  "$([ -f "$TEST_DIR/out/addon-localaddon-v0.2.0.zip.sha256" ] && echo yes || echo no)" "yes"
assert "package rc 0"           "$(echo "$pkg_out" | grep -c 'rc=0')" "1"
assert "zip contains manifest"  "$(unzip -l "$TEST_DIR/out/addon-localaddon-v0.2.0.zip" | grep -c 'localaddon/manifest.md')" "1"
# state files never ship
: > "$ADDONS_STATE/localaddon/enabled"
OUT_DIR="$TEST_DIR/out2" bash scripts/package-addon.sh localaddon --roots "$ADDONS_STATE:$ADDONS_REGISTRY" >/dev/null 2>&1
assert "enabled marker excluded" "$(unzip -l "$TEST_DIR/out2/addon-localaddon-v0.2.0.zip" | grep -c 'localaddon/enabled')" "0"
rm -f "$ADDONS_STATE/localaddon/enabled"
assert "package unknown fails"  "$(OUT_DIR="$TEST_DIR/out" bash scripts/package-addon.sh nope --roots "$ADDONS_STATE:$ADDONS_REGISTRY" >/dev/null 2>&1; echo $?)" "1"
# dirty payload is refused by the privacy gate (FAKE_TOKEN from Task 17)
echo "$FAKE_TOKEN" > "$ADDONS_STATE/localaddon/secret.txt"
assert "dirty payload refused"  "$(OUT_DIR="$TEST_DIR/out3" bash scripts/package-addon.sh localaddon --roots "$ADDONS_STATE:$ADDONS_REGISTRY" >/dev/null 2>&1; echo $?)" "1"
rm -f "$ADDONS_STATE/localaddon/secret.txt"

# --- Task 19: registry-index + end-to-end own-registry flow ---
idx_out="$(bash scripts/registry-index.sh --dir "$TEST_DIR/out" \
	--url-template "file://$TEST_DIR/out/{file}" --name testidx 2>&1)"
assert "index has registry name" "$(echo "$idx_out" | jq -r '.registry')" "testidx"
assert "index lists addon"       "$(echo "$idx_out" | jq -r '.addons[0].id')" "localaddon"
assert "index has version"       "$(echo "$idx_out" | jq -r '.addons[0].version')" "0.2.0"
assert "index sha matches file"  "$(echo "$idx_out" | jq -r '.addons[0].sha256')" \
	"$(awk '{print $1}' "$TEST_DIR/out/addon-localaddon-v0.2.0.zip.sha256")"
assert "index url templated"     "$(echo "$idx_out" | jq -r '.addons[0].url')" \
	"file://$TEST_DIR/out/addon-localaddon-v0.2.0.zip"
# end-to-end: the generated index is a working registry
bash scripts/registry-index.sh --dir "$TEST_DIR/out" \
	--url-template "file://$TEST_DIR/out/{file}" --name testidx \
	--out "$TEST_DIR/out/index.json" >/dev/null
$ADDONS registry add testidx "file://$TEST_DIR/out/index.json" >/dev/null
rm -rf "$ADDONS_STATE/localaddon"
e2e_out="$(ADDONS_ASSUME_YES=1 ADDONS_DRY_RUN=1 $ADDONS install localaddon 2>&1)"
assert "e2e install from own registry" "$(echo "$e2e_out" | grep -c "registry 'testidx'")" "1"
assert "e2e unpacked"                  "$([ -f "$ADDONS_STATE/localaddon/manifest.md" ] && echo yes || echo no)" "yes"
$ADDONS registry remove testidx >/dev/null

# --- Task 20: registries_list resilient to empty/corrupt file ---
EMPTY_REG="$TEST_DIR/empty-registries.json"
: > "$EMPTY_REG"   # zero-byte file (corruption / truncation)
empty_out="$(ADDONS_REGISTRIES_FILE="$EMPTY_REG" $ADDONS registry list 2>/dev/null)"
assert "empty file falls back to default" "$(echo "$empty_out" | grep -c 'default')" "1"
empty_warn="$(ADDONS_REGISTRIES_FILE="$EMPTY_REG" $ADDONS registry list 2>&1 >/dev/null)"
assert "empty file warns loudly"           "$(echo "$empty_warn" | grep -c 'empty/invalid')" "1"
echo "not json at all" > "$EMPTY_REG"
bad_out="$(ADDONS_REGISTRIES_FILE="$EMPTY_REG" $ADDONS registry list 2>/dev/null)"
assert "corrupt file falls back to default" "$(echo "$bad_out" | grep -c 'default')" "1"

# --- Task 21: privacy-scan --dir skips .git (internal remote URL is not a leak) ---
# Assemble the fake internal host at runtime so this source file never contains a
# literal that the repo's own privacy scan would flag (mirrors FAKE_TOKEN above).
FAKE_HOST="internalhost"".local:3000"
mkdir -p "$TEST_DIR/repo/.git"
echo "clean public content" > "$TEST_DIR/repo/index.json"
# A .git/config with an internal .local remote must NOT trip the scan.
printf '[remote "origin"]\n\turl = http://%s/x/y.git\n' "$FAKE_HOST" > "$TEST_DIR/repo/.git/config"
assert "scan ignores .git remote" "$(bash scripts/privacy-scan.sh --dir "$TEST_DIR/repo" >/dev/null 2>&1; echo $?)" "0"
# But a .local host in tracked content IS still a leak.
echo "see http://$FAKE_HOST/docs" > "$TEST_DIR/repo/README.md"
assert "scan still catches content leak" "$(bash scripts/privacy-scan.sh --dir "$TEST_DIR/repo" >/dev/null 2>&1; echo $?)" "1"

# --- Task 22: registry-index validates generated URLs (no broken templates) ---
RI="bash scripts/registry-index.sh --dir $TEST_DIR/out"
# A template missing {file} leaves no usable url path; a literal brace must fail.
assert "broken template (stray brace) fails" \
	"$($RI --url-template 'https://x/{tag/{file}' --name t >/dev/null 2>&1; echo $?)" "1"
assert "non-http template fails" \
	"$($RI --url-template 'ftp://x/{tag}/{file}' --name t >/dev/null 2>&1; echo $?)" "1"
assert "valid template passes" \
	"$($RI --url-template 'https://x/{tag}/{file}' --name t >/dev/null 2>&1; echo $?)" "0"
brk_err="$($RI --url-template 'https://x/{tag/{file}' --name t 2>&1 || true)"
assert "broken template names the problem" "$(echo "$brk_err" | grep -c 'placeholder')" "1"

# --- Task 23: privacy-scan --git-identity rejects non-noreply emails in history ---
IDREPO="$TEST_DIR/idrepo"
mkdir -p "$IDREPO" && (cd "$IDREPO" && git init -q && \
	git -c user.name=x -c user.email=x@users.noreply.github.com commit -q --allow-empty -m one)
assert "noreply-only history passes" \
	"$(bash scripts/privacy-scan.sh --git-identity "$IDREPO" >/dev/null 2>&1; echo $?)" "0"
REALMAIL="real""@example.com"
(cd "$IDREPO" && git -c user.name=x -c user.email="$REALMAIL" commit -q --allow-empty -m two)
assert "real email in history fails" \
	"$(bash scripts/privacy-scan.sh --git-identity "$IDREPO" >/dev/null 2>&1; echo $?)" "1"
id_err="$(bash scripts/privacy-scan.sh --git-identity "$IDREPO" 2>&1 || true)"
assert "real email is reported" "$(echo "$id_err" | grep -c 'example.com')" "1"

# --- Task 24: per-machine default-registry override (dev=Gitea, default=GitHub) ---
OFF_FILE="$TEST_DIR/default-url"
rm -f "$OFF_FILE"
export ADDONS_DEFAULT_URL_FILE="$OFF_FILE"
# Default: baked GitHub, no override file.
assert "default default is github" \
	"$(ADDONS_REGISTRIES_FILE=/nope $ADDONS registry default 2>/dev/null | grep -c 'raw.githubusercontent.com')" "1"
# Set a per-machine override -> becomes active, file persisted.
$ADDONS registry default "file://$TEST_DIR/registry/index.json" >/dev/null
assert "set writes override file" "$([ -s "$OFF_FILE" ] && echo yes || echo no)" "yes"
assert "override is now active" \
	"$(ADDONS_REGISTRIES_FILE=/nope $ADDONS registry default 2>/dev/null | grep -c "$TEST_DIR/registry/index.json")" "1"
# env beats the file.
assert "env overrides file" \
	"$(ADDONS_DEFAULT_URL=https://envwins/x.json ADDONS_REGISTRIES_FILE=/nope $ADDONS registry default 2>/dev/null | grep -c 'envwins')" "1"
# reset restores the baked default.
$ADDONS registry default reset >/dev/null
assert "reset removes file" "$([ -f "$OFF_FILE" ] && echo no || echo yes)" "yes"
assert "reset back to github" \
	"$(ADDONS_REGISTRIES_FILE=/nope $ADDONS registry default 2>/dev/null | grep -c 'raw.githubusercontent.com')" "1"
unset ADDONS_DEFAULT_URL_FILE

# --- Task 25: regression guard — URL_TEMPLATE default must not use the brace-eating form ---
# The bug: `${VAR:-...{tag}/{file}}` lets bash close the expansion at the first
# "}", corrupting the template to "{tag/{file}}" and shipping broken URLs. Both
# publish scripts must use the two-step default instead. Guard against reverting.
for s in publish-addon.sh mirror-registry-github.sh; do
	# Maintainer-only publish scripts, excluded from end-user release archives.
	# Skip their regression guards when the script isn't present (fresh install).
	[ -f "$ROOT_DIR/scripts/$s" ] || continue
	# Single-quoted regexes below are grep patterns, not shell expansions.
	# shellcheck disable=SC2016
	# No template-with-placeholders inside a ${...:-...} default.
	assert "no brace-eating default in $s" \
		"$(grep -cE '\$\{URL_TEMPLATE:-[^}]*\{(tag|file|id|version)\}' "$ROOT_DIR/scripts/$s")" "0"
	# shellcheck disable=SC2016
	# The safe two-step assignment is present.
	assert "two-step URL default in $s" \
		"$(grep -c '\[ -n "\$URL_TEMPLATE" \] || URL_TEMPLATE=' "$ROOT_DIR/scripts/$s")" "1"
done
# registry-index actually rejects a corrupted template (defence in depth).
assert "registry-index rejects {-corrupted url" \
	"$(bash "$ROOT_DIR/scripts/registry-index.sh" --dir "$TEST_DIR/out" --url-template 'https://x/{tag/{file}' --name t >/dev/null 2>&1; echo $?)" "1"

# --- Task 26: release-published advisory guard ---
CRP="bash scripts/check-release-published.sh"
curver="$(tr -d '[:space:]' < VERSION)"
assert "release-published: published → exit 0" \
	"$(RELEASE_TAGS_OVERRIDE="v1.0.0 v$curver" $CRP >/dev/null 2>&1; echo $?)" "0"
assert "release-published: unpublished → exit 3" \
	"$(RELEASE_TAGS_OVERRIDE="v1.0.0 v9.9.9" $CRP >/dev/null 2>&1; echo $?)" "3"
assert "release-published: can't-determine → exit 0 (non-blocking)" \
	"$(RELEASE_TAGS_OVERRIDE="" GITEA_URL="" $CRP >/dev/null 2>&1; echo $?)" "0"
crp_warn="$(RELEASE_TAGS_OVERRIDE='v1.0.0' $CRP 2>&1 || true)"
assert "release-published warns with the cut command" "$(echo "$crp_warn" | grep -c 'publish-gitea-release')" "1"

# --- Task 27: _list YAML-lijst parser (inline + block) ---
MF="$TEST_DIR/list.md"
cat > "$MF" <<'LISTEOF'
---
id: x
requires: [keychain, node]
scheduler:
  - launchd
  - systemd
---
LISTEOF
assert "_list inline"   "$($ADDONS _list "$MF" requires | tr -s ' ' | sed 's/ *$//')"  "keychain node"
assert "_list block"    "$($ADDONS _list "$MF" scheduler | tr -s ' ' | sed 's/ *$//')" "launchd systemd"
assert "_list missing"  "$($ADDONS _list "$MF" nope)"                                   ""

# --- onboard.run: referenced .sh must exist (mirrors install: / schedule.entrypoint) ---
mkdir -p "$ADDONS_REGISTRY/reffile"
echo '#!/usr/bin/env bash' > "$ADDONS_REGISTRY/reffile/install.sh"
echo '#!/usr/bin/env bash' > "$ADDONS_REGISTRY/reffile/uninstall.sh"
echo '# Ref File' > "$ADDONS_REGISTRY/reffile/README.md"
cat > "$ADDONS_REGISTRY/reffile/manifest.md" <<'EOF'
---
id: reffile
name: Ref File
install: bash system/addons/reffile/install.sh
command: bash
privacy: local
install_method: self
onboard:
  run: bash system/addons/reffile/onboard.sh
support:
  pi: full
---
# Ref File
EOF
rm -f "$ADDONS_REGISTRY/reffile/onboard.sh"
assert "missing onboard.run fails" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "1"
ob_err="$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile 2>&1 || true)"
assert "missing onboard.run names the file" "$(echo "$ob_err" | grep -c 'onboard.run references missing file')" "1"
echo '#!/usr/bin/env bash' > "$ADDONS_REGISTRY/reffile/onboard.sh"
assert "present onboard.run passes" "$(ADDONS_CHECK_REGISTRY="$ADDONS_REGISTRY" bash scripts/check-addons.sh reffile >/dev/null 2>&1; echo $?)" "0"

# --- onboard install prompt: offered on install (dry-run echoes the run cmd) ---
mkdir -p "$ADDONS_REGISTRY/obtest"
echo '#!/usr/bin/env bash' > "$ADDONS_REGISTRY/obtest/install.sh"
echo '#!/usr/bin/env bash' > "$ADDONS_REGISTRY/obtest/onboard.sh"
cat > "$ADDONS_REGISTRY/obtest/manifest.md" <<'EOF'
---
id: obtest
name: Onboard Test
install: bash system/addons/obtest/install.sh
command: bash
privacy: local
install_method: self
onboard:
  run: bash system/addons/obtest/onboard.sh
  prompt: "Run the obtest setup now?"
support:
  pi: full
---
# Onboard Test
EOF
ob_inst="$(ADDONS_ASSUME_YES=1 ADDONS_DRY_RUN=1 $ADDONS install obtest 2>&1)"
assert "install offers onboard (dry-run echoes run cmd)" "$(echo "$ob_inst" | grep -c 'obtest/onboard.sh')" "1"

# --- onboard subcommand: runs the step directly; no-op without a block ---
ob_run="$(ADDONS_DRY_RUN=1 $ADDONS onboard obtest 2>&1 || true)"
assert "onboard subcommand runs step" "$(echo "$ob_run" | grep -c 'obtest/onboard.sh')" "1"
ob_none="$(ADDONS_DRY_RUN=1 $ADDONS onboard graphify 2>&1; echo "rc=$?")"
assert "onboard on addon without block is a no-op" "$(echo "$ob_none" | grep -c 'rc=0')" "1"

# --- the _template documents the onboard: hook so addon authors discover it ---
assert "_template documents onboard:" "$(grep -c 'onboard:' system/addons/_template/manifest.md)" "1"

# --- Task 17: update re-runs the new version's install step + keeps enabled ---
# Package updaddon v2.0.0 whose install writes an observable marker, register it.
mkdir -p "$TEST_DIR/pkg/updaddon"
cat > "$TEST_DIR/pkg/updaddon/manifest.md" <<EOF
---
id: updaddon
name: Upd Addon
version: 2.0.0
install: touch $TEST_DIR/updaddon-reinstalled
command: bash
privacy: local
install_method: self
support:
  pi: full
---
# Upd Addon
EOF
echo "# Upd Addon" > "$TEST_DIR/pkg/updaddon/README.md"
(cd "$TEST_DIR/pkg" && zip -r -q "$TEST_DIR/registry/addon-updaddon-v2.0.0.zip" updaddon)
UPD_SHA=$($ADDONS _sha256 "$TEST_DIR/registry/addon-updaddon-v2.0.0.zip")
cat > "$TEST_DIR/registry/upd-index.json" <<EOF
{ "registry": "updreg", "addons": [ { "id": "updaddon", "name": "Upd Addon",
  "version": "2.0.0", "url": "file://$TEST_DIR/registry/addon-updaddon-v2.0.0.zip",
  "sha256": "$UPD_SHA", "privacy": "local" } ] }
EOF
$ADDONS registry add updreg "file://$TEST_DIR/registry/upd-index.json" >/dev/null
# Pre-existing install at v1.0.0, enabled, marker absent.
mkdir -p "$ADDONS_STATE/updaddon"
sed 's/^version: 2.0.0/version: 1.0.0/; s#^install: .*#install: echo old#' \
	"$TEST_DIR/pkg/updaddon/manifest.md" > "$ADDONS_STATE/updaddon/manifest.md"
echo "# Upd Addon" > "$ADDONS_STATE/updaddon/README.md"
: > "$ADDONS_STATE/updaddon/enabled"
rm -f "$TEST_DIR/updaddon-reinstalled"
ADDONS_ASSUME_YES=1 $ADDONS update updaddon >/dev/null 2>&1
assert "update re-runs new install step" "$([ -f "$TEST_DIR/updaddon-reinstalled" ] && echo yes || echo no)" "yes"
assert "update bumps installed version"  "$(grep -c '^version: 2.0.0' "$ADDONS_STATE/updaddon/manifest.md")" "1"
assert "update keeps addon enabled"      "$([ -f "$ADDONS_STATE/updaddon/enabled" ] && echo yes || echo no)" "yes"
$ADDONS registry remove updreg >/dev/null
rm -rf "$ADDONS_STATE/updaddon" "$TEST_DIR/updaddon-reinstalled"

# ---- report ----
echo "passed=$passed failed=$failed"
if [ "$failed" -gt 0 ]; then
	printf '%s\n' "${failures[@]}" >&2
	exit 1
fi
