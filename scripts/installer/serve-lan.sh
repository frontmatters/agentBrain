#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# serve-lan.sh — serve the engaging installer + a fresh git bundle on the LAN,
# so a second machine can install with:  curl -fsSL http://<this-ip>:7780/install.sh | bash
# Regenerates the bundle from the CURRENT main and injects LAN defaults into the
# served installer copy (repo copy stays generic).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${AB_PORT:-7780}"
SRV="/tmp/ab-dev-install"
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$IP" ] || { echo "no LAN IP found" >&2; exit 1; }
mkdir -p "$SRV"
git -C "$ROOT" bundle create "$SRV/agentBrain.bundle" main HEAD
{
  echo '#!/usr/bin/env bash'
  echo "export AB_BUNDLE=\"http://$IP:$PORT/agentBrain.bundle\""
  echo "export AB_VERSION=\"$(git -C "$ROOT" describe --tags --match 'v*' 2>/dev/null | sed 's/^v//')\""
  echo "export AB_REMOTE=\"\${AB_REMOTE:-$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)}\""
  tail -n +2 "$ROOT/scripts/installer/install.sh"
} > "$SRV/install.sh"
chmod +x "$SRV/install.sh"
lsof -ti tcp:"$PORT" 2>/dev/null | xargs kill 2>/dev/null || true
( cd "$SRV" && nohup python3 -m http.server "$PORT" --bind 0.0.0.0 >/dev/null 2>&1 & )
echo "serving: curl -fsSL http://$IP:$PORT/install.sh | bash"
