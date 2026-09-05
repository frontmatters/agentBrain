#!/usr/bin/env bash
# analyse.sh — machine report for the agentBrain installer-rollout verification.
# No install, no side effects: read-only diagnosis. Safe to run from any shell.
set -uo pipefail

os="unknown"; flavor="native"; arch="unknown"
case "$(uname -s 2>/dev/null)" in
	Darwin) os="darwin" ;;
	Linux)  os="linux" ;;
esac
case "$(uname -m 2>/dev/null)" in
	arm64|aarch64) arch="arm64" ;;
	x86_64|amd64)  arch="x86_64" ;;
esac
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
	flavor="wsl"
fi

echo "═══ machine ═══"
echo "  os:      $os"
echo "  arch:    $arch"
echo "  flavor:  $flavor"
echo "  id:      ${os}-${arch}${flavor:+-$flavor}"

echo ""
echo "═══ tools ═══"
for t in git python3 curl jq rg fd; do
	if command -v "$t" >/dev/null 2>&1; then
		echo "  ✓ $t ($(command -v $t))"
	else
		echo "  ✗ $t MISSING"
	fi
done

echo ""
echo "═══ WSL ═══"
if [ -n "${WSL_DISTRO_NAME:-}" ]; then
	echo "  ✓ WSL distro: ${WSL_DISTRO_NAME}"
	[ "$(cat /proc/sys/kernel/osrelease 2>/dev/null)" ] && echo "  kernel: $(uname -r)"
else
	echo "  (not WSL — native)"
fi

echo ""
echo "═══ agentBrain reachability ═══"
echo "  done. Paste this output back to the Mac."
