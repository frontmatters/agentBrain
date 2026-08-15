---
name: grill-me
description: Relentless knowledge-extraction interview. Asks focused questions to pull tacit knowledge (context, business, workflow, goals) out of the user's head and into agentBrain's local preferences and notes.
argument-hint: Optional focus area — "business", "workflow", "goals", "clients", "tech-stack", or leave empty for full session
user-invocable: true
resources:
  - local/preferences/personal/
  - local/preferences/organization/
  - local/preferences/team/
---

# Grill Me

Extract tacit knowledge from the user via a relentless but focused interview.
The output lands in `local/preferences/` and/or a dedicated brain note.

## When to use

- At brain setup (new install, no preferences yet)
- When starting a new business domain or project
- Periodically (quarterly) to refresh the brain's context
- Any time the user says "it doesn't know me well enough"

## Interview flow

### 1. Assess what's already known

Before asking anything, read existing files under:
- `local/preferences/personal/`
- `local/preferences/organization/`
- `local/preferences/team/`

Summarize in one sentence what the brain already knows about the user.
Then say: "I'm going to ask you questions to fill the gaps. Answer freely — I'll
turn your answers into structured brain notes. Type 'stop' at any time to end."

### 2. Choose a focus

If the user passed a focus argument (e.g. `/grill-me business`), use that focus.
Otherwise run a full session covering all domains in order.

Available focus areas:

| Focus | What to extract |
|---|---|
| `business` | what the user does, their customers, revenue model, team, unique edge |
| `workflow` | daily rhythms, tools used, how decisions are made, bottlenecks |
| `goals` | 90-day goals, 1-year goals, what success looks like, current blockers |
| `clients` | who are the clients, what do they need, how are they managed |
| `tech-stack` | languages, frameworks, infra, AI tools, preferences, dislikes |
| `communication` | how the user prefers to be spoken to, tone, verbosity, format |

### 3. Ask relentlessly — 15–25 questions minimum

Never ask multiple questions in one message. One question at a time.
Wait for the answer. Then ask a follow-up or pivot to the next topic.

Question principles:
- **Concrete over abstract** — "What did you work on last week?" not "What are your priorities?"
- **Devil's advocate** — "You said X — what would someone who disagrees say?"
- **Fill the gaps** — ask about things that are NOT in the preferences yet
- **Surface tensions** — "You said you prefer async, but also need to be responsive — how do you handle that?"
- **Quantify when useful** — "How many clients do you have right now?" "What % of your time goes to X?"

Keep asking until one of:
- User types "stop"
- You have 15+ answers and all focus areas are covered
- No meaningful new information surfaces in 3 consecutive answers

### 4. Write the output

After the interview (or when user says "stop"), write the extracted knowledge:

**Always write to:**
- `local/preferences/personal/<topic>.md` — for personal facts and preferences
  (create or update; never overwrite content the user explicitly set)

**Optionally write to:**
- `local/preferences/organization/<topic>.md` — if the user revealed org-level context
- `local/preferences/team/<topic>.md` — if team agreements emerged

**Format for each file:**
```markdown
---
date: YYYY-MM-DD
type: preferences
tags: [preferences, personal]  # adjust scope
source: grill-me
id: <UUID5 via scripts/uuid5-gen.sh>
---

# <Topic>

<Content as structured markdown — paragraphs, bullet lists, or tables as fits>
```

Generate UUID5: `bash scripts/uuid5-gen.sh "local/preferences/personal/<filename-no-ext>"`

**After writing:** tell the user:
- How many files were created/updated
- What the brain now knows that it didn't before
- Suggest running `/brain-insights` to see how the new context affects recommendations

### 5. Optional: dedicated brain note

If the interview surfaced a detailed business model, a complex project, or
structured context too rich for a preferences file, also write:
- `local/projects/<name>/context.md` (for project-specific context)
- `local/learnings/<topic>.md` (for a durable insight or pattern)

## Rules

- Never ask about credentials, passwords, or API keys — redirect to `local/security/`
- Never print sensitive values from the answers back to the user in a summary
- Update existing preference files rather than creating duplicates
- Keep files concise — preferences are context, not documentation
- If the user corrects a previous answer, update the file immediately

## Example opening

> "I've read your current brain preferences. Here's what I know: [one-sentence summary].
> Let's fill the gaps. First question — what's the most important thing you're working on right now?"
