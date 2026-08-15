---
date: 2026-05-19
type: system
tags: [pi-agent, postinstall, patch, node18]
id: 7eaf731b-a56d-5742-9cbc-ffcba87cfa4d
---

# Pi Postinstall Patch Skill

Versioned compatibility patch skill for local Pi installations.

## Why this exists

Some Pi versions can break on older Node runtimes or specific Undici/fetch behavior:

- GitHub Copilot OAuth JSON can arrive as gzip bytes and fail with `Unexpected token '', "�`.
- `pi-tui` may use RegExp `/v` flags that Node 18 cannot parse.
- Undici can expect a global `File` constructor or `markAsUncloneable` support not present in older Node runtimes.

This skill keeps the patch mechanism in the public, versioned Pi config layer while the actual local opt-in config stays private/local.

## Use

```bash
bash scripts/apply-pi-postinstall-patches.sh
node --test tests/gzip-json.test.mjs
```

From Pi, load the skill with:

```text
/skill:pi-postinstall-patch
```

Then follow the instructions in `SKILL.md`.

## Automatic post-update opt-in

Create a local config file:

```bash
cat > ~/.pi/agent/pi-postinstall-patch.json <<'JSON'
{
  "postInstall": true
}
JSON
```

The Pi wrapper runs the patch script after `pi update pi` when this flag is true.

You can also enable one command only:

```bash
PI_POSTINSTALL_PATCH=1 pi update pi
```

## Versioning

Patch changes should be made in `scripts/apply-pi-postinstall-patches.sh` with a short changelog entry here.

### v0.1.0

- Add GitHub Copilot gzip JSON parsing patch.
- Add Node 18 compatible `pi-tui` regex replacements.
- Add Undici Node 18 `File` and `markAsUncloneable` compatibility patches.
- Add gzip JSON unit test.
