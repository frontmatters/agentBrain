---
date: 2026-05-18
type: system
tags: [sessions, session-continuity]
id: efbec1cd-4d5b-5b66-8c5b-2534e38ffbcc
---

# Sessions

Crash recovery and session continuity. Agent-agnostic — any agent reading `system/agent-config/shared.md` will maintain this automatically.

## Structure

```
local/sessions/
├── session-journal.md                      ← live journal (always current)
├── archive/
│   ├── 2026-05/
│   │   ├── 20260518-143205-a7f3.md
│   │   └── ...
│   └── 2026-04/
│       └── ...
└── README.md                               → symlink to system/sessions.md
```

## Flow

1. **Session start**: agent reads `session-journal.md`, archives it to `archive/YYYY-MM/YYYYMMDD-HHMMSS-<pid>.md`, starts fresh journal
2. **During session**: agent updates journal after each significant action
3. **Crash/restart**: new session reads journal → picks up where it left off

## Naming convention

- **File**: `YYYYMMDD-HHMMSS-<pid>.md`
- **PID**: 4 lowercase hex chars generated before writing the archive. Recommended command: `openssl rand -hex 2` (fallback: first 4 chars of `uuidgen` or another random/unique source).
- **UUID5**: full UUID in frontmatter `id` field, generated from the final archive path, including PID: `scripts/uuid5-gen.sh "local/sessions/archive/YYYY-MM/YYYYMMDD-HHMMSS-<pid>"`
- **Collision rule**: if the target archive file already exists, generate a new PID and try again. This handles multiple tabs/sessions starting in the same second.

## Rules

- Archive files are never deleted
- Monthly subfolders keep listings manageable (~50-150 files per month)
- All files use standard agentBrain frontmatter (`id`, `date`, `project`, `previous`)
- Wiki-links and UUID5 references remain intact permanently
- `previous` field links sessions into a chain for traceability
