---
name: project-init
description: Apply the owner's project-type decisions to a repository - repository-local git identity, the LICENSE holder for that type, and the R&D scaffold. The types themselves live in the owner's vault, so this ships with no brands in it and works on a machine that has defined none. Triggers - "set up this project", "which identity should this repo use", "new project", "init this repo", "am I committing under the right name", a fresh repo about to get its first commit.
---

# project-init: the decision is already made, apply it

Which name signs which kind of work is a decision most owners make once and then
have to remember on every new repository. Forgetting it costs a rewrite: commits
land under the wrong identity and the history has to be rewritten to fix
attribution.

This skill reads that decision and applies it. It does not make it.

## Public mechanism, private types

The types are not in this skill. They live in a vault note as a
`project-types:` block, because which brands exist and which address signs which
work is the owner's data, not framework knowledge. This follows the rule in
`system/rules.md`: public is HOW and WHERE, private is WHAT.

```
system/skills/project-init/     the mechanism, identical for everyone
vault/…/…-project-type.md       the types, different for everyone
templates/local-starters/       a generic example, seeded into a fresh vault
```

A machine that has defined no types is a supported state. The skill says so,
leaves the repository identity alone and still scaffolds.

## Run it

```bash
bash system/skills/project-init/bin/project-init            # detect or default
bash system/skills/project-init/bin/project-init --type <id>
bash system/skills/project-init/bin/project-init --list
bash system/skills/project-init/bin/project-init --dry-run
```

## What it does, and what it refuses to do

| Step | Behaviour |
| --- | --- |
| Pick a type | An explicit `--type` wins. Otherwise the markers recorded per type are matched against the repo. Otherwise the declared default. |
| git identity | Set with `git config` inside the repository. Never `--global`: the global identity belongs to the machine, not to one project. |
| Incomplete type | A type whose address is not decided yet is reported and skipped, never half applied. A name without an address produces commits nobody can attribute. |
| LICENSE | Read, reported, never rewritten. A licence is a legal statement; a scaffold that edits one silently is worse than one that says nothing. |
| R&D | Delegates to `rnd-init`, so the layout has one implementation. `--no-rnd` skips it. |
| Published types | Prints a reminder to sanitize before the first public push. |

Running it twice is safe: it reports the identity is already set and creates
nothing.

## Defining the types

Add to the frontmatter of the vault note that already explains the decision, so
the reasoning and the machine-readable form stay in one file:

```yaml
project-types-default: <id>
project-types:
  <id>:
    label: <human name>
    git-name: <commit name>
    git-email: <commit address>
    license-holder: <copyright holder, or empty>
    visibility: public | private
    detect: [Dockerfile, Package.swift]
```

`detect` lists files or directories whose presence identifies the type. Leave it
empty for a type that should never be auto-detected.

Only the fields above are read. The parser is deliberately small and uses no
YAML library, because PyYAML is not in the Python standard library and a
scaffold must not fail on a machine that has not installed it.
