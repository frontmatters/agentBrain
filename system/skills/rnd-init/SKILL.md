---
name: rnd-init
description: Scaffold the R&D convention in a repository - one kept-forever place for research and validation artefacts, with dashboards, decisions, captures, renders, logs and experiments, the right .gitignore lines and a README that carries the convention with the folder. Triggers - "set up R&D", "where do the screenshots go", "add an R&D folder", "scaffold R&D", a project that is about to produce validation artefacts (gates, sweeps, contact sheets, decision pages), or a repo that still writes into verif-output/.
---

# rnd-init: one place for the artefacts a project produces while proving itself

Validation artefacts scatter. Screenshots land in `verif-output/`, a dashboard
in `docs/ux/`, a rendered document in `/tmp`, a contact sheet in a scratchpad.
By the time someone asks "what did that look like before the fix", the evidence
has been overwritten or thrown away.

This skill creates one dated, kept-forever place with a fixed layout, so
validation is repeatable and reviewable instead of archaeological.

## Run it

```bash
bash system/skills/rnd-init/bin/rnd-init            # current repo
bash system/skills/rnd-init/bin/rnd-init --dir path/to/repo
```

It is idempotent. Run it again on a scaffolded repo and it reports
`0 created, 9 already present` without touching anything.

## What it produces

```
R&D/
  README.md       the convention, so a newcomer needs no other document
  dashboards/     validation dashboards (urls, links, commands, checklists)
  decisions/      decision pages  (the decision-page skill already writes here)
  captures/       screenshots, contact sheets, axe reports  (git-ignored)
  renders/        documents rendered to HTML                (git-ignored)
  logs/           gate output worth keeping
  experiments/    proof-of-concept scripts and data
```

Plus two lines in `.gitignore`, appended only if absent.

## The options, and when to use them

| Flag | Default | Use it when |
|---|---|---|
| `--with prototypes,art-studies,asset-mocks` | off | The project has design work of its own. Shipping empty folders everybody ignores is bloat. |
| `--migrate-verif-output` | off | The repo already writes into `verif-output/`. Moves the contents into `captures/` and leaves a symlink, so existing paths keep resolving. Opt-in because it moves real data. |
| `--no-gitignore` | off | The repo manages ignores elsewhere (a global file, a monorepo root). |
| `--dry-run` | off | You want to see the plan first. Writes nothing. |

## Three things that will bite you otherwise

**`R&D` contains `&`, a shell operator.** `cd R&D/captures` forks a background
job and fails. Quote every path: `cd "R&D/captures"`. The generated README says
so at the top, because this catches everyone once.

**`captures/` and `renders/` are git-ignored on purpose.** They hold large
binaries and regenerable output. They stay on disk forever and are never
committed. That is also why they carry no `.gitkeep`: it could never be
committed anyway. The four tracked folders do carry one, so the structure
survives a clone.

**An existing `R&D/README.md` is never overwritten.** A project may have added
its own rules (retention, naming). The skill reports `kept` and moves on.

## After scaffolding

Point the things that produce artefacts at it:

- gates and sweeps write into `R&D/captures/<date>-<topic>/`
- the `decision-page` skill already probes for `R&D/` and writes into
  `R&D/decisions/` when it exists
- rendered working documents go to `R&D/renders/` and are regenerated, never
  edited in place

Decision pages and dashboards are local files. They are never published.
