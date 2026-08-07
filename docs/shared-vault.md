---
date: 2026-06-22
type: system
tags: [shared-vault, knowledge-layer, sync, documentation]
id: 3094b169-1430-5a3c-b536-7b535b572aa7
---

# The `shared/` knowledge layer

agentBrain has three knowledge layers:

| Layer | Path | Contents | Git |
|---|---|---|---|
| Framework | `system/`, `templates/` | code, skills, templates | the framework repo (public) |
| Private | `local/` → `~/.agentBrain/vault` | your notes, projects, learnings | its own private repo |
| **Shared** | `shared/` → `~/.agentBrain/shared` | knowledge you share with others | **its own scope repo** |

`shared/` is a top-level layer (a sibling of `local/`, not nested under it) backed by a
separate git repo, so it can have different access rights than your private vault. It is
gitignored from the framework repo, just like `local/`.

## Set up a shared scope

```bash
# Bring your own remote (Gitea / GitHub / GitLab / ssh:// / a bare path)
bash scripts/setup-shared-vault.sh --remote=ssh://host.tailnet/path/agentBrain-shared.git

# Or bootstrap a local bare repo (no server software needed; great for a tailnet)
bash scripts/setup-shared-vault.sh --bootstrap
```

The setup is host-agnostic and tiered (first match wins): an explicit `--remote`, else
`--bootstrap` (a `git init --bare` local remote + clone), else it tells you to pass one.
It does **not** install Gitea/Forgejo — for a full UI server, install one yourself and pass
its URL via `--remote`. The clone lives at `~/.agentBrain/shared` (override with `--vault=PATH`
or `AGENTBRAIN_SHARED_VAULT`). Setup is idempotent and refuses to overwrite a real `shared/`.

If `--remote` points at a public platform (github.com / gitlab.com), setup warns: **shared ≠
public** — make sure the repo's visibility is private/internal.

## Sync

```bash
bash scripts/sync-agentbrain-shared.sh "optional commit message"
```

Sync runs a **bidirectional secret-gate**, then `git fetch` + rebase, then commit + push:

1. **pre-push gate** — `check-agentbrain-shared.sh` scans the working tree; a plaintext
   secret aborts before anything is committed or pushed.
2. **incoming gate** — after fetch, `check-agentbrain-shared.sh --incoming` scans added lines
   in the incoming refs; a secret in someone else's push blocks the pull.
3. **rebase, abort on conflict** — divergent history is rebased; on conflict it aborts with
   instructions and never force-pushes.

Credentials are per-scope: by default it sources `~/bin/gitea-helper.sh` (override with
`AGENTBRAIN_SHARED_HELPER`); set `AGENTBRAIN_SHARED_NO_TOKEN=1` for a local/bare remote.

## Promote a note from private to shared

```bash
bash scripts/promote-to-shared.sh learnings/my-note      # a single note
bash scripts/promote-to-shared.sh references/some-folder # a whole folder
```

Promote moves the note(s) from `local/` to `shared/`, **regenerates the path-derived UUID5**
(the id depends on the path), logs an old→new id map to `shared/.promote-id-map` (reversible),
and runs the secret-gate. Wiki-links resolve by basename, so `[[note-name]]` links keep
working after the move.

## Privacy model

`local/` is private to you — a leaked secret stays on your disk. `shared/` is visible to
everyone with access to the scope repo, so the secret-gate runs as a **gate** (it blocks),
not a warning, in both directions. Never put real secrets in `shared/`; reference them via
the keychain/secrets-helper instead.

## Health checks

`doctor.sh` runs the shared secret-gate automatically when a `shared/` layer is configured,
and skips it cleanly when it is not — so installs without a shared layer stay green.

The original design + plan live in the author's private vault
(`local/specs/2026-06-21-shared-vault-{design,plan}.md`) — private-vault references,
not shipped with the framework.
