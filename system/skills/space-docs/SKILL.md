---
name: space-docs
description: >
  Produce a self-contained, transferable documentation set for a project or
  "space": a small standalone docs repo (README + ARCHITECTURE + ROADMAP +
  MEMORY, with rendered diagrams) that stands on its own boundary — no
  machine-local paths, no private/vault notes, no dead links, so it can be
  handed to a colleague or moved to another machine unchanged. A deterministic
  validate.sh gates delivery. Use when the user asks for "space-docs",
  "self-contained docs", "transferable documentation", "deelbare documentatie",
  "documenteer dit project/deze space", "maak de docs self-contained", or wants
  a project's knowledge captured as a shareable, portable bundle.
---

# space-docs

Turn scattered/private knowledge about a project into a **self-contained,
transferable docs bundle**. The deliverable is one small docs folder/repo that a
recipient can read and act on **without** your vault, your machine, or the code
repos open.

**Announce:** "Using space-docs to produce a self-contained docs set for <space>."

## The one boundary rule

Everything the docs reference must live **inside the space's own boundary** —
the docs repo itself, or the project's own repos/infra/code. Nothing may point
OUT: no machine-local paths (`/Users/...`), no private notes/vault, no dead
links, no session-specific artifacts. If it points out, **rewrite it in** or
drop it. `scripts/validate.sh` enforces this.

## Workflow

1. **Scope the space.** Name the parts (repos, services, data) and how they
   relate. One repo or an ensemble of several? The docs describe the whole.

2. **Scaffold the doc set** (copy from `templates/`):
   - `README.md` — the map: what the parts are, how they relate, where things
     live. The entry point.
   - `ARCHITECTURE.md` — the system: components, trust/egress boundary, the
     decision records (ADRs), open questions. Diagrams as Mermaid.
   - `ROADMAP.md` — milestones + a building-block inventory (existing vs to-build).
   - `MEMORY.md` — runtime footprint per component/building block (measure it;
     idle vs under load). Optional but valued.
   Drop any section that does not apply; add space-specific ones as needed.

3. **Fill from evidence, self-contained.** Every claim grounded in the real
   thing (file path, command, measurement). Use **portable references**:
   `$HOME`, `~`, or repo-relative paths — never absolute machine paths. Describe
   the project's own code/infra freely (that is in-scope); never reference your
   private vault or this session.

4. **Render diagrams to PNG** (portable/offline export) while keeping the Mermaid
   source inline (renders in-browser on most git hosts):
   ```bash
   mmdc -i diagram.mmd -o diagram.png -t neutral -b white -s 2
   ```
   Keep the `.mmd` sources next to the PNGs so they are regeneratable. Visually
   verify each PNG before shipping (open it / screenshot it).

5. **Validate the boundary** — the gate:
   ```bash
   scripts/validate.sh <docs-dir>     # exit 0 = self-contained
   ```
   It FAILS on: machine-local paths, private/vault references, dead/absolute/
   `..`-escaping links, hard secrets (keys/tokens), off-space deny-list terms
   (other clients / unrelated — pass a local deny-list as arg 2), and **any
   subfolder without a README** (every folder documents itself). It WARNs on
   internal hosts/IPs and credential-like values/emails (confirm they belong to
   the space). Fix every FAIL, then re-run until PASS.

6. **Make it a repo + publish** so nothing stays local. `git init`, commit,
   push to the project's git host (private if it is client data). Cross-link
   only to files that are inside the bundle or clearly part of the space.

## What counts as in-scope vs a leak

| In-scope (fine) | Out-of-boundary (rewrite/remove) |
|---|---|
| the project's own repos, code paths, infra hosts | machine-local paths (`/Users/<name>/…`) |
| portable refs (`$HOME`, `~`, repo-relative) | your private vault / notes / this session |
| the project's own Gitea/registry host (flagged) | dead links to files not in the bundle |
| measured numbers, real commands | "see my earlier analysis" / unshared sources |

## Handling a link that leaves the boundary

`validate.sh` fails three kinds of escaping link: `DEADLINK` (target not in the
bundle), `ABSLINK` (absolute path), and `OUTLINK` (a `../`-link that resolves to
a real file OUTSIDE the space — passes on your machine because the sibling repo
is there, breaks for a recipient who only has the bundle). Decide by **what the
target is**:

- **It belongs to the space** (e.g. a sibling repo's doc that is part of the same
  project) → **bring it IN**: copy the doc into the bundle and link to the local
  copy, OR summarise its essence inline. If it must stay external, downgrade the
  clickable link to a **plain textual pointer** (`` see `docs/X.md` in the app
  repo ``) — descriptive, not a dangling link.
- **It is truly external / private** (your notes, another team's doc, this
  session) → **drop it** or replace with a self-contained sentence. Never link
  out of the boundary.

Rule of thumb: a reader with ONLY the bundle must never hit a broken or escaping
link. Every clickable link resolves inside the bundle; everything else is prose.

## Privacy & relevance — only space-relevant information

Self-contained is not enough; the bundle must also be CLEAN and ON-TOPIC.
Everything in it is required for THIS space and safe to hand over. Three more
gates in `validate.sh`:

- **No secret material (FAIL).** Private keys and tokens (AWS / GitHub / Slack /
  JWT) never belong in shareable docs. Reference secrets by env-var name, never
  by value.
- **Credential-like values & emails (WARN).** A `password: <value>` or an email
  is flagged for review — acceptable only as intentional dev/test creds or a
  space-relevant contact; otherwise redact (point at the `.env` / vault instead).
- **No off-space content (FAIL, via deny-list).** Nothing that is not required
  for this space — no other clients, no unrelated projects or internal codenames.
  Configure a deny-list of those terms (validate.sh arg 2, or a git-ignored
  `.space-deny` at the docs root) and keep it **local**, so the sensitive names
  never enter the shared repo itself.

## Why this beats ad-hoc docs

- The **boundary validator** turns "is this shareable?" into a deterministic
  gate — no accidental machine-path or vault leak.
- The **fixed doc set** (map + architecture + roadmap + memory) is a repeatable
  shape a recipient learns once.
- **Rendered diagrams + portable refs** make the bundle move to another machine
  or colleague unchanged.
