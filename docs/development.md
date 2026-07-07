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
install. Both share one private vault (`local/` symlinks into it), so flipping
between them never touches knowledge. See `system/architecture.md` for the
canonical description.

| Command                         | What it does                                                              |
| ------------------------------- | ------------------------------------------------------------------------- |
| `scripts/dev-sync-status.sh`    | Show live/dev sync status (`--doctor` for full diagnostics)               |
| `scripts/deploy-dev-to-live.sh` | Rsync the public layer dev → live (dry-run by default; `--apply` to run)  |

## Quality gates

| Gate                        | When it runs                                                             |
| --------------------------- | ------------------------------------------------------------------------ |
| `.githooks/pre-commit`      | Path-aware fast checks: privacy scan, shellcheck, addon/frontmatter checks on staged files |
| `.githooks/pre-push`        | `doctor.sh --fast` (structural + privacy checks)                         |
| `scripts/doctor.sh`         | Full health audit (`--ci` scopes to the shippable artifact; `--pi-lens-strict` for release quality) |
| `scripts/validate-install.sh` | Fresh install + idempotent re-run + doctor in a disposable sandbox      |
| `scripts/release-check.sh`  | Doctor, privacy scan, archive build, private-path check, disposable test install from the archive |

## Cutting a release

1. `scripts/bump-version.sh patch --pre` per prerelease iteration; `--release`
   to promote the cycle to a stable `X.Y.Z`.
2. Fill the generated CHANGELOG section (the release build refuses `TODO`
   placeholders) and add a RELEASE_NOTES section (used as the release body).
3. `scripts/release-check.sh` — the full gate against the actual archive.
4. `scripts/publish-gitea-release.sh [--prerelease]` — tag + archive asset on
   the Gitea dev remote (prereleases stay here).
5. Stable only: `scripts/publish-agentbrain-github.sh` force-pushes a clean
   single-commit snapshot to the public GitHub repo (no dev history), and the
   release archive is attached to a GitHub release.

The release archive is built from a `git ls-files` allowlist with a leak gate:
untracked files can never ship. Maintainer tooling (this page's scripts) is
stripped from the payload (`NONSHIP_SCRIPTS` in `scripts/release.sh`).
