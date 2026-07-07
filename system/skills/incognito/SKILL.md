---
name: incognito
description: Toggle agentBrain incognito mode — a read-only session where the brain can be consulted but nothing new is written (learnings, projects, troubleshoot, memories, journal all suppressed). Use when the user wants a throwaway/sensitive session, says "incognito", "read-only brain", "don't save anything this session", "niets opslaan", "alleen raadplegen", or wants to stop polluting the vault. Args - "on" / "off" / (none = status).
related: []
---

# incognito — read-only agentBrain sessions

Toggle a mode where reads work but every write path is suppressed. State is a
single flag file in the active vault (`local/sessions/.incognito`); write-side
hooks check it and no-op while it exists.

## Steps

1. Resolve the CLI: `~/agentBrain/system/addons/incognito/bin/incognito`.
2. Run it with the user's intent:
   - "on" / "aan" / "enable" → `incognito on`
   - "off" / "uit" / "disable" → `incognito off`
   - anything else / no arg → `incognito status`
   ```bash
   bash ~/agentBrain/system/addons/incognito/bin/incognito <on|off|status>
   ```
3. Relay the CLI output to the user.
4. **When you just turned it ON**, internalize it for the rest of this session:
   do NOT write learnings, projects, troubleshoot notes, memories, or run any
   save-* skill. Consulting the brain (brain_search/brain_read/brain_recent) stays
   fine. The PreToolUse guard and the MCP write tools hard-block stray Write/Edit/
   MultiEdit and brain_save_* calls, but Bash-based writes (e.g. new-note.sh) are
   NOT intercepted — so don't lean on the guards; don't propose any writes while
   incognito is on.
5. **When you just turned it OFF**, normal write behavior resumes.

## Notes

- The flag lives in the active vault, so it flips with `brain use dev|live`.
- To start a fresh session already incognito, the user can `touch
  ~/agentBrain/local/sessions/.incognito` before launching; the SessionStart hook
  then injects an incognito banner.
- Code edits (system/, scripts/, root) are never blocked — incognito only stops
  new knowledge.
