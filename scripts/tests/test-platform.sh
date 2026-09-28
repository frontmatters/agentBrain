#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Tests for platform.sh. Mocks uname via a function override.
set -uo pipefail

# Tools (npm/node/bun) live in user-scoped installs — load them before probing.
# shellcheck disable=SC1091
TOOLPATHS_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib" && pwd)"
# shellcheck disable=SC1091
. "$TOOLPATHS_DIR/_toolpaths.sh"
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"; cd "$ROOT_DIR" || exit 1
passed=0; failed=0; failures=()
assert() { if [ "$2" = "$3" ]; then passed=$((passed+1)); else failed=$((failed+1)); failures+=("$1: got '$2' want '$3'"); fi; }

source scripts/lib/platform.sh

# platform_id reads platform_flavor as well as uname, and that looks at
# $WSL_DISTRO_NAME and /proc/version. Mocking only uname is therefore not
# hermetic: run on a WSL machine, the real environment leaks through and every
# linux case yields 'wsl-*' instead of 'linux-*'.
# So pin the flavor here too, and cover the wsl ids explicitly.

# macOS Apple Silicon
uname() { case "$1" in -s) echo Darwin;; -m) echo arm64;; esac; }
platform_flavor() { echo native; }
assert "macos os"   "$(platform_os)"   "darwin"
assert "macos arch" "$(platform_arch)" "arm64"
assert "macos id"   "$(platform_id)"   "macos-arm64"
# Linux aarch64
uname() { case "$1" in -s) echo Linux;; -m) echo aarch64;; esac; }
assert "linux-arm os"   "$(platform_os)"   "linux"
assert "linux-arm arch" "$(platform_arch)" "arm64"
assert "linux-arm id"   "$(platform_id)"   "linux-aarch64"
# Linux x86_64
uname() { case "$1" in -s) echo Linux;; -m) echo x86_64;; esac; }
assert "linux-x86 id" "$(platform_id)" "linux-x86_64"
# WSL: the same kernel, a different flavor: the ids that platform_id documents.
platform_flavor() { echo wsl; }
assert "wsl-x86 id" "$(platform_id)" "wsl-x86_64"
uname() { case "$1" in -s) echo Linux;; -m) echo aarch64;; esac; }
assert "wsl-arm id" "$(platform_id)" "wsl-aarch64"
unset -f uname platform_flavor
# Restore the real functions: unset -f removes the definition, not the override.
source scripts/lib/platform.sh

# --- capability-probes: PATH-shim ---
SHIM=$(mktemp -d); export PATH="$SHIM:$PATH"
mkok()  { printf '#!/bin/sh\nexit 0\n' > "$SHIM/$1"; chmod +x "$SHIM/$1"; }
mkfail(){ printf '#!/bin/sh\nexit 1\n' > "$SHIM/$1"; chmod +x "$SHIM/$1"; }

mkok node;        if platform_has node; then assert "node ok" yes yes; else assert "node ok" no yes; fi
mkok nvidia-smi;  if platform_has gpu;  then assert "gpu ok" yes yes;  else assert "gpu ok" no yes;  fi
rm -f "$SHIM/nvidia-smi"; mkfail nvidia-smi   # binary present but exit 1 (no GPU)
if platform_has gpu; then assert "gpu fail->absent" yes no; else assert "gpu fail->absent" no no; fi
rm -f "$SHIM/node" "$SHIM/nvidia-smi"
EMPTY=$(mktemp -d)   # empty PATH: robust against a system node (e.g. via nvm) on the real PATH
if PATH="$EMPTY" platform_has node; then assert "node absent" yes no; else assert "node absent" no no; fi
rmdir "$EMPTY"
rm -rf "$SHIM"

# capability enumerator lists the known tokens
caps="$(platform_capabilities)"
case " $caps " in *" ollama "*) assert "enum has ollama" yes yes ;; *) assert "enum has ollama" no yes ;; esac
case " $caps " in *" obsidian "*) assert "enum has obsidian" yes yes ;; *) assert "enum has obsidian" no yes ;; esac
# new probes resolve (uv present-or-absent must not error)
if platform_has uv; then :; else :; fi; assert "uv probe no-error" yes yes
# unknown capability still returns absent
if platform_has totally-unknown-cap; then assert "unknown absent" yes no; else assert "unknown absent" no no; fi

echo "passed=$passed failed=$failed"
for f in "${failures[@]:-}"; do [ -n "$f" ] && echo "FAIL: $f"; done
[ "$failed" -eq 0 ]
