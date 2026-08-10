#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# sandbox.sh — a disposable install-testbed in your browser (REAL, not a mock).
#
# Serves a real terminal (ttyd/xterm.js) where every connection spawns a fresh
# non-root Debian container: open the page, paste the install curl, walk the
# real installer + wizard as a human would on a brand-new machine. Refresh (or
# the wrapper's reset button) = a brand-new machine; --rm removes the old one.
#
# Composes with serve-lan.sh: run that first so the container's motd can point
# at your LAN installer. Found its first real bug within minutes of existing
# (npm missing on fresh Linux), which is exactly the job of this tool.
#
# Every session is RECORDED (util-linux `script` inside the container) into
# local/logs/sandbox/ — private, never shipped. That closes the self-improvement
# loop: an agent reads where a human stumbled (errors, retries, abandoned
# steps) and turns it into findings/fixes. `sandbox.sh logs` lists them.
#
# Usage:
#   sandbox.sh [start]      build image (idempotent) + start terminal & wrapper
#   sandbox.sh stop         stop terminal & wrapper
#   sandbox.sh status       what is running, with URLs
#   sandbox.sh logs         list recorded sessions (newest first)
#
# Env:
#   AB_SANDBOX_PORT   ttyd port            (default 7681)
#   AB_WRAPPER_PORT   wrapper-page port    (default 7682)
#   AB_BASE_IMAGE     container base image (default debian:bookworm)
#   AB_SANDBOX_AUTH   optional user:pass — basic-auth gate on the terminal
#                     (dropeye-style passphrase gate for less-trusted networks)
#
# Needs: docker (e.g. colima) and ttyd (macOS: brew install ttyd · Debian/Ubuntu: apt install ttyd).
set -euo pipefail

PORT="${AB_SANDBOX_PORT:-7681}"
WPORT="${AB_WRAPPER_PORT:-7682}"
BASE="${AB_BASE_IMAGE:-debian:bookworm}"
IMAGE="brain-sandbox"
SRV="/tmp/ab-sandbox"
INSTALLER_PORT=7780
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOGDIR="$VAULT/local/logs/sandbox"

c() { printf '\033[%sm' "$1"; }
info() { printf '%s·%s %s\n' "$(c 2)" "$(c 0)" "$*"; }
ok()   { printf '%s✓%s %s\n' "$(c '1;32')" "$(c 0)" "$*"; }
die()  { printf '%s✗%s %s\n' "$(c '1;31')" "$(c 0)" "$*" >&2; exit 1; }

