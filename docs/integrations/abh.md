---
date: 2026-08-29
type: reference
tags: [integration, abh, agentbrain]
id: 3299cdae-2deb-5e12-8cc7-ec3123c06f4f
---

# ABH integration

ABH means agentBrain Harness. It is an optional consumer of the canonical
agentBrain checkout. It is not a second source of truth.

## Canonical direction

```text
agentBrain checkout
  -> ABH context provider
  -> ABH memory provider
  -> ABH filesystem skill provider
  -> ABH web profile
```

ABH reads agentBrain through its own profile/plugin mechanism. Do not copy
agentBrain skills into an independent ABH-owned source directory.

## Install

The optional agent menu installs the CLI:

```bash
npm install -g @agentbrain-harness/abh
```

The installer does not pin the package. It follows npm `latest`. The menu shows
the installed version and compares it with npm `latest` when the registry is
reachable.

## Configure

After ABH is present, run:

```bash
bash scripts/setup/setup-abh.sh
```

The setup installs and mounts:

- `@agentbrain-harness/agentbrain-context`
- `@agentbrain-harness/agentbrain-memory`
- `@agentbrain-harness/skill-filesystem`

The profile patch is:

```text
$ABH_HOME/profiles/web/cordis.patch.yml
```

The setup verifies the composed profile with:

```bash
abh --profile web --dump-config
```

A duplicate provider entry is a hard failure. The managed patch is rewritten
idempotently, while a non-managed user patch is not overwritten.

## Run

```bash
abh web
# or
brain harness
```

The latter is a thin launcher. It does not replace ABH's profile or credential
handling.

## Verify

```bash
abh --version
abh --profile web --dump-config
grep -n -E 'agentbrain-context|agentbrain-memory|skill-filesystem' \
  "${ABH_HOME:-$HOME/.abh}/profiles/web/cordis.patch.yml"
```

Then open the ABH skill catalog and confirm that agentBrain skills are visible.
Enable or disable an add-on and restart ABH to verify catalog membership follows
the canonical agentBrain state.

## Credentials

ABH owns its own provider authentication. AgentBrain does not copy or print ABH
credentials. Pi credentials are a separate concern. A plain Pi `auth.json`
warning means keychain migration is recommended; it does not mean ABH is broken.

## Troubleshooting

| Symptom | Meaning | Action |
|---|---|---|
| `pnpm not found` | ABH profile package management cannot run | Re-run prerequisites, then `pnpm --version`. |
| `duplicate loader entry id` | The profile mounted the same provider twice | Re-run `bash scripts/setup/setup-abh.sh`; inspect the managed patch. |
| Skills absent | Provider is not mounted, root is wrong, or ABH needs a restart | Run `--dump-config`, verify `AGENTBRAIN_DIR`, restart `abh web`. |
| `abh: command not found` | npm's user-scoped bin directory is not in the current shell | Start a login shell or load nvm, then run `abh --version`. |
| ABH starts but no context appears | Context is injected on the first model request, not necessarily in the static home screen | Start a session and inspect the first request/context. |
