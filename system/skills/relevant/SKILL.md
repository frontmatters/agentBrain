---
name: relevant
description: Check whether open work is still needed, or already resolved in another parallel session. Use when the user asks "is this still needed?", "staat er nog iets open?", "did I already do this elsewhere?", or before acting on uncommitted changes, unpushed commits, parked projects, or backlog items. Runs the still-needed CLI and reads the verdicts back.
related: [list-parks, park]
argument-hint: optionally a scope — git | brain | a repo path
user-invocable: true
resources:
  - system/addons/still-needed/README.md
---

# Relevant — is this still needed?

The user works in many sessions at once. An open item here may already be
resolved elsewhere. This skill answers, per item, **is this still needed?**

## Steps

1. **Run the checker.** Prefer the installed CLI; fall back to the addon path.

   ```bash
   still-needed --json 2>/dev/null \
     || python3 ~/agentBrain/system/addons/still-needed/bin/still-needed --json
   ```

   - **Scope is automatic.** With no flag the CLI checks the git repo you are
     standing in (fast, relevant). It only falls back to scanning everything when
     you are not inside a repo. So a question asked *while working in a project*
     just works — no flag needed.
   - **Broaden when the user means "all my work"** ("staat er ergens nog iets
     open?", "over al mijn projecten"): add `--all` to sweep every repo under the
     configured roots. The JSON `scope` field tells you which mode ran.
   - Narrow further with `still-needed git`, `still-needed brain`, or
     `--repo <path>` when the user is explicit.
   - Add `--fetch` when the user works in separate clones/worktrees, or asks for a
     fresh check ("did another session just push this?"). Note it is slower.

2. **Read the verdicts back in plain language**, grouped by what the user should do:
   - **LIKELY RESOLVED** — already on origin via another session. Safe to discard:
     `git checkout -- <file>` for uncommitted, or drop the redundant local commit.
     Name the exact file/commit and the discard command.
   - **REVIEW** — behind origin (pull first) or a stale parked/backlog item
     (confirm it is not already done). Say what to verify.
   - **STILL NEEDED** — real open work. List it briefly; do not nag.

3. **Never auto-discard.** Report and recommend; the user (or an explicit
   follow-up instruction) decides. Treat LIKELY RESOLVED as high-confidence only
   when the run used `--fetch` or you have confirmed all sessions share one clone.

4. **End with the one-line tally** the CLI prints (`N likely resolved · M to review`)
   so the user gets the headline even if the list is long.

## Notes

- The CLI never reads or reports `.env*` files, and filters build/OS noise.
- It is a report, not a gate: it always exits 0.
- If nothing is open, say so plainly ("niets open dat al elders is opgelost").
