---
date: 2026-05-17
type: system
tags: [pi-agent, setup, public-framework]
id: fad7ed93-4907-511a-988c-63ea443b7933
---

# Pi Config

Public Pi config contains generic setup helpers only.

## Public-safe contents

- `scripts/bootstrap-macos.sh` — generic macOS bootstrap
- `agents.md` — Pi-specific entry point that points back to canonical `system/rules.md`
- `bin/pi` — optional wrapper that prompts for Pi self-update and auto-updates after a timeout
- docs that explain where local/private config belongs
- templates with placeholder values only

## Private contents

Real Pi provider extensions, model preferences, credentials, integration notes, migration notes, session logs, and machine-specific settings belong in:

```text
local/pi-config/
local/integrations/
local/security/
```

## Pi auto-update wrapper

The optional wrapper is installed to:

```text
~/.pi/agent/bin/pi
```

Put `~/.pi/agent/bin` before Bun/npm paths in `PATH`. The wrapper:

- skips checks for `pi update`, `--offline`, print/json/rpc modes, and non-interactive shells
- checks npm for a newer Pi version
- asks whether to update
- defaults to update after `PI_AUTO_UPDATE_TIMEOUT` seconds (default: 60)
- can be disabled with `PI_AUTO_UPDATE=0`

## Post-install compatibility patches

`skills/pi-postinstall-patch/` contains a versioned Agent Skill and helper script for local Pi compatibility patches after `pi update`.

Use it when a local Pi install hits known Node 18 / Copilot compatibility failures:

- GitHub Copilot login fails with `Unexpected token '', "�` from gzip-compressed JSON bytes.
- `pi-tui` fails on RegExp `/v` flags in Node 18.
- Undici expects `global.File` or `markAsUncloneable` support that is missing in the active Node runtime.

Manual run:

```bash
bash ~/.pi/agent/skills/pi-postinstall-patch/scripts/apply-pi-postinstall-patches.sh
```

Verify the gzip JSON helper:

```bash
node --test ~/.pi/agent/skills/pi-postinstall-patch/tests/gzip-json.test.mjs
```

Opt in to automatic patching after the Pi wrapper runs `pi update pi`:

```bash
cat > ~/.pi/agent/pi-postinstall-patch.json <<'JSON'
{
  "postInstall": true
}
JSON
```

Or for one command only:

```bash
PI_POSTINSTALL_PATCH=1 pi update pi
```

This mechanism is public-safe because it stores only generic patch logic. Local opt-in state stays in `~/.pi/agent/pi-postinstall-patch.json`.

## Secrets-helper

The bootstrap can optionally install a secrets-helper from a local environment variable:

```bash
export SECRETS_HELPER_REPO="https://github.com/<owner>/<repo>.git"
export SECRETS_HELPER_VERSION="vX.Y.Z"
export SECRETS_HELPER_RUN_SETUP=0
bash scripts/bootstrap-macos.sh
```

Do not commit the real private repo URL or local credentials to the public layer.
