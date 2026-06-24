---
name: brain-review
description: Review agentBrain for outdated notes, missing info, and quality. Use periodically (monthly) or when the knowledge base needs maintenance.
argument-hint: Optional focus area (e.g. "Learnings" or "Projects")
user-invocable: true
resources:
  - system/rules.md
  - learnings/patterns.md
  - learnings/troubleshooting.md
---

# Brain Review

Periodic review of agentBrain to keep the knowledge base healthy.

## Automated checks

Run the automated quality check first:

```bash
bash scripts/check-brain-review.sh
```

This checks:

- Missing frontmatter fields
- Stale notes (>6 months without update)
- Low confidence entries older than 3 months
- Retracted entries older than 3 months (safe to remove)
- Very short/placeholder content
- Active projects with no updates for >6 months
- Orphaned projects not in index.md
- Duplicate headings across notes
- Public/private misclassification (private IPs, tokens in public notes)

## Manual review

After automated checks, do a deeper manual review:

## Steps

1. **Inventory all files:**
   - Read all files in `learnings/` and `projects/`
   - Note the number of files, last update dates, and confidence levels

2. **Check staleness:**
   - Notes older than 6 months without updates -> flag for review
   - Technology-related notes -> check if the tool/library version is still current
   - `confidence: low` entries -> have they been confirmed 2x+ since? Update to `high`
   - Treat note staleness as age + manual review unless local usage telemetry exists

3. **Check recoverable curation:**
   - Identify duplicate or overlapping notes that can be consolidated
   - Respect explicit keep/pin markers
   - Prefer archive or consolidation over deletion
   - Produce a dry-run/report before mutating files
   - Keep private archives under `local/` when they contain real knowledge

4. **Check quality per note:**
   - Does it have frontmatter with all required fields?
     - Learning: `date`, `type`, `tags`, `confidence`, `source`
     - Project: `date`, `type`, `tags`, `status`, `priority`
   - Is it actionable? (not just "interesting")
   - Is it concise? (no unnecessary text)
   - Does it have a `## Related` section with relevant links?

5. **Check patterns:**
   - Are there entries in `troubleshooting.md` that are actually patterns? -> move to `patterns.md`
   - Are there `confidence: retracted` entries that can be archived or removed after review?
   - Are there duplicate entries?

6. **Check projects:**
   - Are `status: active` projects still active?
   - Are completed projects set to `status: done`?
   - Are there projects that exist but have no note?

7. **Report:**
   - Number of notes per category
   - Outdated notes (older than 6 months)
   - Missing frontmatter
   - Consolidation/archive candidates
   - Recommendations for cleanup
   - Apply fixes only after confirmation when they move, archive, or delete content

## References

- Rules: `system/rules.md`
- Patterns: `learnings/patterns.md`
- Troubleshooting: `learnings/troubleshooting.md`
