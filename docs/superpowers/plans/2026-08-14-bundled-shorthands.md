# Bundled + self-declared shorthands — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship default shorthands with agentBrain by letting each addon declare an optional `shorthand:` in its manifest; the shorthand addon merges enabled addons' shorthands as a third layer beneath the user's own.

**Architecture:** `bin/shorthand`'s `merged()` gains a third source — an "addon-derived" layer assembled from enabled addon manifests — inserted with precedence `local > core (shorthand.system.json) > addon-derived`. Terms only (no shell aliases). `check-addons.sh` validates the new optional field.

**Tech Stack:** Bun + TypeScript (the addon CLI), Bash (check-addons), Keep a Changelog / SemVer.

---

## File Structure

- `system/addons/shorthand/bin/shorthand` — add `addonLayer()` + a frontmatter reader; wire into `merged()`. (Modify)
- `system/addons/shorthand/tests/test-shorthand.sh` — add addon-layer tests. (Modify)
- `scripts/check-addons.sh` — validate optional `shorthand:` (format + cross-addon uniqueness WARN). (Modify)
- `system/addons/_template/manifest.md` — document the optional field. (Modify)
- `system/addons/README.md` — document the three-layer model in the manifest schema. (Modify)
- `system/addons/youtube-digest/manifest.md` — stamp `shorthand: ytd`. (Modify)
- `system/addons/shorthand/manifest.md` + `CHANGELOG.md` — bump 0.3.1 → 0.4.0. (Modify)

Core convention (unchanged): `shorthand.system.json` holds `ab`, `moc`. Local layer (`local/addons/shorthand/shorthand.json`) is the user's own.

---

## Task 1: Addon-derived layer in `bin/shorthand`

**Files:**
- Modify: `system/addons/shorthand/bin/shorthand` (imports line 19; `merged()` at 54-59)
- Test: `system/addons/shorthand/tests/test-shorthand.sh`

- [ ] **Step 1: Write the failing test**

Append to `system/addons/shorthand/tests/test-shorthand.sh`, just before the final summary line (the `test-shorthand:` echo). It builds a fixture addon under the fixture BRAIN and asserts the derived shorthand surfaces, respects enabled-state, loses to local, and that core beats an addon.

```bash
# --- addon-derived layer ---
mkdir -p "$FIX/system/addons/zeta-addon" "$FIX/local/addons/zeta-addon"
cat > "$FIX/system/addons/zeta-addon/manifest.md" <<'MAN'
---
id: zeta-addon
name: Zeta Addon
shorthand: zt
privacy: local
install_method: self
author: frontmatters
---
MAN
: > "$FIX/local/addons/zeta-addon/enabled"      # enabled
run apply >/dev/null
grep -q '| `:zt` | Zeta Addon | term | system |' "$NOTE" && ok "addon-derived shorthand appears" || no "addon-derived shorthand appears"

# disabled addon contributes nothing
rm -f "$FIX/local/addons/zeta-addon/enabled"
run apply >/dev/null
grep -q ':zt' "$NOTE" && no "disabled addon shorthand removed" || ok "disabled addon shorthand removed"

# core beats an addon that declares a core short
: > "$FIX/local/addons/zeta-addon/enabled"
sed -i.bak 's/^shorthand: zt/shorthand: ab/' "$FIX/system/addons/zeta-addon/manifest.md"; rm -f "$FIX/system/addons/zeta-addon/manifest.md.bak"
run apply >/dev/null
grep -q '| `:ab` | agentBrain | term | system |' "$NOTE" && ok "core beats addon on collision" || no "core beats addon on collision"

# local beats an addon-derived short
sed -i.bak 's/^shorthand: ab/shorthand: mine/' "$FIX/system/addons/zeta-addon/manifest.md"; rm -f "$FIX/system/addons/zeta-addon/manifest.md.bak"
run add mine "my own thing" >/dev/null
grep -q '| `:mine` | my own thing | term | local |' "$NOTE" && ok "local beats addon-derived" || no "local beats addon-derived"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd system/addons/shorthand && bun ../../../scripts/../system/addons/shorthand/bin/shorthand >/dev/null 2>&1; bash tests/test-shorthand.sh`
(Or from repo root: `bash system/addons/shorthand/tests/test-shorthand.sh`)
Expected: FAIL on "addon-derived shorthand appears" (the derived layer does not exist yet).

- [ ] **Step 3: Add `readdirSync` to the fs import**

In `system/addons/shorthand/bin/shorthand`, line 19, change:

```ts
import { existsSync, readFileSync, writeFileSync, mkdirSync, copyFileSync } from "fs";
```

to:

```ts
import { existsSync, readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync } from "fs";
```

- [ ] **Step 4: Add the addon-derived layer function**

In `system/addons/shorthand/bin/shorthand`, immediately AFTER the `merged()` function (after line 59), insert:

