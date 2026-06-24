---
name: brain-purge
description: PERMANENTLY delete forget-batches from agentBrain's trash (local/.trash/forget/). Always previews + validates first; deletion requires explicit user confirmation — never skippable. Counterpart that makes /brain-forget final. Triggers — "purge", "echt verwijderen", "definitief weg", "leeg de trash", "empty trash".
---

# brain-purge — permanent delete from trash

Makes a [[brain-forget]] final: removes a trash batch from `local/.trash/forget/<timestamp>/` **permanently**. After purge, `/brain-recall` can no longer restore it.

## When to use

- A forgotten note must be truly gone from disk (not just out of listings/grep).
- Periodic trash cleanup of batches you are certain about.

## Do not use for

- Anything you might want back — there is NO undo. Use [[brain-forget]] (recoverable) if unsure.
- Git history — purge only removes the trash copies. If the note was ever committed, its content persists in the vault's git history (purge tells you when this applies).
- Live notes — purge operates on trash batches only. Forget first, then purge.

## Invocation

```
/brain-purge <batch-id>          # preview only — validates, shows manifest + files
/brain-purge all                 # preview of every batch in the trash
/brain-purge <batch-id> --confirm <batch-id>   # PERMANENT delete
/brain-purge all --confirm ALL                 # PERMANENT delete of all batches
```

Batch-ids are the `/brain-recall` timestamps (`YYYYMMDD-HHMMSS`).

## MANDATORY agent protocol (never skip)

1. Run the **preview** (no `--confirm`) and show the user what would be deleted: manifest (reason, original paths, date), file list, and the git-history caveat.
2. Ask the user for **explicit confirmation** (e.g. AskUserQuestion). A general instruction like "clean up" is NOT confirmation for a specific batch.
3. Only after the user confirms: rerun with `--confirm <batch-id>`.

The script enforces this structurally: without `--confirm` it never deletes, and the confirm value must restate the batch-id exactly. There is deliberately no `--force`.

## Related

- [[brain-forget]] — soft-delete (the step before purge)
- [[brain-recall]] — restore from trash (impossible after purge)
- [[list-hidden]] — dashboard of hidden + forgotten notes
- [[forward:brain-hide-forget]] — design spec
