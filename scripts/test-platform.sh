#!/usr/bin/env bash
# Tests voor platform.sh. Mockt uname via functie-override.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT_DIR" || exit 1
passed=0; failed=0; failures=()
assert() { if [ "$2" = "$3" ]; then passed=$((passed+1)); else failed=$((failed+1)); failures+=("$1: got '$2' want '$3'"); fi; }

source scripts/platform.sh

# macOS Apple Silicon
uname() { case "$1" in -s) echo Darwin;; -m) echo arm64;; esac; }
assert "macos os"   "$(platform_os)"   "darwin"
assert "macos arch" "$(platform_arch)" "arm64"
assert "macos id"   "$(platform_id)"   "macos-arm64"
# Linux aarch64 (Spark)
uname() { case "$1" in -s) echo Linux;; -m) echo aarch64;; esac; }
assert "linux-arm os"   "$(platform_os)"   "linux"
assert "linux-arm arch" "$(platform_arch)" "arm64"
assert "linux-arm id"   "$(platform_id)"   "linux-aarch64"
# Linux x86_64
uname() { case "$1" in -s) echo Linux;; -m) echo x86_64;; esac; }
assert "linux-x86 id" "$(platform_id)" "linux-x86_64"
unset -f uname

# --- capability-probes: PATH-shim ---
SHIM=$(mktemp -d); export PATH="$SHIM:$PATH"
mkok()  { printf '#!/bin/sh\nexit 0\n' > "$SHIM/$1"; chmod +x "$SHIM/$1"; }
mkfail(){ printf '#!/bin/sh\nexit 1\n' > "$SHIM/$1"; chmod +x "$SHIM/$1"; }

mkok node;        if platform_has node; then assert "node ok" yes yes; else assert "node ok" no yes; fi
mkok nvidia-smi;  if platform_has gpu;  then assert "gpu ok" yes yes;  else assert "gpu ok" no yes;  fi
rm -f "$SHIM/nvidia-smi"; mkfail nvidia-smi   # binary aanwezig maar exit 1 (geen GPU)
if platform_has gpu; then assert "gpu fail->absent" yes no; else assert "gpu fail->absent" no no; fi
rm -f "$SHIM/node" "$SHIM/nvidia-smi"
EMPTY=$(mktemp -d)   # lege PATH: robuust tegen een system-node (bv. via nvm) op de echte PATH
if PATH="$EMPTY" platform_has node; then assert "node absent" yes no; else assert "node absent" no no; fi
rmdir "$EMPTY"
rm -rf "$SHIM"

echo "passed=$passed failed=$failed"
for f in "${failures[@]:-}"; do [ -n "$f" ] && echo "FAIL: $f"; done
[ "$failed" -eq 0 ]
