---
name: brain-hide
description: >-
  Hide an agentBrain note from listings without deleting it. Adds `hidden: true` + `hidden-at` to frontmatter. Use when a learning, project, or preference no longer needs to clutter /list-* output but you want to keep it around. Triggers — "hide this note", "verstop", "uit zicht halen", "remove from listings".
---

# brain-hide — set hidden flag on a note

Counterpart to [[brain-unhide]]. Adds a `hidden: true` flag to a note's frontmatter so that `/list-parks`, `/list-learnings`, `/list-projects` skip it. Bestand blijft op zijn plek.

## When to use

- A learning, project, or preference is no longer relevant for daily listings.
- You want to keep a note for archival but stop seeing it.
- You're about to bulk-clean listings and want to selectively suppress items.

## Do not use for

- Permanent deletion — use `/brain-forget` (soft-delete via .trash).
- Privacy / secrets — `hidden:` flag is NOT a privacy mechanism. `grep` and `brain_search` MCP still find content. For true privacy: V2 `brain-conceal` (planned).
- System framework files — `system/**` is refused (validate_target fail-closed).
- Auto-generated content — `local/sessions/**`, `local/daily-notes/**` refused.

## Invocation

```
/brain-hide <type>/<slug> [--file <name>]
```

Type is one of: `learnings`, `projects`, `preferences`, `integrations`, `troubleshooting`, `memories`.

For `projects/<slug>` without `--file`: targets `index.md`. Other files in that project folder cascade as hidden via `is_hidden()` in `system/lib/visibility.sh`.

For `projects/<slug> --file <name>`: targets only that specific file inside the project.

## Cross-machine note

`brain-hide` mutates frontmatter, which syncs via gitea. Hidden status propagates across machines automatically. Compare with `brain-forget`, which is local-only (`.trash/` is gitignored).

## Anti-patterns

- **Hiding to "delete"**: hidden notes still exist on disk and in git history. Use `brain-forget` for soft-delete.
- **Hiding as privacy**: see "Do not use for".
- **Bulk-hiding via shell loop**: works but easy to over-hide.

## Related

- [[brain-unhide]] — reverse this operation
- [[brain-forget]] — soft-delete via .trash
- [[list-hidden]] — see what is hidden
- [[forward:brain-hide-forget]] — design spec