```ts
// --- addon-derived layer -------------------------------------------------
// Enabled addons may declare `shorthand: <short>` in their manifest; it becomes a
// term (short -> the addon's `name`). Bundled + enabled-gated, lowest precedence.
const SYS_ADDONS = join(BRAIN, "system", "addons");
const LOCAL_ADDONS = join(BRAIN, "local", "addons");

function manifestField(mpath: string, key: string): string | undefined {
  if (!existsSync(mpath)) return undefined;
  const fm = readFileSync(mpath, "utf8").match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return undefined;
  const m = fm[1].match(new RegExp(`^${key}:\\s*(.+)$`, "m"));
  return m ? m[1].trim() : undefined;
}

function addonIds(): string[] {
  const ids = new Set<string>();
  for (const root of [SYS_ADDONS, LOCAL_ADDONS]) {
    if (!existsSync(root)) continue;
    for (const e of readdirSync(root, { withFileTypes: true }))
      if (e.isDirectory() && e.name !== "_template") ids.add(e.name);
  }
  return [...ids].sort();                       // alphabetical: first-declaring addon wins
}

function addonLayer(): any[] {
  const claimed = new Map<string, any>();
  for (const id of addonIds()) {
    if (!existsSync(join(LOCAL_ADDONS, id, "enabled"))) continue;   // enabled-gated
    const local = join(LOCAL_ADDONS, id, "manifest.md");
    const mpath = existsSync(local) ? local : join(SYS_ADDONS, id, "manifest.md");
    const short = manifestField(mpath, "shorthand");
    if (!short || !/^[a-z0-9-]+$/.test(short)) continue;            // absent/invalid -> skip
    if (claimed.has(short)) continue;                              // first-alpha addon wins
    claimed.set(short, { short, full: manifestField(mpath, "name") || id, kind: "term", layer: "system" });
  }
  return [...claimed.values()];
}
```

- [ ] **Step 5: Wire the addon layer into `merged()`**

Replace the body of `merged()` (lines 54-59) with:

```ts
// merged view. Precedence low→high: addon-derived, then core (system.json), then local.
function merged(): any[] {
  const m = new Map<string, any>();
  for (const s of addonLayer()) m.set(s.short, s);
  for (const s of loadLayer(SYS)) m.set(s.short, { ...s, layer: "system" });
  for (const s of loadLayer(SRC)) m.set(s.short, { ...s, layer: "local" });
  return [...m.values()].sort((a, b) => a.short.localeCompare(b.short));
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash system/addons/shorthand/tests/test-shorthand.sh`
Expected: PASS — all existing tests plus the 4 new addon-layer assertions ("addon-derived shorthand appears", "disabled addon shorthand removed", "core beats addon on collision", "local beats addon-derived").

- [ ] **Step 7: Commit**

```bash
git add system/addons/shorthand/bin/shorthand system/addons/shorthand/tests/test-shorthand.sh
git commit -m "feat(shorthand): addon-derived layer from enabled manifests"
```

---

## Task 2: Validate `shorthand:` in `check-addons.sh`

**Files:**
- Modify: `scripts/check-addons.sh` (inside the per-manifest loop, after the README + required-field checks)

- [ ] **Step 1: Add the validation block**

`check-addons.sh` iterates manifests with `field "$m" <key>` available and an `errors` counter. Inside the `for m in "$REGISTRY"/*/manifest.md` loop, after the required-field checks and before the loop closes, add (uses the existing `field` helper and `id`/`dir_id` vars already computed in the loop):

```bash
	# Optional `shorthand:` — lowercase handle, unique across addons.
	sh="$(field "$m" shorthand)"
	if [ -n "$sh" ]; then
		case "$sh" in
			*[!a-z0-9-]*|"") echo "FAIL $m: shorthand '$sh' must be lowercase [a-z0-9-]" >&2; errors=$((errors+1)) ;;
		esac
		if [ -n "${SEEN_SHORTS-}" ] && printf '%s\n' "$SEEN_SHORTS" | grep -qx "$sh"; then
			echo "WARN $m: shorthand '$sh' already declared by another addon (alphabetically-first id wins)" >&2
		fi
		SEEN_SHORTS="$(printf '%s\n%s' "${SEEN_SHORTS-}" "$sh")"
	fi
```

Note: initialise `SEEN_SHORTS=""` once, just before the `for m in "$REGISTRY"/*/manifest.md` loop starts.

- [ ] **Step 2: Verify a bad value fails and a good value passes**

Run:
```bash
# temp bad manifest
mkdir -p /tmp/ca/BadCaps && printf 'id: badcaps\nname: X\nprivacy: local\ninstall_method: self\nauthor: frontmatters\nshorthand: BadCaps\n' > /tmp/ca/BadCaps/manifest.md
printf '# X\n' >> /tmp/ca/BadCaps/manifest.md
ADDONS_CHECK_REGISTRY=/tmp/ca bash scripts/check-addons.sh; echo "exit=$?"
```
Expected: `FAIL .../manifest.md: shorthand 'BadCaps' must be lowercase` and non-zero exit.

