---
name: brain-insights
description: Analyze recent Claude Code and Pi sessions plus agentBrain notes to surface work patterns, friction, missing skills/learnings, and quick wins.
argument-hint: Optional window, e.g. "7 days", "30 days", or a project name
user-invocable: true
resources:
  - system/rules.md
  - learnings/patterns.md
  - learnings/troubleshooting.md
  - local/projects/
  - local/learnings/
  - local/sessions/
---

# Brain Insights

Generate a private reflection report from recent Pi sessions and agentBrain notes.

## Default scope

- Time window: last 14 days unless the user specifies another window.
- Session sources:
  - `~/.claude/projects/*/*.jsonl` for Claude Code transcripts (via `scripts/session-digest.sh`).
  - `~/.pi/agent/sessions/` for Pi JSONL sessions (same digest script).
  - `local/sessions/` for agentBrain session journals and archives.
- Knowledge sources:
  - `local/projects/*/index.md` and optional project files.
  - `local/learnings/` plus public placeholder files for structure only.
  - `learnings/patterns.md`, `learnings/troubleshooting.md` for policy/examples.

## Steps

1. **Set the window**
   - Parse the user argument for a day count, date range, or project name.
   - If unspecified, use the last 14 days.

2. **Collect session evidence (digest-first)**
   - Run the deterministic digest over both session sources:
     `bash scripts/session-digest.sh --days <N> --out local/sessions/digests/$(date +%F)-digest.md`
   - Read the digest, not raw transcripts. Deep-read at most the top 5 notable
     sessions (most turns, most errors, or repeated first prompts) directly from
     their JSONL files, and summarize — never paste raw transcript content.
   - Read `local/sessions/session-journal.md` and recent `local/sessions/archive/YYYY-MM/*.md` when present.

3. **Collect brain context**
   - Read active project indexes from `local/projects/*/index.md`.
   - Read relevant `local/learnings/` notes.
   - Check whether important findings are missing from learnings or troubleshooting.

4. **Analyze patterns**
   - Projects worked on most.
   - Tools and workflows used most.
   - Repeated friction or failure modes.
   - Wins and high-leverage improvements.
   - Candidate learnings/troubleshooting entries worth saving.
   - Preference or onboarding gaps to ask the user about later.
   - Repeated first prompts across sessions (skill candidates: same ask 3x+ = missing skill).
   - Skills that never appear in the digest's skill-usage aggregation (dead or undiscoverable skills — input for /brain-retro).
   - Prompt inefficiencies: sessions with many turns and errors on one small task.

5. **Write a private report**
   - Save to `local/reports/brain-insights-YYYYMMDD.md` unless the user asks for chat-only output.
   - Include frontmatter:
     ```yaml
     ---
     date: YYYY-MM-DD
     type: report
     tags: [brain-insights, sessions, agentbrain]
     source: session-analysis
     id: <UUID5>
     ---
     ```
   - Generate UUID5 with `scripts/uuid5-gen.sh "local/reports/brain-insights-YYYYMMDD"`.

6. **Report back concisely**
   - Mention report path.
   - List top 3 insights and top 3 recommended actions.
   - Ask before saving any new durable learning unless it is clearly proven and non-sensitive.

## Report outline

```markdown
# Brain Insights — YYYY-MM-DD

## Scope

- Window:
- Sources:

## At a Glance

- What's working:
- What's hindering:
- Quick wins:

## Work Patterns

- Projects:
- Tools/workflows:
- Interaction style:

## Friction

- Repeated issues:
- Validation gaps:
- Context/onboarding gaps:

## Candidate Learnings

- [ ] Pattern/troubleshooting item — evidence and suggested destination

## Recommended Actions

1. ...
2. ...
3. ...

## Related

- [[Patterns]]
- [[Troubleshooting]]
```

## Safety rules

- Reports are private and must stay under `local/`.
- Do not include secrets, tokens, private URLs, or customer data.
- Summarize sensitive session details instead of copying raw logs.
- Public files may describe the method only; real findings stay local.
- If command, scheduled job, transcript, or tool output is re-injected into agent context, scan/summarize it first and truncate large output.
