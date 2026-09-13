#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-ext-verify.sh — an extension row is judged by what the editor carries.
#
# The editor CLI exits non-zero when any extension in a batch fails, and a
# bundled dependency that is already newer than the one being pulled in is one
# of the ways a batch fails:
#
#   Installing extension 'github.copilot'...
#   Error while installing extension github.copilot-chat: Extension
#   'github.copilot-chat' is a built-in extension with version '0.65.0' and
#   cannot be downgraded to version '0.48.1'.
#
# github.copilot installed. The row reported a failure and told the user to run
# by hand the command that had just worked.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
SRC="$ROOT_DIR/scripts/tools/install-agent-clis.sh"

pass=0; fail=0
t_ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
t_bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-ext-verify.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# A stand-in for the editor CLI. CARRIES lists what it reports as installed;
# the install itself always fails, exactly as it did on the real machine.
cat > "$TMP/code" <<'EOS'
#!/bin/sh
case "$1" in
  --list-extensions) printf '%s\n' $CARRIES ;;
  --install-extension)
    echo "Installing extension 'github.copilot'..."
    echo "Error while installing extension github.copilot-chat: Extension 'github.copilot-chat' is a built-in extension with version '0.65.0' and cannot be downgraded to version '0.48.1'." >&2
    echo "Failed Installing Extensions: github.copilot-chat" >&2
    exit 1 ;;
esac
EOS
chmod +x "$TMP/code"

# Source just the helper, from a real file: bash 3.2 cannot source a pipe.
sed -n '/^_ext_present()/,/^}/p' "$SRC" > "$TMP/helper.sh"
# shellcheck disable=SC1091
. "$TMP/helper.sh"

# --- 1. the editor answers in lower case, the row asks in mixed case ---------
CARRIES="github.copilot" ; export CARRIES
if _ext_present "$TMP/code" "GitHub.copilot"; then
	t_ok "GitHub.copilot is found although the editor says github.copilot"
else
	t_bad "case difference hid an installed extension"
fi

# --- 2. an extension that is not there stays not there -----------------------
if _ext_present "$TMP/code" "GitHub.copilot-nonexistent"; then
	t_bad "reported an extension the editor does not carry"
else
	t_ok "an absent extension stays absent"
fi

# --- 3. no partial match: a longer id must not satisfy a shorter one ---------
# grep without -x would let github.copilot-chat answer for github.copilot.
CARRIES="github.copilot-chat"
if _ext_present "$TMP/code" "GitHub.copilot"; then
	t_bad "github.copilot-chat was accepted as github.copilot"
else
	t_ok "a longer id does not satisfy a shorter one"
fi

# --- 4. the verdict the row reaches on the real failure ----------------------
# Install exits 1, the editor carries what was asked for: that is a success.
CARRIES="github.copilot"
"$TMP/code" --install-extension GitHub.copilot >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && _ext_present "$TMP/code" "GitHub.copilot"; then
	t_ok "non-zero exit plus the extension present is judged a success"
else
	t_bad "the fixture no longer reproduces the reported failure (rc=$rc)"
fi

# --- 5. and a real failure is still a failure --------------------------------
CARRIES=""
if _ext_present "$TMP/code" "GitHub.copilot"; then
	t_bad "an install that truly failed was called a success"
else
	t_ok "an install that truly failed stays a failure"
fi

if [ "$((pass + fail))" -lt 5 ]; then
	printf 'ext-verify: only %d assertion(s) ran\n' "$((pass + fail))" >&2; exit 1
fi
printf 'ext-verify: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
