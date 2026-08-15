#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-session-update-quiet.sh — guard the session-start update-check contract.
#
# The session-start hook injects brain-update's STDOUT into the agent context. So a
# progress line printed to stdout — e.g. `info "fetching <remote> …"` — leaks the
# update remote's URL into the session. When that remote is a private/LAN `origin`
# (as on any Gitea-cloned checkout), the URL is exposed and, if unreachable, the
# check hangs on its fetch. Regression fixed 2026-08-14 (v1.10.0). This check makes
# a re-break fail the doctor BEFORE it ships.
#
# Two invariants:
#   1. Static  — brain-update's info()/progress must route to stderr, not stdout.
#   2. Runtime — `brain-update --session` against an UNREACHABLE origin must leak no
#      URL to stdout and must not hang (bounded budget).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BU="$ROOT_DIR/scripts/brain-update.sh"
fails=0

[ -f "$BU" ] || { echo "check-session-update-quiet: brain-update.sh missing" >&2; exit 1; }

# 1. Static invariant: the progress/info helper writes to stderr (>&2). A stdout
#    progress line is exactly what leaked the remote URL into the session.
if ! grep -qE '^info\(\).*>&2' "$BU"; then
	echo "check-session-update-quiet: FAIL — brain-update.sh info() must route to stderr (>&2);" >&2
	echo "  a stdout progress line leaks the (possibly private/LAN) remote URL into the session." >&2
	fails=$((fails + 1))
fi

# 2. Runtime invariant: a session check against an unreachable origin must produce
#    no URL on stdout and finish quickly. The host uses the reserved `.invalid` TLD
#    (RFC 2606) — guaranteed never to resolve, so no real/internal address appears
#    here and the fetch fails deterministically.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/local/update"
printf '{"auto_update":"notify","mode":"branch","channel":"prerelease","source":"http://agentbrain-update.invalid/unreachable.git"}' \
	> "$TMP/local/update/config.json"

start="$(date +%s)"
out="$(AGENTBRAIN_DIR="$TMP" bash "$BU" --session --repo "$ROOT_DIR" 2>/dev/null || true)"
elapsed="$(( $(date +%s) - start ))"

if printf '%s' "$out" | grep -qiE '://|http|\.invalid'; then
	echo "check-session-update-quiet: FAIL — session update-check leaked to stdout: $out" >&2
	fails=$((fails + 1))
fi
if [ "$elapsed" -gt 7 ]; then
	echo "check-session-update-quiet: FAIL — session check hung ${elapsed}s on an unreachable origin (fetch budget exceeded)" >&2
	fails=$((fails + 1))
fi

if [ "$fails" -eq 0 ]; then
	echo "check-session-update-quiet: ok"
else
	echo "check-session-update-quiet: $fails failure(s)" >&2
	exit 1
fi
