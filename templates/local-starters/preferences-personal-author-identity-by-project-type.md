---
date: {{date}}
type: user-preference
tags: [preferences, identity, git, author]
id: {{uuid5}}
# Machine-readable form of the buckets described below. project-init reads this
# block and applies it to a repository. The prose is the authority on WHY.
#
# Delete the examples and describe your own. Nothing here is required: with no
# types defined, project-init leaves the git identity alone and still scaffolds.
# The id is the ROLE the work plays; the label is your name for it. Roles are
# the same for everyone, labels are not, which is why only the labels are
# private data. Fill in the names and addresses you actually use.
project-types-default: published
project-types:
  published:
    label: ""
    git-name: ""
    git-email: ""
    license-holder: ""
    visibility: public
    detect: []
  incoming:
    label: ""
    git-name: ""
    git-email: ""
    license-holder: ""
    visibility: private
    detect: []
---

# Author identity per project type

Which name signs which kind of work. Decide it once, and `project-init` applies
it to every new repository instead of you remembering.

## Why bother

Forgetting costs a rewrite. Commits land under the wrong identity and the
history has to be rewritten to correct attribution, which is painful once
anything has been pushed or tagged.

Separating identities also keeps attribution and legal boundaries clear later:
trademarks, storefront guidelines, and bookkeeping all assume one author per
body of work.

## Define your buckets

The frontmatter above starts you with two, which is enough for most people. The
id names the role the work plays, so it means the same thing in anyone's vault;
the label is your own name for it.

- **Published**: what you release under your own name or brand. Set
  `visibility: public` so `project-init` reminds you to sanitize before the
  first public push.
- **Incoming**: forks, work accounts, client repositories. Things you consume
  rather than publish. Usually `visibility: private`.

Add more only when a real third case turns up. A common third is `storefront`:
consumer software that lands in an app store under its own publisher name.

Pick ids that describe the role, not the brand. A brand as an id ages badly
after a rename, and it can collide with words the framework already uses.

## detect

`detect` lists files or directories whose presence identifies the type, so a
repository is recognised without being told:

```yaml
    detect: [Dockerfile, docker-compose.yml]
```

Leave it empty for a type that should never be auto-detected.

## Rules worth keeping

- Set identities per repository, never globally. The global identity belongs to
  the machine.
- A bucket with no address is incomplete. `project-init` reports it and skips
  it, rather than writing a name that produces unattributable commits.
- README, LICENSE, SECURITY.md and contact details use the same identity as the
  commits.
- Record identifiers here, never secrets. Passwords and tokens belong in the
  keychain.
