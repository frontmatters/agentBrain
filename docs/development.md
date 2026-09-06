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
canonical description.

| Command                         | What it does                                                              |
| ------------------------------- | ------------------------------------------------------------------------- |
| `tools/framework-sync-status.sh` (factory) | Show live/dev sync status (`--doctor` for full diagnostics)          |
| `tools/framework-deploy-live.sh` (factory) | Rsync the public layer dev → live (dry-run by default; `--apply` to run) |

## Quality gates

| Gate                        | When it runs                                                             |
| --------------------------- | ------------------------------------------------------------------------ |
| `.githooks/pre-commit`      | Path-aware fast checks on staged files: privacy scan, NDA gate, shellcheck plus an SC2317 unreachable-code pass, em-dash and invisible-character checks on added lines, addon/frontmatter checks. Warns when a symlink shim's target is dirty and unstaged (`check-shim-staging.sh`) |
| `.githooks/commit-msg`      | Conventional Commits subject format (see below); no em-dashes in the message; refuses a message that names a file the commit does not carry while that file sits dirty behind a shim |
| `.githooks/pre-push`        | `doctor.sh --fast` (structural + privacy checks)                         |
| `.githooks/post-commit`     | Opt-in auto-push (see below). Ships tracked but a **no-op by default** — clones/contributors never inherit it |
| `scripts/checks/doctor.sh`         | Full health audit (`--ci` scopes to the shippable artifact; `--pi-lens-strict` for release quality). Serialized by `scripts/lib/lock.sh`: a second doctor waits, nested ones proceed |
| `tools/framework-validate-install.sh` (factory) | Fresh install + idempotent re-run + doctor in a disposable sandbox |
| `tools/framework-release-check.sh` (factory) | Doctor, privacy scan, archive build, private-path check, disposable test install from the archive |

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
commits (VERSION/CHANGELOG bumps) for local review before `deploy-dev-to-live`.

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

## Cutting a release

Release tooling is not in this repository. It lives in the factory, the
directory beside this checkout that holds every agentBrain checkout, the
archives and the addon catalogue (`~/Developer/agentBrain-factory/`, its own
private repo). A consumer never has it, and the archive built from this repo
is `git ls-files` with nothing to strip.

From the factory, with `CHECKOUT=dev|next|live` (default `dev`):

1. `tools/framework-bump-version.sh patch --pre` per candidate; `--release`
   to finalize the candidate's version as a stable `X.Y.Z`.
2. Curate `CHANGELOG.md` in the checkout (the build refuses `TODO`
   placeholders) and write the entries under `[Unreleased]` for the version the
   candidates are for; `tools/checks/check-changelog.sh` refuses an empty section or a TODO.
3. `CHECKOUT=next tools/framework-release-check.sh`: the full gate against the
   actual archive.
4. `CHECKOUT=next tools/framework-publish-gitea.sh --prerelease`: tag plus
   archive asset on the Gitea dev remote (candidates stay here).
5. Stable only: `tools/framework-publish-github.sh` force-pushes a clean
   single-commit snapshot to the public GitHub repo (no dev history), and the
   release archive is attached to a GitHub release.

   The release check stamps the archive it passed (`<zip>.checked`, with the
   archive's checksum). Both publishers refuse an archive without a matching
   stamp, and `publish-github` publishes that same archive instead of
   rebuilding one: what ships is what was checked.

**A release is done only when it is published on the public channel (GitHub).**
Until that publish, the tag has zero consumers and MAY be re-cut to fold in
late fixes: no patch release exists for a version nobody could install. After
the GitHub publish the tag is immutable: any further change is a new version.

## Writing style

Every sentence a human reads follows `system/writing-style.md` (*The Elements
of Style*): name the subject, omit needless words, concrete over vague, honest
claims only. `scripts/checks/check-writing-style.sh` guards the policy in the doctor;
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
   fix→Fixed, revert→Removed, rest→Changed), then curate. `release.sh` refuses
   to build when the release is undocumented.
3. **SemVer + display rule** — `VERSION` holds the latest release (X.Y.Z). The
   displayed version is exact `vX.Y.Z` on a release and `git describe`
   (`v1.7.0-74-g6fb3d69`) everywhere in between, so a dev build never poses as
   a release. Releasing = move `[Unreleased]` → `[vX.Y.Z]` + date, bump
   `VERSION`, run `release-check.sh`, then `release.sh` + publish.
