---
name: unpark
description: Resume a previously /park-ed agentBrain project in a new session. Reads local/projects/<name>/index.md plus all Related learnings, summarizes status and open backlog, adds an "unparked" entry to Progress, and starts executing the backlog instructions. NB - this is not the same as `claude --resume` or `pi resume`, which restore chat sessions; /unpark works at the project level inside agentBrain. Triggers - "unpark X", "continue with project X", "resume project X", "pick X back up", "open my work on X", "execute the backlog of X".
related: [park, list-parks]
---

# unpark — pick up a parked project

Counterpart to [[park]]. Used in a **new session** to reload the save from
a previous session and execute the open backlog.

## When to use

- New session opened, user wants to continue earlier work.
- User mentions a project name with verbs like "unpark", "continue",
  "pick up", "resume", "execute the backlog".
- User pastes the unpark prompt that `/park` generated at the end.

**Do not confuse with `claude --resume` / `pi resume`**: those restore an
earlier chat conversation at the CLI level. `/unpark` operates at a higher
level: on an agentBrain project and its backlog, independent of which chat
session or agent.

## Do not use for

- Trivial lookups ("what's in project X?") — use `Read` directly.
- Projects without a parked index.md — first finish `/park` in the previous
  session.
- Projects with status `done` — those are finished; read the changelog
  rather than running a resume flow.

## Steps (follow in this order)

### 1. Determine the project

- **Project name explicit**: user names it → use that.
- **Project number from /list-parks**: user types `/unpark 3` or similar
  → resolve via the cached index file at `~/agentBrain/local/.parks-index.json`
  (written by the most recent `/list-parks` run). See "Number resolution"
  below.
- **No project name or number given** (bare `/unpark`, or "continue where we
  were" without naming it) → render the parked-projects table inline (see
  "No-argument listing" below), then ask which to pick **by row number or
  name**. Do not guess, and do not dodge into chat resume.
- **Sanity check**: `local/projects/<projectname>/index.md` exists. If not
  → ask whether it is spelled correctly and list available projects.
- **Do not silently dodge into chat resume**: if the user says "resume"
  without a project name, ask whether they mean `claude --resume` (chat
  session) or `/unpark <project>` (project backlog). Do not guess.

#### No-argument listing

When `/unpark` is called with no project name or number, print a Markdown table
of every `paused`/`blocked` project, newest first, so the user can pick by row
number or name. Row numbers are stable because the scan is sorted
deterministically (date descending), so the same snippet resolves a later
`/unpark <N>`.

```bash
{
  printf '| # | Project | Status | Prio | Date | Where I left off |\n'
  printf '| --- | --- | --- | --- | --- | --- |\n'
  for f in "$HOME"/agentBrain/local/projects/*/index.md; do
    [ -f "$f" ] || continue
    st=$(awk -F': *' '/^status:/{print $2; exit}' "$f")
    case "$st" in paused|blocked) ;; *) continue ;; esac
    name=$(basename "$(dirname "$f")")
    pr=$(awk -F': *' '/^priority:/{print $2; exit}' "$f")
    dt=$(awk -F': *' '/^date:/{print $2; exit}' "$f")
    # FULL "## Status" section (every line until the next "## "), joined to one
    # cell. No truncation — the whole "where I left off" must be visible. Strip
    # pipes/newlines so the Markdown row stays valid.
    sl=$(awk '/^## Status/{s=1;next} s&&/^## /{exit} s&&NF{print}' "$f" | tr '\n' ' ' | tr '|' '/' | sed 's/  */ /g; s/ *$//')
    printf '%s\t%s\t%s\t%s\t%s\n' "${dt:-0000-00-00}" "$name" "$st" "${pr:--}" "${sl:--}"
  done | sort -r | awk -F'\t' '{printf "| %d | %s | %s | %s | %s | %s |\n", NR, $2, $3, $4, $1, $5}'
}
```

After printing the table, ask which project to unpark (row number or name). To
resolve a number, re-run the snippet and take the row whose `#` matches.

#### Number resolution

When the user passes a number (e.g. `/unpark 3`):

1. Read `~/agentBrain/local/.parks-index.json`. If missing or stale
   (older than 24h), run `/list-parks` first to refresh.
2. Find the entry where `n` matches the argument.
3. Use its `name` field as the project name.
4. If `n` is out of range: tell the user "Number N is not in the current
   parks index (which has M entries). Run `/list-parks` to refresh."
5. If the resolved project's `index.md` no longer exists (project was
   renamed/deleted since the index was written): tell the user and
   suggest re-running `/list-parks`.

Quick bash for resolution:

```bash
INDEX="$HOME/agentBrain/local/.parks-index.json"
N=3
NAME=$(grep -o "{\"n\":$N,\"name\":\"[^\"]*\"" "$INDEX" | sed 's/.*"name":"//;s/"//')
```

