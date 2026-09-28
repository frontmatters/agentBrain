#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# session-banner.sh — agent-neutral incognito session banner.
# When a session STARTS already incognito (the flag is present before launch),
# print a banner to stdout announcing the vault is read-only this session.
# Reads still work; writes are suppressed.
#
# Agent-neutral by design: it only emits plain text. Each agent wires it into its
# own session-start mechanism and decides what to do with stdout:
#   - Claude Code: hooks.SessionStart in ~/.claude/settings.json (stdout → context)
#   - Pi / Copilot / Gemini: call from their own session-start entry point
# Nothing here is specific to any one agent (unlike claude-pretooluse-guard.sh,
# which parses a Claude PreToolUse payload).
#
# Fail-safe: a session-start step must NEVER block a session. Errors are swallowed;
# it always exits 0.
set +e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || exit 0

if bash "$HERE/is-incognito.sh" 2>/dev/null; then
	cat <<'EOF'
🔒 agentBrain INCOGNITO — this session is read-only.
   reads  : brain_search / brain_read / brain_recent  → work normally
   writes : learnings, projects, troubleshoot, memories, journal  → suppressed
   Do not try to persist knowledge this session. To enable writes: /incognito off
EOF
fi

exit 0
