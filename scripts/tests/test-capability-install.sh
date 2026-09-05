#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"; cd "$ROOT_DIR"
. scripts/lib/platform.sh
. scripts/lib/capability-install.sh
fails=0
assert() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got:$2 want:$3)"; fails=$((fails+1)); fi; }

# A known capability yields a non-empty recipe on this OS (macOS has brew arms).
cmd="$(capability_install_cmd ollama)"
if [ -n "$cmd" ]; then assert "ollama recipe" yes yes; else assert "ollama recipe" no yes; fi
# Unknown capability yields empty.
cmd="$(capability_install_cmd nope-cap)"
if [ -z "$cmd" ]; then assert "unknown empty" yes yes; else assert "unknown empty" no yes; fi
# offer_install on an already-present capability returns 0 without prompting.
present=""; for c in uv node clipboard; do platform_has "$c" && { present="$c"; break; }; done
if [ -n "$present" ]; then AGENTBRAIN_ASSUME_NO=1 offer_install "$present" >/dev/null 2>&1 && rc=0 || rc=$?; assert "present->0" "$rc" "0"; else echo "skip present->0 (none present)"; fi
# A missing capability with AGENTBRAIN_ASSUME_NO declines -> exit 1, no install run.
AGENTBRAIN_ASSUME_NO=1 offer_install nope-cap >/dev/null 2>&1 && rc=0 || rc=$?; assert "decline->1" "$rc" "1"

# ── devtools slice: platform_flavor/id + cascaded capability arms ────────────
# platform_os stub: the arms branch on the OS at call time, so one mac tests
# both arms. A fake apt-get on PATH covers the linux jq arm.
flavor="$(platform_flavor)"
case "$flavor" in native|wsl) assert "flavor valid" yes yes;; *) assert "flavor valid" "$flavor" "native|wsl";; esac
case "$(platform_id)" in macos-*|linux-*|wsl-*) assert "id valid" yes yes;; *) assert "id valid" no yes;; esac

platform_os() { echo darwin; }
assert_contains() { case "$2" in *"$3"*) echo "ok   $1";; *) echo "FAIL $1 (missing '$3' in: $2)" >&2; fails=$((fails+1));; esac; }
cmd="$(capability_install_cmd jq)"
if [ -n "$cmd" ]; then assert "darwin jq recipe" yes yes; else assert "darwin jq recipe" no yes; fi
cmd="$(capability_install_cmd mailpit)"
assert_contains "darwin mailpit recipe" "$cmd" "brew install mailpit"
for t in ripgrep fd yq shellcheck wget fzf gh ffmpeg imagemagick git-lfs; do
	cmd="$(capability_install_cmd "$t")"
	assert_contains "darwin $t recipe" "$cmd" "brew install"
done

platform_os() { echo linux; }
FAKE="$(mktemp -d)"; printf '#!/bin/sh\necho fake-apt "$@"\n' > "$FAKE/apt-get"; chmod +x "$FAKE/apt-get"
PATH_SAVE="$PATH"; PATH="$FAKE:$PATH"
cmd="$(capability_install_cmd jq)"
assert_contains "linux jq recipe" "$cmd" "apt-get install -y jq"
cmd="$(capability_install_cmd mailpit)"
case "$cmd" in *axllent/mailpit*|*mailpit-linux-*) assert "linux mailpit recipe" yes yes;; *) assert "linux mailpit recipe" no yes;; esac
# linux arms for the remaining core tools (apt route via fake apt-get)
for t in ripgrep shellcheck wget fzf gh ffmpeg imagemagick git-lfs; do
	cmd="$(capability_install_cmd "$t")"
	assert_contains "linux $t recipe" "$cmd" "apt-get install -y"
done
cmd="$(capability_install_cmd yq)"
assert_contains "linux yq recipe" "$cmd" "yq_linux"
platform_os() { echo darwin; }
cmd="$(capability_install_cmd yt-dlp)"
assert_contains "darwin yt-dlp recipe" "$cmd" "brew install yt-dlp"
platform_os() { echo linux; }
cmd="$(capability_install_cmd yt-dlp)"
assert_contains "linux yt-dlp recipe" "$cmd" "yt-dlp/releases"
platform_os() { echo darwin; }
cmd="$(capability_install_cmd colima)"
assert_contains "darwin colima recipe" "$cmd" "brew install colima"
cmd="$(capability_install_cmd ttyd)"
assert_contains "darwin ttyd recipe" "$cmd" "brew install ttyd"
case " $(platform_capabilities) " in *" colima "*and*" ttyd "*|*colima*ttyd*) assert "container capabilities" yes yes;; *) assert "container capabilities" no yes;; esac

PATH="$PATH_SAVE"; rm -rf "$FAKE"
platform_has jq >/dev/null 2>&1; case " $(platform_capabilities) " in *" jq "*) assert "jq in capabilities" yes yes;; *) assert "jq in capabilities" no yes;; esac
case " $(platform_capabilities) " in *" mailpit "*) assert "mailpit in capabilities" yes yes;; *) assert "mailpit in capabilities" no yes;; esac

if [ "$fails" = 0 ]; then echo "test-capability-install: ok"; else echo "test-capability-install: $fails fail(s)" >&2; exit 1; fi
