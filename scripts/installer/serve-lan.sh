#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# serve-lan.sh — serve the engaging installer + a git bundle on the LAN,
# so a second machine can install with:  curl -fsSL http://<this-ip>:7780/install.sh | bash
#
# The bundle is rebuilt when main has moved, checked per request. Built once at
# startup, a long-running server quietly serves an older and older tree, and a
# server that tells you nothing while it drifts is the failure mode worth
# designing out.
#
# Rebuilds write to a temporary path and are renamed into place, so a client
# downloading during a rebuild never sees a half-written bundle.
set -euo pipefail

# --daemon:     rebuild, then EXEC the server in the foreground, for the launchd
#               job (launchd reaps nohup children on job exit; exec = the server IS the job).
# --build-only: regenerate the served files and exit. The request handler calls
#               this, so the build lives in exactly one place.
MODE="${1:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${AB_PORT:-7780}"
SRV="/tmp/ab-dev-install"
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$IP" ] || { echo "no LAN IP found" >&2; exit 1; }
mkdir -p "$SRV"

build() {
	local tmp_b tmp_i
	tmp_b="$SRV/.bundle.$$"
	tmp_i="$SRV/.install.$$"
	# --tags: without the tags the clone has no anchor and `git describe` returns
	# only a bare hash. An edge install must be able to say which release it is
	# past and by how far.
	git -C "$ROOT" bundle create "$tmp_b" --tags main HEAD >/dev/null 2>&1
	{
		echo '#!/usr/bin/env bash'
		echo "export AB_BUNDLE=\"http://$IP:$PORT/agentBrain.bundle\""
		# Describe MAIN, not HEAD: the bundle ships main; a shared checkout may sit
		# on another session's branch and would lie in the banner otherwise.
		echo "export AB_VERSION=\"$(git -C "$ROOT" describe --tags --match 'v*' main 2>/dev/null | sed 's/^v//')\""
		# The LAN install context may not reach this checkout's origin: the
		# reachable remote IS this machine, the git daemon on the LAN IP.
		echo "export AB_REMOTE=\"\${AB_REMOTE:-git://$IP/$(basename "$ROOT")}\""
		tail -n +2 "$ROOT/scripts/installer/install.sh"
	} > "$tmp_i"
	chmod +x "$tmp_i"
	# Atomic within the same filesystem: a client mid-download keeps its open
	# handle on the old inode and finishes reading a consistent file.
	mv -f "$tmp_b" "$SRV/agentBrain.bundle"
	mv -f "$tmp_i" "$SRV/install.sh"
	git -C "$ROOT" rev-parse main > "$SRV/.built-from"
}

if [ "$MODE" = "--build-only" ]; then
	build
	exit 0
fi

build

HANDLER="$ROOT/scripts/installer/serve-lan-handler.py"
if [ "$MODE" = "--daemon" ]; then
	exec python3 "$HANDLER" "$SRV" "$PORT" "$ROOT" "${BASH_SOURCE[0]}"
fi
lsof -ti tcp:"$PORT" 2>/dev/null | xargs kill 2>/dev/null || true
nohup python3 "$HANDLER" "$SRV" "$PORT" "$ROOT" "${BASH_SOURCE[0]}" >/dev/null 2>&1 &
echo "serving: curl -fsSL http://$IP:$PORT/install.sh | bash"
