---
name: pi-postinstall-patch
description: Apply and verify local compatibility patches after Pi updates. Use after `pi update` or when Node 18/Pi Copilot login fails with gzip JSON parsing, RegExp /v flag, or Undici File shim errors.
---

# Pi Postinstall Patch

This skill applies public-safe compatibility patches to the locally installed Pi packages.
It is intended as a temporary bridge until the fixes are upstreamed.

## When to use

Use this skill when:

- `pi update` or `pi` fails on Node 18 with RegExp `/v` flag errors.
- `/login github-copilot` fails with `Unexpected token '', "�` caused by raw gzip bytes.
- Undici fails with `ReferenceError: File is not defined` on Node 18.
- You just ran `pi update` and need to re-apply local compatibility patches.

## Apply patches

From the skill directory:

```bash
bash scripts/apply-pi-postinstall-patches.sh
```

The script is idempotent. It only patches files that exist and prints skipped targets.

## Verify gzip JSON helper

```bash
node --test tests/gzip-json.test.mjs
```

## Enable automatic post-update patching

Create this local config file:

```bash
cat > ~/.pi/agent/pi-postinstall-patch.json <<'JSON'
{
  "postInstall": true
}
JSON
```

The Pi wrapper at `~/.pi/agent/bin/pi` will run the patch script after `pi update pi`
when this config contains `"postInstall": true`.

Alternatively, enable for one command:

```bash
PI_POSTINSTALL_PATCH=1 pi update pi
```

## Notes

- These patches modify local package-manager output under global `node_modules`.
- A future Pi update can overwrite them; rerun this skill or enable automatic post-update patching.
- Keep real machine-specific config in `~/.pi/agent/pi-postinstall-patch.json` or `local/`, not in public docs.
