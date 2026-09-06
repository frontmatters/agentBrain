#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-abh-autostart.sh — optional user-level ABH Web startup at login/boot.
# Platform-aware: launchd on macOS, systemd --user on Linux/WSL.
set -euo pipefail

ACTION="${1:-status}"
LABEL="com.agentbrain.harness.web"
HOME_DIR="${AGENTBRAIN_HOME:-$HOME}"
STATE_DIR="${HOME_DIR}/.agentbrain"
LOG_DIR="${STATE_DIR}/logs"
PLIST="${HOME_DIR}/Library/LaunchAgents/${LABEL}.plist"
UNIT_DIR="${HOME_DIR}/.config/systemd/user"
UNIT="${UNIT_DIR}/agentbrain-harness-web.service"

usage() { echo "Usage: $0 enable|disable|status"; }
if ! command -v abh >/dev/null 2>&1; then
  if [ "$ACTION" = status ]; then echo "agentBrain Harness autostart: not installed (ABH missing)"; exit 0; fi
  echo "agentBrain Harness is not installed — install @agentbrain-harness/abh first" >&2
  exit 1
fi
ABH_BIN="$(command -v abh)"

mac_enable() {
  mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$ABH_BIN</string><string>web</string><string>--no-open</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>WorkingDirectory</key><string>$HOME_DIR</string>
  <key>StandardOutPath</key><string>$LOG_DIR/abh-web.out.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/abh-web.err.log</string>
</dict></plist>
EOF
  plutil -lint "$PLIST" >/dev/null
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "agentBrain Harness autostart enabled via launchd (starts at login)"
}

linux_enable() {
  # WSL: systemd is opt-in ([boot] systemd=true in /etc/wsl.conf). Without it
  # systemctl --user cannot work — say so instead of a raw systemctl error.
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd not available." >&2
    echo "WSL: enable it via /etc/wsl.conf ([boot] systemd=true), then 'wsl --shutdown' and reopen." >&2
    return 1
  fi
  mkdir -p "$UNIT_DIR" "$LOG_DIR"
  cat > "$UNIT" <<EOF
[Unit]
Description=agentBrain Harness Web
After=network-online.target

[Service]
ExecStart=$ABH_BIN web --no-open
WorkingDirectory=$HOME_DIR
Restart=on-failure
Environment=ABH_HOME=$HOME_DIR/.abh

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now agentbrain-harness-web.service
  echo "agentBrain Harness autostart enabled via systemd --user (starts at login)"
}

case "$(uname -s)" in
  Darwin) case "$ACTION" in enable) mac_enable ;; disable) launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; rm -f "$PLIST"; echo "agentBrain Harness autostart disabled" ;; status) launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 && echo "agentBrain Harness autostart: enabled" || echo "agentBrain Harness autostart: disabled" ;; *) usage; exit 2 ;; esac ;;
  Linux) case "$ACTION" in enable) linux_enable ;; disable) systemctl --user disable --now agentbrain-harness-web.service 2>/dev/null || true; rm -f "$UNIT"; echo "agentBrain Harness autostart disabled" ;; status) systemctl --user is-enabled agentbrain-harness-web.service 2>/dev/null || echo "agentBrain Harness autostart: disabled" ;; *) usage; exit 2 ;; esac ;;
  *) echo "Unsupported platform: $(uname -s)" >&2; exit 2 ;;
esac
