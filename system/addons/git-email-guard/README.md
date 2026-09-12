---
date: 2026-06-05
type: addon
tags: [addon, git, privacy, security, email, hook]
status: active
id: 6baf4a5e-1a11-5df6-933d-89dbb630cd21
---

# git-email-guard

Pre-commit hook that blocks commits when `git config user.email` is not in a per-repo whitelist. Prevents accidental personal-email leakage to public repos (the kind that's only fixable later via `git filter-repo` and a destructive force-push).

## Install on a repo

```bash
# With whitelist seeded inline:
bash system/addons/git-email-guard/install.sh ~/Developer/my-project dev@example.com

# Or install into existing repo (will use existing .gitemail-allowed):
cd ~/Developer/my-project
bash ~/agentBrain/system/addons/git-email-guard/install.sh .
```

The install script:
- Symlinks `hooks/pre-commit` into the repo's `.git/hooks/pre-commit` (so addon updates propagate automatically)
- Backs up any pre-existing pre-commit hook to `pre-commit.bak.<timestamp>`
- Optionally seeds `.gitemail-allowed` if you pass email args and the file doesn't yet exist

## Whitelist file

`.gitemail-allowed` (committed to the repo, one email per line):

```
# Allowed author emails for this repo
dev@example.com
business@example.com  # uncomment if needed
```

Empty lines and `# comments` are ignored. The file lives in the repo root, so collaborators inherit the whitelist on clone.

## Bypass

For an exceptional commit (e.g. cherry-pick of someone else's work):

```bash
GIT_EMAIL_GUARD=skip git commit -m "..."
```

## Uninstall

```bash
bash system/addons/git-email-guard/uninstall.sh ~/Developer/my-project
```

Restores any backed-up pre-commit hook.

## Good fits

- Personal/private monorepos that publish to a public mirror (Lockpad → GitHub)
- Multi-account setups where one wrong global config can leak personal email
- Any project where the author wants commits attributable only to a specific business identity

## Tests

```bash
bash system/addons/git-email-guard/tests/test-git-email-guard.sh
```

Hermetic: spins up throwaway git repos in a tmpdir and runs the hook directly (no real commits, no network). Covers whitelist match/miss, the `$GIT_EMAIL_ALLOWED` env fallback, the `GIT_EMAIL_GUARD=skip` bypass, empty `user.email`, and the no-whitelist allow-with-warning path. Wired via the manifest `test:` field, so `bash scripts/addons.sh test git-email-guard` runs it when `git` is on PATH.

## Privacy

Privacy tier: `local-only`. The hook runs entirely client-side, reads only `git config user.email` and `.gitemail-allowed`. No network, no telemetry.

## Why this exists

On 2026-06-05, 23 commits in `lockpad`'s public history were found to contain a personal Gmail address. Root cause: `user.email` had been set globally years prior; lockpad never overrode it per-repo. The exposure was fixed by `git filter-repo` + force-push, but the destructive cleanup is invasive and not always possible. This hook makes that exposure impossible to begin with: every commit is validated *before* it lands in the repo.

See also `vault/learnings/Git-Email-Leak-Prevention.md`.