### 2. Read the project document fully

```
Read ~/agentBrain/local/projects/<projectname>/index.md
```

Pay special attention to:

- **Frontmatter `status`**: `paused` / `blocked` / `active` — determines
  whether resume even makes sense.
- **`## Status` paragraph**: one-paragraph summary of where you left off.
- **`## Setup` table**: paths to artifacts; verify those paths still exist
  (`ls` checks) before doing anything — paths may have moved.
- **`## Backlog — Unpark instructions`**: the heart. Read EVERY step,
  especially the classification table of findings.
- **`## Related`**: list of wiki-links to learnings — these are relevant
  for execution, not optional reading.

### 3. Read the Related learnings

For every `[[link]]` in `## Related`: open the learning. No summaries —
direct `Read`. Insights from earlier sessions are often the reason a
particular fix choice was made.

If a link is `[[forward:X]]`-marked: skip (forward-ref, target doesn't
exist yet).

### 4. Verify the current state of the work

**Before changing anything**, check that the world still looks like the
project document describes:

- Do all paths from the `## Setup` table exist?
- Did the user make changes in the meantime? Check
  `git status` / `git log -1 --since="<park-date>"` on the relevant repos.
- Does the "what is done" claim still hold? Run smoke tests or validation
  scripts if the project doc lists any.

In case of **drift** between project document and reality: stop, report
it to the user, ask whether the document should be updated before
continuing. Never blindly execute backlog steps on a document that no
longer reflects reality.

### 5. Add an "Unparked" entry to Progress

Update `local/projects/<projectname>/index.md` `## Progress` with one
line:

```markdown
- **YYYY-MM-DD** — Unparked in new session. [short line about what comes
  first: "starting with fix step 1: resolve_scope_root fail-closed"].
```

Plus: update frontmatter `date:` and `status:` (from `paused` to `active`).

### 6. Execute the backlog

Follow the "Concrete fix steps" in order. For each step:

- Make the change.
- Verify (test, build, smoke test — whatever the step prescribes).
- Caution: do NOT deviate from the classification. Items marked
  ❌ FALSE POSITIVE or ❌ DISAGREE were deliberately excluded — do not
  address them anyway unless the user explicitly asks.

### 7. Update Progress per completed phase

After each substantial block of work: add a Progress entry with date +
one-line summary. Not only at the end. This makes mid-session crash
recovery trivial.

### 8. Decide status at session end

At the end of the unpark session:

- **All done** → status=`done`, optionally a changelog entry, ask the user
  whether the project can be archived / promoted.
- **Partly done, rest later** → call `/park` again with the updated
  backlog (also save insights from this session).
- **Blocked** → status=`blocked` with the blocker explained in the Status
  paragraph.

## Anti-patterns (do not do)

- **Executing the backlog without first reading the Related learnings.**
  A fix step that says "change line 142" lacks context if you don't know
  why line 142 was ever written that way.
- **Addressing FALSE POSITIVE findings anyway.** The reviewer classified
  it in the previous session — you are not the reviewer now.
- **Executing the backlog against stale paths.** First check the setup
  still holds — `ls` is cheap.
- **"Quickly unparking" without a Progress entry.** Next time you unpark,
  the current session is context, and without a log you miss it.
- **Unpark accompanied by scope creep.** Execute only the open backlog.
  Other ideas that arise during unpark → note them in a new Backlog
  section or in a new `/park` cycle at the end.

## Example: short unpark prompt that triggers this skill

```
Unpark promote-demote-skill via
~/agentBrain/local/projects/promote-demote-skill/index.md — execute
the backlog.
```

Or, shorter:

```
/unpark promote-demote-skill
```

## When NOT to use /unpark on a project

- **Done projects**: they're finished. Read the changelog, don't unpark.
- **Unknown projects** (where you haven't done `/park` yet): start with
  normal exploration + `/brainstorming` skill, not `/unpark`.
- **Cross-machine unpark**: if the project was parked on another machine,
  first run `gitea-sync` or equivalent so `local/` is up to date.
  Otherwise you read an outdated snapshot.
- **Restoring a chat session**: that's `claude --resume` or `pi resume`,
  NOT `/unpark`. `/unpark` works on project backlogs, not on chat logs.

## The three-skill loop

| Skill | When | Direction |
|---|---|---|
| `/list-parks` | start of a session, or any time | see — what is parked? |
| `/unpark <name>` | you picked a project from /list-parks | load — pick up the backlog |
| `/park` | end of working session, not done | save — checkpoint + insights |

Mnemonic: **see → load → save.**

## Related

- [[park]] — counterpart; save skill for this flow
- [[list-parks]] — dashboard of all parked work; run this first if you don't know the project name
- [[forward:journal]] — session-log skill (useful to place unpark context)
