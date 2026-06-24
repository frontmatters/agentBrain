#!/usr/bin/env bash
# check-launchd-templates.sh — plutil -lint all launchd plist templates after
# placeholder substitution. Catches plist corruption (malformed XML, missing
# closing tags, wrong-type values) at commit/deploy time, not at install time.
#
# Templates use {{VAULT}} and {{HOME}} as placeholders. We substitute with
# test paths and lint the result — same way setup-launchd-loop.sh renders.
#
# Runs in doctor's public_checks. macOS only (plutil); skip elsewhere.
#
# Usage: bash scripts/check-launchd-templates.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="$ROOT_DIR/system/launchd"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "check-launchd-templates: not macOS — skip"
	exit 0
fi

if [ ! -d "$TEMPLATE_DIR" ]; then
	echo "check-launchd-templates: no system/launchd/ dir — skip"
	exit 0
fi

shopt -s nullglob
TEMPLATES=("$TEMPLATE_DIR"/*.plist.template)
shopt -u nullglob

if [ ${#TEMPLATES[@]} -eq 0 ]; then
	echo "check-launchd-templates: no templates found — skip"
	exit 0
fi

PASS=0
FAIL=0
for tmpl in "${TEMPLATES[@]}"; do
	name="$(basename "$tmpl")"
	rendered="$(mktemp "${TMPDIR:-/tmp}/launchd-render-XXXXXX.plist")"
	# Substitute all known placeholders with valid dummy plist fragments so
	# plutil -lint sees structurally valid XML. addon.plist.template uses
	# more placeholders than dev.agentbrain.loop.plist.template — keep the
	# list permissive.
	sed -e "s|{{VAULT}}|/tmp/test-vault|g" \
	    -e "s|{{HOME}}|/tmp/test-home|g" \
	    -e "s|{{LABEL}}|test.label|g" \
	    -e "s|{{COMMAND_PATH}}|/tmp/test-cmd|g" \
	    -e "s|{{LOG_OUT}}|/tmp/test.out|g" \
	    -e "s|{{LOG_ERR}}|/tmp/test.err|g" \
	    -e "s|{{ARGS_XML}}|<string>--test</string>|g" \
	    -e "s|{{SCHEDULE_XML}}|<key>RunAtLoad</key><true/>|g" \
	    "$tmpl" > "$rendered"
	if plutil -lint "$rendered" >/dev/null 2>&1; then
		echo "  ✓ $name"
		PASS=$((PASS+1))
	else
		echo "  ✗ $name — plutil -lint failed:" >&2
		plutil -lint "$rendered" >&2 || true
		FAIL=$((FAIL+1))
	fi
	rm -f "$rendered"
done

if [ "$FAIL" -gt 0 ]; then
	echo "check-launchd-templates: $FAIL failed, $PASS passed"
	exit 1
fi
echo "check-launchd-templates: ✅ $PASS template(s) valid"
