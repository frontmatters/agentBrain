---
name: explain-branch
description: Generate a themed HTML explainer of a git branch's commits (what's in each commit) plus a merge/landing strategy, via brain-explain. Use when the user says "explain this branch", "what's in these commits", "document this branch before merge", "commit explainer", or wants to review/land a branch by seeing its commits laid out. Produces a reviewable HTML page under local/explainers/.
---

# explain-branch skill

Turns a git commit range into a **reviewable HTML explainer**: every commit
explained (what/why/which files), the review findings that were fixed, and a
**merge/landing-strategy** section. Reuses [[brain-explain]] for the render.
Agent-agnostic: pure git + brain-explain, works for any agent that can run bash.

## When to use

- Before landing a feature branch — so the user can *see* what each commit does
  and decide how to merge (fold-in vs rebase vs PR).
- To document a branch as durable, linkable knowledge (it lands in the graph).

## Procedure

1. **Pick the range.** Usually `git merge-base <parent> HEAD`..`HEAD` (only the
   branch's own commits), or an explicit `<base>..<head>`. Verify with:
   ```bash
   git log --oneline <base>..<head>
   git log --reverse --format='%h %s' <base>..<head> | while read -r sha _; do
     git show --stat --format='' "$sha" | grep '|'   # files per commit
   done
   ```

2. **Assess the landing topology** (this feeds the strategy section):
   ```bash
   git log --oneline main..<head>        # what a merge to main would carry
   git log --oneline main..<parent>      # is the parent branch ahead of main?
   ```
   If `main..<head>` ≫ the branch's own commits, a direct merge to main drags the
   parent's unmerged work along — say so, and recommend fold-into-parent (ff) or
   rebase-onto-main with the trade-offs.

3. **Write the explainer note** at `local/explainers/<slug>/index.md` with
   frontmatter `type: explainer`, `category: workflows`, a `theme` (clean-flat),
   and `id` from `bash scripts/uuid5-gen.sh 'local/explainers/<slug>/index'`.
   Structure with brain-explain shortcodes:
   - a one-line mental model,
   - `:::layers` for the phases,
   - `:::flow` listing each commit (`**\`sha\`** · subject — what/why *(files)*`),
   - `:::callout` for the review findings that were fixed,
   - `:::callout` + `:::cards` for the **merge/sync-strategy** with a recommendation,
   - a "still to do after landing" note (e.g. a stashed WIP to restore).

4. **Render + verify:**
   ```bash
   bash system/addons/brain-explain/bin/brain-explain render \
     local/explainers/<slug>/index.md --out local/explainers/<slug>/index.html
   ```
   Then **verify visually** (hard rule): serve it (`python3 -m http.server` in the
   dir) and screenshot with the webapp-testing/Playwright tool or `snapcoder` —
   `file://` is blocked in Playwright, so serve over `127.0.0.1`.

5. **Link it in the MOC** `local/explainers/index.md` under `## workflows`, and
   `bash scripts/sync-agentbrain-local.sh`.

## Notes

- The narrative is written per-branch (LLM) — there is deliberately no scaffolding
  script yet; add one only if this proves useful 2×+ (YAGNI).
- Example output: `[[queue-dispatch-branch/index]]` — the first dogfood of this skill.

## Related

- [[brain-explain]] — the render engine · `local/explainers/index.md` — the MOC
