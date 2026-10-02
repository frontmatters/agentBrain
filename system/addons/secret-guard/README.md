---
date: 2026-10-01
type: system
tags: [addon, security, secret-guard]
id: f4d9e47b-282f-51b3-a824-0d341c013299
---

# Secret Guard

Opt-in protection before a Claude Code or Pi tool executes. Scans **every string
value in the entire tool input**, including nested fields, regardless of tool name.
Claude's hook uses matcher `*`; Pi's `secret-guard.ts` uses `tool_call`. Both
use the same Python scanner. A match blocks with a short **kind-only** reason;
no input fragment is echoed to stderr.

Detects `token` + 40 hex, Authorization Bearer/Basic values, `curl -u`
credentials, HTTPS URL userinfo passwords and long `password=` / `token=` URL
query values; also secret-named literal assignments (`TOKEN`, `SECRET`,
`PASSWORD`, `PASSWD`, `API_KEY`, `APIKEY`), GitHub classic and fine-grained
tokens, Anthropic/OpenAI keys, Slack tokens, AWS access keys and private-key
headers. Deliberately allows variable references (`$TOKEN`, `${X}`, `$(secrets get ...)`), placeholders,
identifier-like letter/underscore assignments, short letter-only identifiers,
the URL password placeholder `password`, ordinary prose about passwords, and
bare 40-hex git commit IDs. A URL userinfo password is detected from 8 literal
characters; a long, varied letter-only secret assignment is still blocked.
Narrow patterns
mean other formats can pass: this is defense-in-depth, **not** a DLP guarantee.

## Installation

**Only with the owner's approval:** `bash system/addons/secret-guard/install.sh`
registers the Claude PreToolUse hook in `~/.claude/settings.json` (creating or
merging it, idempotently). It does not install into Pi automatically; link
`system/pi-config/extensions/secret-guard.ts` through the normal Pi extension
setup after removing `secret-guard.ts` from `system/pi-config/extensions/.pi-ignore`
(with owner approval). `bash system/addons/secret-guard/uninstall.sh` removes only its own
Claude hook. To disable Pi, remove the `secret-guard.ts` symlink from the Pi
extensions directory, restore its `.pi-ignore` entry, and restart Pi. Pi fails
closed: if `python3` or the scanner script is unavailable, it blocks every
tool call with a generic reason. Nothing changes the real agent installation
just by cloning this addon.

The hook sees the input before **execution**, but the agent harness may already
have recorded the proposed tool call in its session transcript. It cannot
redact previous transcripts, tool outputs or secrets with unknown shapes.

Tests: `python3 system/addons/secret-guard/tests/test-secret-guard.py` and
`node --test` via the existing Pi extension test runner (secret-guard.test.ts).
