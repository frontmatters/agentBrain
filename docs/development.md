---
date: 2026-07-03
type: system
tags: [docs, development, release, maintainer]
id: 3464a45a-bf59-5aff-ae07-1de6283adb47
---

# Development & release workflow

Maintainer documentation. Consumers never need any of this — the user-facing
commands live in the [README](../README.md).

## Dual-checkout model

Development happens in a `-dev` checkout; a second checkout serves as the live
install. Both share one private vault (`vault/` symlinks into it), so flipping
between them never touches knowledge. See `system/architecture.md` for the
canonical description. `brain status` shows which checkout is active and how
far each one is from its last tag; `brain use dev|live` flips between them.

## Quality gates

The pre-push hook validates the commit being pushed, not the working tree: it
checks that sha out in a detached worktree (with the vault link and brain.json
put in place), runs `doctor.sh --fast` there, and removes the worktree. A
commit or edit made while the doctor runs, from this session or another, can
no longer fail the push or slip past it; what is green is what lands.

| Gate                        | When it runs                                                             |
| --------------------------- | ------------------------------------------------------------------------ |
| `.githooks/pre-commit`      | Path-aware fast checks on staged files: privacy scan, NDA gate, shellcheck plus an SC2317 unreachable-code pass, em-dash and invisible-character checks on added lines, addon/frontmatter checks. Warns when a symlink shim's target is dirty and unstaged (`check-shim-staging.sh`) |
| `.githooks/commit-msg`      | Conventional Commits subject format (see below); no em-dashes in the message; refuses a message that names a file the commit does not carry while that file sits dirty behind a shim |
| `.githooks/pre-push`        | `doctor.sh --fast` (structural + privacy checks)                         |
| `.githooks/post-commit`     | Opt-in auto-push (see below). Ships tracked but a **no-op by default** — clones/contributors never inherit it |
| `scripts/checks/doctor.sh`         | Full health audit (`--ci` scopes to the shippable artifact; `--pi-lens-strict` for release quality). Serialized by `scripts/lib/lock.sh`: a second doctor waits, nested ones proceed |

To try a command against a throwaway agentBrain instead of your own, use
`bash scripts/tools/sandbox-run.sh <command>`: it redirects every location an
install writes to (agent skill dirs, add-on state, Pi config, `HOME`) into a
temporary directory.

### New addons are built off `main`

`system/addons/` is part of the framework tree the doctor gates: `check-addons`
validates every manifest it finds there, `clients.md` must match all of them,
`check-frontmatter` reads every markdown file and the skill links must point at
enabled addons. Those checks run over the working tree, uncommitted files
included. A half-built addon in that directory therefore turns the doctor red,
and with it the pre-push gate.

So a new addon is built on a branch or in its own worktree
(`git worktree add ../agentBrain-<addon> -b addon/<id>`) and lands in
`system/addons/` on `main` only when `bash scripts/checks/check-addons.sh`
passes for it. A release is built from committed work only, never from a
working tree.

### Maintainer auto-push (opt-in)

`.githooks/post-commit` can auto-push each commit to `origin` in the background,
but only after you turn it on **per checkout** — it is a no-op otherwise:

```sh
git config agentbrain.autopush true      # enable on a maintainer machine (dev, live)
git config --unset agentbrain.autopush   # back to default (off)
```

The config is local (never committed), so enabling it on your dev checkout does
not enable it for anyone else. When on, opt a single commit out with a
`[skip-push]` marker (also `[no-push]` / `[local-only]`) in the message, or
`COMMIT_SKIP_PUSH=1 git commit …` — the supported way to hold release-prep
commits (VERSION/CHANGELOG bumps) for local review before they are pushed.

## Commit convention

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) —
the missing link between the commits and the two standards the CHANGELOG already
adheres to ([Keep a Changelog](https://keepachangelog.com/) + [SemVer](https://semver.org/)):
the `type` maps to a release bump (`fix` → PATCH, `feat` → MINOR, `!`/`BREAKING
CHANGE` → MAJOR) and to a changelog section.

```
<type>(<optional-scope>)<optional-!>: <description>
```

- **Types**: `feat` `fix` `docs` `style` `refactor` `perf` `test` `build` `ci` `chore` `revert`.
- **Scope** (optional) names the touched area — a script, skill, addon, or subsystem
  (`feat(queue):`, `docs(spaces):`). Put the area in the *scope*, not the *type*
  (`feat(pi):`, not `pi:`).
- **`!`** before the colon marks a breaking change (`feat(api)!: …`).
- Subject in the imperative, English (matches the repo-wide rule), no trailing period.

`.githooks/commit-msg` enforces this on every commit; `Merge`/`Revert`/`fixup!`
subjects are exempt. Bypass a single commit with `git commit --no-verify`.

## Releases

Release tooling (archive build, release checks, publishing) is not part of this
repository. What ships here is the part a contributor touches:

- Add changelog entries with `bash scripts/changelog-add.sh <Added|Changed|Fixed|Removed> "<one line>"`.
  It writes under `[Unreleased]` and creates the section header when missing,
  which matters right after a release: `[Unreleased]` is empty then, and the
  first `### Fixed` in the file belongs to the published version.
- Public stable releases are published on `main`; release candidates on `next`,
  from immutable `vX.Y.Z-rc.N` tags. See `scripts/installer/README.md` for
  opting in to release candidates.

**A release is done only when it is published on GitHub.** After that its tag
is immutable: any further change is a new version.

## Writing style

Every sentence a human reads follows `system/writing-style.md` (*The Elements
of Style*): name the subject, omit needless words, concrete over vague, honest
claims only. In a source checkout, `scripts/checks/check-writing-style.sh` guards the policy in the doctor;
Claude Code users can invoke the `elements-of-style` plugin skill while
writing. Source comments and system/ docs stay English
(`check-english-sources.sh`).

## Versioning & releases (ksc)

agentBrain follows the **ksc** triad — SemVer + Keep a Changelog + Conventional
Commits — enforced by tooling, not convention:

1. **Conventional Commits** — the `commit-msg` hook rejects anything that is not
   `type(scope): subject`. Types drive the bump: `feat` → MINOR, `fix` → PATCH,
   `!`/`BREAKING` → MAJOR.
2. **Keep a Changelog** — `CHANGELOG.md` keeps an `## [Unreleased]` section.
   Draft it from the commits: `bash scripts/changelog-draft.sh` (feat→Added,
   fix→Fixed, revert→Removed, rest→Changed), then curate.
3. **SemVer + display rule** — `VERSION` holds the latest release (X.Y.Z). The
   displayed version is exact `vX.Y.Z` on a release and `git describe`
   (`v1.7.0-74-g6fb3d69`) everywhere in between, so a dev build never poses as
   a release. Releasing moves `[Unreleased]` to `[vX.Y.Z]` with its date and
   bumps `VERSION`.
