# Workspace

Working material that is not knowledge. It sits beside the vault, never inside it.

```
~/.agentBrain/
├── vault/        what you learned      (git, own remote, doctor validates it)
├── shared/       what you share        (git, own remote)
└── workspace/    what you worked with  (no git, nothing validates it)
```

## Why it is separate

The vault is checked. Every note there must carry frontmatter and a
path-derived id, its wiki-links must resolve, and its filenames feed the search
index. That is the point: it is knowledge, so it is held to a standard.

Working material cannot meet that standard and should not be asked to. A cloned
repository under review holds thousands of README and SKILL files written by
somebody else, to somebody else's conventions. Put it in the vault and every
check treats it as your knowledge: it fails validation, its filenames pollute
the search index, and its dead links drown the real ones.

Measured, when exactly that happened: 3520 foreign files produced 2521 schema
failures, and pruning them from the index turned 19 dead links into 4926
because their common basenames had been masking the real ones.

## What goes where

The lanes are named after how long the material lives, not what it is about.
That is the only property you can decide on the way in, before you know whether
anything useful will come of it.

| Directory | Holds | Lifetime |
| --- | --- | --- |
| `external/<name>/` | third-party checkouts, under review or as reference | until you are done with them |
| `derived/<producer>/` | output a producer can rebuild from its input | until the producer runs again |
| `scratch/<name>/` | throwaway working files, exports, intermediate output | delete whenever |

`derived/` is the `node_modules` of the brain: never edited by hand, never
backed up, and thrown away without a second thought because the producer makes
it again. `derived/graphify/` is the first tenant.

## What comes back out

The workspace holds the raw material. What you *learn* from it belongs in the
vault, as a note that stands on its own:

- an assessment of a third-party project goes in the space or in `learnings/`
- a pattern worth reusing goes in `learnings/`, in your own words
- a decision goes in the project note that the decision belongs to

The test is whether it still makes sense once the source is gone. If it does,
it is knowledge and belongs in the vault. If it only makes sense next to the
89 MB it came from, it stays here.

## What never goes here

Anything confidential. Sealed client material belongs in `vault/spaces/<slug>/`,
which is gitignored from the personal vault and backed up to its own remote.
The workspace has no git and no remote, so nothing here is backed up at all.