lan_ip() { ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'; }
ts_ip() {
  command -v tailscale >/dev/null 2>&1 && { tailscale ip -4 2>/dev/null | head -1; return; }
  ifconfig 2>/dev/null | awk '/inet 100\./{print $2; exit}'
}

kill_port() { lsof -ti tcp:"$1" 2>/dev/null | xargs kill 2>/dev/null || true; }

status() {
  local ip; ip="$(lan_ip)"
  if curl -fsS -o /dev/null "http://localhost:$PORT/" 2>/dev/null; then
    ok "terminal : http://localhost:$PORT/  (every connection = a fresh container)"
  else
    info "terminal : not running"
  fi
  if curl -fsS -o /dev/null "http://localhost:$WPORT/" 2>/dev/null; then
    ok "wrapper  : http://localhost:$WPORT/  (reset button + machine counter)"
    [ -n "$ip" ] && info "           http://$ip:$WPORT/  (LAN)"
    local tsip; tsip="$(ts_ip)"
    [ -n "$tsip" ] && info "           http://$tsip:$WPORT/  (tailnet)"
  else
    info "wrapper  : not running"
  fi
  if curl -fsS -o /dev/null "http://$ip:$INSTALLER_PORT/install.sh" 2>/dev/null; then
    ok "installer: http://$ip:$INSTALLER_PORT/install.sh (serve-lan.sh)"
  else
    info "installer: not serving — run: bash scripts/installer/serve-lan.sh"
  fi
  # Dropeye-style QR access: scan from a phone/tablet on the same network.
  if command -v qrencode >/dev/null 2>&1 && [ -n "$ip" ] && curl -fsS -o /dev/null "http://localhost:$WPORT/" 2>/dev/null; then
    echo ""
    qrencode -t ANSIUTF8 -m 1 "http://$ip:$WPORT/"
    info "scan to open the sandbox on a phone/tablet (same network)"
  fi
}

stop() {
  kill_port "$PORT"
  kill_port "$WPORT"
  ok "sandbox stopped (ports $PORT + $WPORT freed; containers with --rm clean themselves up)"
}

start() {
  command -v docker >/dev/null 2>&1 || die "docker not found — start colima (or Docker) first"
  docker ps >/dev/null 2>&1 || die "docker daemon unreachable — is colima running?"
  command -v ttyd >/dev/null 2>&1 || die "ttyd not found — install with: brew install ttyd"

  local ip; ip="$(lan_ip)"
  [ -n "$ip" ] || die "no LAN IP found"
  local curl_line="curl -fsSL http://$ip:$INSTALLER_PORT/install.sh | bash"

  info "building $IMAGE (base: $BASE) …"
  docker build -q -t "$IMAGE" - >/dev/null <<DOCKER
FROM $BASE
RUN apt-get update -qq && apt-get install -y -qq git python3 curl jq rsync procps ca-certificates nano less sudo && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash demo && echo "demo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/demo
USER demo
WORKDIR /home/demo
RUN git config --global user.name "Demo User" && git config --global user.email "demo@example.com"
RUN echo 'echo; echo "  Fresh machine (user: demo, passwordless sudo). Install agentBrain with:"; echo; echo "  $curl_line"; echo' >> /home/demo/.bashrc
CMD ["bash"]
DOCKER

  kill_port "$PORT"
  mkdir -p "$LOGDIR"
  # Record each session with `script` INSIDE the container (bind-mounted to the
  # private log dir); the timestamp resolves at connect time, one file per
  # fresh machine. Agents mine these for stumbles — the self-improvement loop.
  auth_args=()
  [ -n "${AB_SANDBOX_AUTH:-}" ] && auth_args=(-c "$AB_SANDBOX_AUTH")
  # shellcheck disable=SC2016  # $(date)/$$ must expand INSIDE the container, per connection
  nohup ttyd -p "$PORT" --writable "${auth_args[@]}" -t fontSize=14 \
    -t 'theme={"background":"#1d1f24","foreground":"#e8e9ec"}' \
    docker run --rm -it -v "$LOGDIR:/var/log/sandbox" "$IMAGE" \
    bash -c 'exec script -q -f "/var/log/sandbox/$(date +%Y%m%d-%H%M%S)-$$.typescript" -c bash' \
    >"$SRV-ttyd.log" 2>&1 &
  sleep 1
  curl -fsS -o /dev/null "http://localhost:$PORT/" || die "ttyd did not come up (log: $SRV-ttyd.log)"
  # macOS firewall blocks a NEW binary's incoming connections silently: local
  # curls pass, remote clients see a header without a terminal. Say it here.
  if [ "$(uname)" = "Darwin" ] && /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
    info "macOS firewall is on — if REMOTE clients see no terminal, allow ttyd once:"
    info "  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add \"\$(command -v ttyd)\" --unblockapp \"\$(command -v ttyd)\""
  fi

  mkdir -p "$SRV"
  sed -e "s/__PORT__/$PORT/g" >"$SRV/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>agentBrain sandbox — fresh machine in your browser</title>
<link rel="preconnect" href="https://api.fontshare.com" />
<link rel="preconnect" href="https://cdn.fontshare.com" crossorigin />
<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700&display=swap" rel="stylesheet" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet" />
<style>
  /* Tokens mirror the getagentbrain.com landing page (oklch + Satoshi/JetBrains Mono). */
  :root {
    --bg: oklch(0.18 0.006 260); --panel: oklch(0.215 0.007 260);
    --border: oklch(0.34 0.008 260); --fg: oklch(0.96 0.004 260);
    --fg-muted: oklch(0.74 0.008 260); --accent: oklch(0.86 0.20 128);
    --font-sans: "Satoshi", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    --font-mono: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
  }
  @media (prefers-color-scheme: light) {
    :root { --bg: oklch(0.962 0.009 92); --panel: oklch(0.94 0.011 90);
            --border: oklch(0.86 0.011 88); --fg: oklch(0.25 0.013 78);
            --fg-muted: oklch(0.45 0.012 80); --accent: oklch(0.49 0.14 134); } }
  * { box-sizing:border-box; }
  html, body { height:100%; }
  body { margin:0; background:var(--bg); color:var(--fg); display:flex;
         flex-direction:column; font:14px/1.5 var(--font-sans);
         height:100vh; height:100dvh; /* iOS Safari: dvh volgt de zichtbare hoogte */ }
  header { display:flex; align-items:center; gap:14px; padding:10px 18px;
           border-bottom:1px solid var(--border); background:var(--panel); }
  .brand { display:flex; align-items:center; gap:8px; font-weight:700;
           letter-spacing:-0.02em; font-size:16px; }
  .brand .mark { width:24px; height:24px; flex:none; display:block; }
  .brand .tag { font-weight:500; color:var(--fg-muted); }
  .d { color:var(--fg-muted); font-size:12.5px; flex:1; }
  .btn { background:none; border:1px solid var(--border); color:var(--fg);
         font:500 13px/1 var(--font-sans); padding:7px 16px; border-radius:6px; cursor:pointer; }
  .btn:hover { border-color:var(--accent); color:var(--accent); }
  .state { font:11.5px/1 var(--font-mono); color:var(--fg-muted); min-width:150px; text-align:right; }
  .state.fresh { color:var(--accent); }
  iframe { flex:1 1 auto; min-height:0; border:0; width:100%; height:100%;
           background:#1d1f24; }
  @media (max-width: 700px) {
    header { gap:10px; padding:8px 12px; }
    .d { display:none; }
    .brand { flex:1; }
    .state { min-width:0; }
  }
  @media (max-width: 420px) {
    .state { display:none; }
    .btn { padding:7px 12px; }
  }
</style>
</head>
<body>
<header>
  <span class="brand">
    <canvas id="brandCanvas" class="mark" aria-hidden="true"></canvas>
    <span>agentBrain</span> <span class="tag">sandbox</span>
  </span>
  <span class="d">fresh disposable machine (user: demo) · reset = brand-new container · install with the curl command shown in the terminal</span>
  <span class="state" id="state"></span>
  <button class="btn" id="reset">reset machine</button>
</header>
<iframe id="term" src="" allow="clipboard-read; clipboard-write"></iframe>
<script>
"use strict";
let n = 0, since = null;
const state = document.getElementById("state");
const term = document.getElementById("term");
function stamp() {
  if (!since) return;
  const s = Math.floor((performance.now() - since) / 1000);
  state.textContent = "machine #" + n + " · " + s + "s old";
  state.classList.toggle("fresh", s < 5);
}
function reset() {
  n += 1; since = performance.now();
  term.src = "http://" + location.hostname + ":__PORT__/?fresh=" + n;
  stamp();
}
document.getElementById("reset").addEventListener("click", reset);
setInterval(stamp, 1000);
reset();

// Neural logo — ported from the getagentbrain.com landing page.
(function initNeuralLogo() {
  var cv = document.getElementById("brandCanvas");
  if (!cv) return;
  var ctx = cv.getContext("2d");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var lightMq = window.matchMedia("(prefers-color-scheme: light)");
  var SIZE = 24;
  function setSize() {
    var d = Math.min(window.devicePixelRatio || 1, 2);
    cv.width = SIZE * d; cv.height = SIZE * d;
    cv.style.width = SIZE + "px"; cv.style.height = SIZE + "px";
    ctx.setTransform(d, 0, 0, d, 0, 0);
  }
  setSize();
  var N = [
    [0, 0, 0],
    [0.95, 0.25, 0.15], [-0.85, 0.35, -0.25], [0.20, 0.92, -0.35],
    [-0.25, -0.85, 0.30], [0.55, -0.55, -0.65], [-0.60, -0.15, 0.80],
    [0.72, 0.55, -0.50], [-0.50, 0.70, 0.55], [0.10, -0.45, 0.85]
  ];
  var E = [];
  for (var i = 1; i < N.length; i++) E.push([0, i]);
  E.push([1, 7], [7, 3], [3, 8], [8, 2], [2, 6], [6, 9], [9, 5], [5, 1], [4, 9], [4, 5]);
  function color() { return lightMq.matches ? "#4d7c0f" : "#bef264"; }
  var ang = 0.6, raf = null;
  function frame() {
    raf = null;
    if (!reduce) ang += 0.005;
    var col = color(), cx = SIZE / 2, cy = SIZE / 2, R = SIZE * 0.32, f = 3.2;
    var ca = Math.cos(ang), sa = Math.sin(ang), P = [];
    for (var i = 0; i < N.length; i++) {
      var x = N[i][0], y = N[i][1], z = N[i][2];
      var xr = x * ca + z * sa, zr = -x * sa + z * ca;
      var sc = f / (f - zr);
      P.push([cx + xr * R * sc, cy + y * R * sc, zr, sc]);
    }
    ctx.clearRect(0, 0, SIZE, SIZE);
    ctx.lineCap = "round"; ctx.strokeStyle = col;
    for (var e = 0; e < E.length; e++) {
      var a = P[E[e][0]], b = P[E[e][1]], depth = (a[2] + b[2]) / 2;
      ctx.globalAlpha = 0.22 + 0.33 * ((depth + 1) / 2);
      ctx.lineWidth = 0.85 * ((a[3] + b[3]) / 2);
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
    }
    var order = P.map(function (_, i) { return i; }).sort(function (i, j) { return P[i][2] - P[j][2]; });
    ctx.fillStyle = col;
    for (var k = 0; k < order.length; k++) {
      var pt = P[order[k]];
      ctx.globalAlpha = 0.5 + 0.5 * ((pt[2] + 1) / 2);
      var r = (order[k] === 0 ? 2.1 : 1.5) * pt[3];
      ctx.beginPath(); ctx.arc(pt[0], pt[1], r, 0, 6.283); ctx.fill();
    }
    ctx.globalAlpha = 1;
    if (!reduce) raf = requestAnimationFrame(frame);
  }
  window.addEventListener("resize", function () { setSize(); if (!raf) frame(); });
  lightMq.addEventListener("change", function () { if (!raf) frame(); });
  frame();
})();
</script>
</body>
</html>
HTML

  kill_port "$WPORT"
  ( cd "$SRV" && nohup python3 -m http.server "$WPORT" --bind 0.0.0.0 >/dev/null 2>&1 & )
  sleep 1
  echo ""
  status
}

logs() {
  if [ ! -d "$LOGDIR" ] || [ -z "$(ls -A "$LOGDIR" 2>/dev/null)" ]; then
    info "no recorded sessions yet ($LOGDIR)"
    return 0
  fi
  info "recorded sessions in $LOGDIR (newest first):"
  # shellcheck disable=SC2012  # filenames are our own timestamps; ls -t ordering is the point
  ls -lt "$LOGDIR" | awk 'NR>1 {printf "  %s  %6s bytes\n", $NF, $5}' | head -15
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  logs) logs ;;
  -h|--help|help) sed -n '3,29p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command '${1}' — start | stop | status | logs" ;;
esac
