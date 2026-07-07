#!/usr/bin/env bash
# Apply local compatibility patches after Pi updates.
# Public-safe: contains no secrets or machine-specific credentials.

set -euo pipefail

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

find_node_modules() {
	if [[ -n "${PI_NODE_MODULES:-}" && -d "${PI_NODE_MODULES}" ]]; then
		printf '%s\n' "${PI_NODE_MODULES}"
		return 0
	fi

	local bun_mods="$HOME/.bun/install/global/node_modules"
	if [[ -d "$bun_mods/@earendil-works/pi-coding-agent" ]]; then
		printf '%s\n' "$bun_mods"
		return 0
	fi

	local npm_mods=""
	npm_mods="$(npm root -g 2>/dev/null || true)"
	if [[ -n "$npm_mods" && -d "$npm_mods/@earendil-works/pi-coding-agent" ]]; then
		printf '%s\n' "$npm_mods"
		return 0
	fi

	# Check for nested npm installation (e.g., /opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/node_modules)
	local nested_mods=""
	nested_mods="$(npm root -g 2>/dev/null || true)"
	if [[ -n "$nested_mods" && -d "$nested_mods/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui" ]]; then
		printf '%s\n' "$nested_mods/@earendil-works/pi-coding-agent/node_modules"
		return 0
	fi

	return 1
}

patch_github_copilot_fetch_json() {
	local file="$1"
	[[ -f "$file" ]] || {
		warn "Missing pi-ai GitHub Copilot OAuth file: $file"
		return 0
	}

	python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
changed = False

if 'import { gunzipSync } from "node:zlib";' not in text:
    text = text.replace('import { getModels } from "../../models.js";\n', 'import { gunzipSync } from "node:zlib";\nimport { getModels } from "../../models.js";\n')
    changed = True

old = '''async function fetchJson(url, init) {
    const response = await fetch(url, init);
    if (!response.ok) {
        const text = await response.text();
        throw new Error(`${response.status} ${response.statusText}: ${text}`);
    }
    return response.json();
}'''
new = '''async function fetchJson(url, init) {
    const response = await fetch(url, init);
    const buffer = Buffer.from(await response.arrayBuffer());
    const body = buffer[0] === 0x1f && buffer[1] === 0x8b ? gunzipSync(buffer).toString("utf8") : buffer.toString("utf8");
    if (!response.ok) {
        throw new Error(`${response.status} ${response.statusText}: ${body}`);
    }
    return JSON.parse(body);
}'''

if old in text:
    text = text.replace(old, new)
    changed = True
elif new in text:
    pass
else:
    print(f"WARN: fetchJson block not recognized in {path}; leaving unchanged", file=sys.stderr)

if changed:
    path.write_text(text)
    print(f"patched: {path}")
else:
    print(f"ok: {path}")
PY
}

patch_pi_tui_regexes() {
	local file="$1"
	[[ -f "$file" ]] || {
		warn "Missing pi-tui utils file: $file"
		return 0
	}

	python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
orig = text

replacements = {
    r'const zeroWidthRegex = /^(?:\p{Default_Ignorable_Code_Point}|\p{Control}|\p{Mark}|\p{Surrogate})+$/v;':
        r'const zeroWidthRegex = /^(?:\p{Default_Ignorable_Code_Point}|\p{Control}|\p{Mark}|\p{Surrogate})+$/u;',
    r'const leadingNonPrintingRegex = /^[\p{Default_Ignorable_Code_Point}\p{Control}\p{Format}\p{Mark}\p{Surrogate}]+/v;':
        r'const leadingNonPrintingRegex = /^[\p{Default_Ignorable_Code_Point}\p{Control}\p{Format}\p{Mark}\p{Surrogate}]+/u;',
    r'const rgiEmojiRegex = /^\p{RGI_Emoji}$/v;':
        r'const rgiEmojiRegex = /\p{Emoji}/u;',
    r'const rgiEmojiRegex = /^\p{RGI_Emoji}$/u;':
        r'const rgiEmojiRegex = /\p{Emoji}/u;',
}

for old, new in replacements.items():
    text = text.replace(old, new)

if text != orig:
    path.write_text(text)
    print(f"patched: {path}")
else:
    print(f"ok: {path}")
PY
}

patch_undici_node18() {
	local webidl="$1"
	local cache_storage="$2"

	if [[ -f "$webidl" ]]; then
		python3 - "$webidl" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
shim = "if (typeof global.File === 'undefined') { global.File = class {} }"
if shim in text:
    print(f"ok: {path}")
    raise SystemExit

if text.startswith("'use strict'\n"):
    text = text.replace("'use strict'\n", "'use strict'\n" + shim + "\n", 1)
elif text.startswith("'use strict';\n"):
    text = text.replace("'use strict';\n", "'use strict';\n" + shim + "\n", 1)
else:
    text = shim + "\n" + text
path.write_text(text)
print(f"patched: {path}")
PY
	else
		warn "Missing Undici webidl file: $webidl"
	fi

	if [[ -f "$cache_storage" ]]; then
		python3 - "$cache_storage" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '    webidl.util.markAsUncloneable(this)'
new = '''    if (typeof webidl.util.markAsUncloneable === "function") {
      webidl.util.markAsUncloneable(this)
    }'''
if old in text:
    path.write_text(text.replace(old, new))
    print(f"patched: {path}")
elif new in text or "undici v5 expects worker_threads markAsUncloneable" in text:
    print(f"ok: {path}")
else:
    print(f"WARN: markAsUncloneable block not recognized in {path}; leaving unchanged", file=sys.stderr)
PY
	else
		warn "Missing Undici cache storage file: $cache_storage"
	fi
}

main() {
	local node_modules
	if ! node_modules="$(find_node_modules)"; then
		warn "Could not locate Pi global node_modules. Set PI_NODE_MODULES=/path/to/node_modules."
		exit 1
	fi

	log "Pi postinstall patch target: $node_modules"
	patch_github_copilot_fetch_json "$node_modules/@earendil-works/pi-ai/dist/utils/oauth/github-copilot.js"
	patch_pi_tui_regexes "$node_modules/@earendil-works/pi-tui/dist/utils.js"
	patch_undici_node18 \
		"$node_modules/undici/lib/web/webidl/index.js" \
		"$node_modules/undici/lib/web/cache/cachestorage.js"
	log "Pi postinstall patches complete."
}

main "$@"