Then confirm the real registry still passes:
Run: `bash scripts/check-addons.sh`
Expected: `check-addons: all manifests valid`.

- [ ] **Step 3: Commit**

```bash
git add scripts/check-addons.sh
git commit -m "feat(addons): validate optional shorthand: manifest field"
```

---

## Task 3: Docs, stamp youtube-digest, version bump

**Files:**
- Modify: `system/addons/_template/manifest.md`
- Modify: `system/addons/README.md`
- Modify: `system/addons/youtube-digest/manifest.md`
- Modify: `system/addons/shorthand/manifest.md`, `system/addons/shorthand/CHANGELOG.md`

- [ ] **Step 1: Document the field in the template**

In `system/addons/_template/manifest.md`, after the `author:` block, add:

```
# Optional agentBrain shorthand for this addon (lowercase). While the addon is
# enabled, the shorthand addon surfaces it as a term (`<short>` -> this addon's
# name) in the shared glossary. Core (ab, moc) and the user's local layer win.
# shorthand: your-short
```

- [ ] **Step 2: Document the field + layering in the addons README**

In `system/addons/README.md`, in the Manifest schema table, add a row after the `author`/`upstream` rows:

```
| `shorthand` | optional | lowercase handle; while the addon is **enabled**, surfaces as a glossary term (`<short>` → the addon's name). Precedence: user-local > core (`ab`,`moc`) > addon-derived |
```

- [ ] **Step 3: Stamp youtube-digest**

In `system/addons/youtube-digest/manifest.md`, add under `author:`:

```
shorthand: ytd
```

- [ ] **Step 4: Verify ytd surfaces when youtube-digest is enabled**

Run (youtube-digest is enabled in this vault):
```bash
bun system/addons/shorthand/bin/shorthand apply >/dev/null
grep -E '\| `:ytd` \| YouTube Digest \| term \| system \|' ~/agentBrain/local/preferences/personal/shorthand.md
```
Expected: the `:ytd` row prints (unless a local `ytd` overrides it — then it shows `local`, which is also correct).

- [ ] **Step 5: Bump shorthand to 0.4.0 + changelog**

In `system/addons/shorthand/manifest.md` change `version: 0.3.1` → `version: 0.4.0`.

In `system/addons/shorthand/CHANGELOG.md`, under `## [Unreleased]`, add a new section:

```
## [0.4.0] - 2026-08-14

### Added

- **Addon-derived shorthands**: an addon may declare `shorthand: <short>` in its
  manifest; while enabled it surfaces as a glossary term (`<short>` → the addon's
  name). Third layer beneath core (`ab`, `moc`) and the user's local layer, which
  always wins. Terms only — no shell aliases are written for bundled shorthands.
```

- [ ] **Step 6: Full verification + commit**

Run:
```bash
bash scripts/check-addons.sh                         # all manifests valid (ytd stamped)
bash system/addons/shorthand/tests/test-shorthand.sh # 28+ pass
bash scripts/check-shorthand.sh                      # glossary in sync
```
Expected: all green.

```bash
git add system/addons/_template/manifest.md system/addons/README.md \
  system/addons/youtube-digest/manifest.md \
  system/addons/shorthand/manifest.md system/addons/shorthand/CHANGELOG.md
git commit -m "feat(shorthand): document + adopt addon-derived shorthands (0.4.0)"
```

---

## Self-Review

**Spec coverage:**
- Manifest field `shorthand:` → Task 3 (docs) + Task 1 (consumption) + Task 2 (validation). ✓
- Three sources + precedence local > core > addon-derived → Task 1 `merged()`. ✓
- Enabled-gated → Task 1 `addonLayer()` (checks `local/addons/<id>/enabled`). ✓
- Addon-vs-addon deterministic (id-alpha) → Task 1 `addonIds()` sort + first-wins. ✓
- Core cannot be hijacked → Task 1 order (core set after addon). ✓ (test: "core beats addon").
- Terms only, no shell writes → `addonLayer()` emits `kind: "term"`; `renderAliases()` already only aliases local cmd entries — untouched. ✓
- Validation (format + uniqueness WARN) → Task 2. ✓
- Tests → Task 1 Step 1. ✓
- Rollout/version → Task 3 Step 5. ✓

**Placeholder scan:** No TBD/TODO; every code + command step is concrete. ✓

**Type consistency:** entry shape `{short, full, kind, layer, target?}` matches the existing `merged()`/`renderNote()` usage; `addonLayer()` emits the same shape. `manifestField`/`addonIds`/`addonLayer` names are used consistently. ✓
