# Capability provisioning (minimal core) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One shared `declare → detect → offer-install` path for external
prerequisites (obsidian, ollama, uv, devbox, open-webui), replacing four ad-hoc
mechanisms. Minimal core only — the catalog/`ensure`-lifecycle is deferred.

**Architecture:** `platform.sh` gains per-capability probe arms + a
`platform_capabilities()` enumerator. A new sourceable `capability-install.sh`
holds `capability_install_cmd` (OS-aware recipe) + `offer_install` (probe → opt-in
prompt → run/show → re-probe). A new manifest field `runtime_requires:` declares an
add-on's runtime deps; `check-addons` validates the tokens, `addons.sh check` warns
when missing. `setup.sh`'s obsidian block and `addons.sh` enable both call
`offer_install`.

**Tech Stack:** bash (POSIX-ish, bash 3.2 safe), existing test harness
(`scripts/test-platform.sh`), `check-addons.sh` temp-registry test pattern.

**Reference:** spec `docs/superpowers/specs/2026-08-14-capability-provisioning-design.md`.

---

### Task 1: platform.sh — capability probes + enumerator

**Files:**
- Modify: `scripts/platform.sh` (the `platform_has()` case + a new function)
- Test: `scripts/test-platform.sh`

Probe depth (minimal core): `platform_has` answers "is it **installed**" — the gate
for install-offer + check-warn. Deeper health (ollama daemon running, a model
pulled; open-webui responding) is a documented deferred refinement, NOT gated here.
So ollama = `command -v ollama` only.

- [ ] **Step 1: Write the failing test**

Add to `scripts/test-platform.sh` (after the existing `platform_has` tests):

```bash
# capability enumerator lists the known tokens
caps="$(platform_capabilities)"
case " $caps " in *" ollama "*) assert "enum has ollama" yes yes ;; *) assert "enum has ollama" no yes ;; esac
case " $caps " in *" obsidian "*) assert "enum has obsidian" yes yes ;; *) assert "enum has obsidian" no yes ;; esac
# new probes resolve (uv present-or-absent must not error)
if platform_has uv; then :; else :; fi; assert "uv probe no-error" yes yes
# unknown capability still returns absent
if platform_has totally-unknown-cap; then assert "unknown absent" yes no; else assert "unknown absent" no no; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/test-platform.sh`
Expected: FAIL — `platform_capabilities: command not found` (function undefined).

- [ ] **Step 3: Implement the probes + enumerator**

In `scripts/platform.sh`, add these arms inside the `platform_has()` `case "$1" in`
block (before the `*)` default):

```bash
		ollama)      command -v ollama >/dev/null 2>&1 ;;
		uv)          command -v uv >/dev/null 2>&1 ;;
		devbox)      command -v devbox >/dev/null 2>&1 ;;
		obsidian)    { [ "$(platform_os)" = darwin ] && [ -d "/Applications/Obsidian.app" ]; } || command -v obsidian >/dev/null 2>&1 ;;
		open-webui)  command -v curl >/dev/null 2>&1 && curl -fsS -m 2 http://localhost:8080/health >/dev/null 2>&1 ;;
```

Then add a new function after `platform_has()` (single source for the token list —
keep it in sync with the case arms above; both live in this one file):

```bash
# Enumerate the capability tokens platform_has knows. Kept adjacent to the case
# above so the two stay in sync (check-addons validates runtime_requires against
# this list). Space-separated.
platform_capabilities() {
	echo "keychain secret-tool browser node gpu display launchd systemd clipboard screenshot ollama uv devbox obsidian open-webui"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/test-platform.sh`
Expected: PASS (all assertions ok).

- [ ] **Step 5: Commit**

```bash
git add scripts/platform.sh scripts/test-platform.sh
git commit -m "feat(platform): capability probes (ollama/uv/devbox/obsidian/open-webui) + enumerator"
```

---

### Task 2: capability-install.sh — install recipes + offer_install

**Files:**
- Create: `scripts/capability-install.sh`
- Test: `scripts/test-capability-install.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/test-capability-install.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT_DIR"
. scripts/platform.sh
. scripts/capability-install.sh
fails=0
assert() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got:$2 want:$3)"; fails=$((fails+1)); fi; }

# A known capability yields a non-empty recipe on this OS (macOS has brew arms).
cmd="$(capability_install_cmd ollama)"; [ -n "$cmd" ] && assert "ollama recipe" yes yes || assert "ollama recipe" no yes
# Unknown capability yields empty.
cmd="$(capability_install_cmd nope-cap)"; [ -z "$cmd" ] && assert "unknown empty" yes yes || assert "unknown empty" no yes
# offer_install on an already-present capability returns 0 without prompting.
# (uv is present in CI images via the platform; fall back to any present token.)
present=""; for c in uv node clipboard; do platform_has "$c" && { present="$c"; break; }; done
if [ -n "$present" ]; then AGENTBRAIN_ASSUME_NO=1 offer_install "$present" >/dev/null 2>&1; assert "present->0" "$?" "0"; else echo "skip present->0 (none present)"; fi
# A missing capability with AGENTBRAIN_ASSUME_NO declines -> exit 1, no install run.
AGENTBRAIN_ASSUME_NO=1 offer_install nope-cap >/dev/null 2>&1; assert "decline->1" "$?" "1"

[ "$fails" = 0 ] && echo "test-capability-install: ok" || { echo "test-capability-install: $fails fail(s)" >&2; exit 1; }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/test-capability-install.sh`
Expected: FAIL — `capability-install.sh: No such file`.

- [ ] **Step 3: Implement `scripts/capability-install.sh`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# capability-install.sh — provision half of the capability pattern. Sourceable,
# no side-effects on source. Pairs with platform.sh (the probe half).
# Depends on platform_os/platform_has being sourced first.

# OS-aware install command for a capability, or empty if none is known here.
# A "show-only" recipe (services, pipe-to-shell) is still returned as a string;
# offer_install decides whether it may auto-run (see run-safety below).
capability_install_cmd() {
	local os; os="$(platform_os)"
	case "$1" in
		obsidian)
			if [ "$os" = darwin ]; then command -v brew >/dev/null 2>&1 && echo "brew install --cask obsidian"
			elif command -v flatpak >/dev/null 2>&1; then echo "flatpak install -y flathub md.obsidian.Obsidian"
			elif command -v snap >/dev/null 2>&1; then echo "sudo snap install obsidian --classic"; fi ;;
		ollama)
			if [ "$os" = darwin ]; then command -v brew >/dev/null 2>&1 && echo "brew install ollama"
			else echo "curl -fsSL https://ollama.com/install.sh | sh"; fi ;;
		uv)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install uv"
			else echo "curl -LsSf https://astral.sh/uv/install.sh | sh"; fi ;;
		devbox)
			echo "curl -fsSL https://get.jetify.com/devbox | bash" ;;
		open-webui)
			echo "docker run -d -p 8080:8080 --name open-webui ghcr.io/open-webui/open-webui:main" ;;
	esac
}

# True when a recipe is safe to auto-run on opt-in: a package-manager install.
# Pipe-to-shell and services are show-only (never auto-run).
_recipe_auto_runnable() {
	case "$1" in
		*"| sh"*|*"| bash"*|*"docker "*) return 1 ;;
		brew\ *|*"flatpak "*|*"snap "*) return 0 ;;
		*) return 1 ;;
	esac
}

# offer_install <capability>: probe; if present -> 0. If absent, prompt opt-in
# (N default) with the recipe + a "Later:" fallback. Auto-run only safe recipes on
# opt-in; show-only otherwise. Re-probe. Exit: 0 available, 1 declined/absent,
# 2 install ran but still absent.
# Env AGENTBRAIN_ASSUME_NO=1 forces the non-interactive decline (tests/CI).
offer_install() {
	local cap="$1" cmd
	if platform_has "$cap"; then return 0; fi
	cmd="$(capability_install_cmd "$cap")"
	if [ -z "$cmd" ]; then
		echo "  $cap not found — no install recipe for this OS. See its docs." >&2
		return 1
	fi
	if [ "${AGENTBRAIN_ASSUME_NO:-0}" = 1 ] || [ ! -t 0 ]; then
		echo "  $cap not found. Later: $cmd" >&2
		return 1
	fi
	if _recipe_auto_runnable "$cmd"; then
		printf '  Install %s now? [y/N] (later: %s) ' "$cap" "$cmd"
		read -r reply
		case "$reply" in
			[yY]*) eval "$cmd"; platform_has "$cap" && return 0 || { echo "  $cap install ran but is still absent." >&2; return 2; } ;;
			*) echo "  Skipped. Later: $cmd" >&2; return 1 ;;
		esac
	else
		# show-only (service / pipe-to-shell): never auto-run
		echo "  $cap not found. Run this yourself (not auto-run for safety):" >&2
		echo "    $cmd" >&2
		return 1
	fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/test-capability-install.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/capability-install.sh scripts/test-capability-install.sh
git commit -m "feat(capabilities): capability_install_cmd + offer_install (opt-in, show-only for services/pipe-to-shell)"
```

---

### Task 3: check-addons.sh — validate `runtime_requires:`

**Files:**
- Modify: `scripts/check-addons.sh` (near the existing `requires:` validation)

- [ ] **Step 1: Write the failing test (temp registry)**

Run this ad-hoc check (mirrors the `requires:` test pattern already used):

```bash
TMP="$(mktemp -d)"; mkdir -p "$TMP/badrt"
cat > "$TMP/badrt/manifest.md" <<'EOF'
---
id: badrt
name: Bad Runtime
privacy: local
install_method: ai-driven
author: tester
runtime_requires: not-a-capability
---
EOF
echo "# x" > "$TMP/badrt/README.md"
ADDONS_CHECK_REGISTRY="$TMP" bash scripts/check-addons.sh badrt 2>&1 | grep -i runtime_requires
rm -rf "$TMP"
```

Expected before implementation: no output (the field is ignored → no FAIL).

- [ ] **Step 2: Implement the validation**

In `scripts/check-addons.sh`, source platform.sh once near the top (after
`cd "$ROOT_DIR"`):

```bash
# shellcheck source=scripts/platform.sh
. "$ROOT_DIR/scripts/platform.sh"
```

Then, right after the existing `requires:` validation block, add:

```bash
	# Optional `runtime_requires:` — external runtime capabilities (space/comma
	# list). Each must be a known platform_has capability (typo-guard), mirroring
	# how `requires:` validates against known add-ons. Runtime is soft (addons.sh
	# check warns); this is the static gate.
	rtreq="$(field "$m" runtime_requires)"
	if [ -n "$rtreq" ]; then
		known=" $(platform_capabilities) "
		for cap in ${rtreq//,/ }; do
			case "$known" in
				*" $cap "*) : ;;
				*) echo "FAIL $m: runtime_requires '$cap' is not a known capability (see platform_capabilities)" >&2; errors=$((errors+1)) ;;
			esac
		done
	fi
```

- [ ] **Step 3: Re-run the failing test**

Run the Step-1 snippet again.
Expected: a FAIL line naming `runtime_requires 'not-a-capability'`.

- [ ] **Step 4: Verify the whole registry still passes**

Run: `bash scripts/check-addons.sh`
Expected: `check-addons: all manifests valid` (no addon declares the field yet).

- [ ] **Step 5: Commit**

```bash
git add scripts/check-addons.sh
git commit -m "feat(check-addons): validate runtime_requires: against known capabilities"
```

---

### Task 4: addons.sh check — warn on missing runtime

**Files:**
- Modify: `scripts/addons.sh` (`cmd_check`, next to the addon→addon `requires` warn)

- [ ] **Step 1: Implement the warn (source platform.sh, add the loop)**

Ensure `scripts/addons.sh` sources platform.sh (add near the top helpers if not
present):

```bash
# shellcheck source=scripts/platform.sh
. "$ROOT/scripts/platform.sh" 2>/dev/null || . "$(dirname "$0")/platform.sh"
```

In `cmd_check`, right after the existing `requires:` soft-check block, add:

```bash
		# Soft runtime check: warn when a declared runtime_requires capability is
		# not installed. Never fails (mirrors the requires: warn).
		local rt_val rt
		rt_val="$(_field "$m" runtime_requires)"
		if [ -n "$rt_val" ]; then
			for rt in ${rt_val//,/ }; do
				platform_has "$rt" || echo "warn $id needs runtime '$rt' (not installed)" >&2
			done
		fi
```

- [ ] **Step 2: Verify**

Run: `bash scripts/addons.sh check 2>&1 | head` — expect no crash; warnings only
appear once Task 6 stamps `runtime_requires:` and a runtime is absent.
Run: `bash -n scripts/addons.sh` — expect clean syntax.

- [ ] **Step 3: Commit**

```bash
git add scripts/addons.sh
git commit -m "feat(addons): addons.sh check warns on missing runtime_requires capability"
```

---

### Task 5: offer_install at enable + setup.sh obsidian refactor

**Files:**
- Modify: `scripts/addons.sh` (enable flow)
- Modify: `scripts/setup.sh` (obsidian block → `offer_install obsidian`)

> Note: this also covers the "offer ollama early during onboarding" case from the
> spec — onboarding enables its essentials via `cmd_enable`, so each essential's
> `runtime_requires:` is offered right there. No separate aggregation step needed.

- [ ] **Step 1: Wire offer_install into the enable flow**

In `scripts/addons.sh`, source `capability-install.sh` alongside platform.sh:

```bash
. "$ROOT/scripts/capability-install.sh" 2>/dev/null || . "$(dirname "$0")/capability-install.sh"
```

In the enable path (`cmd_enable`, after the add-on is marked enabled and its health
check runs), add:

```bash
	# Offer to install any missing declared runtimes for the just-enabled add-on.
	local m rt_val rt
	m="$(manifest_path "$id")"
	rt_val="$(_field "$m" runtime_requires)"
	for rt in ${rt_val//,/ }; do
		offer_install "$rt" || true   # soft: never block enable on a decline
	done
```

- [ ] **Step 2: Refactor setup.sh obsidian to offer_install**

In `scripts/setup.sh`, source the two libs near the top (after the color/helpers
are defined):

```bash
. "$(dirname "$0")/platform.sh"
. "$(dirname "$0")/capability-install.sh"
```

Replace the hardcoded `OBSIDIAN_CMD` computation + the `if … confirm "Install
Obsidian?"…` block (the lines that build `OBSIDIAN_CMD` and run it) with:

```bash
# The brain IS a ready-made Obsidian vault — offer the human viewer here.
if [ "${AGENTBRAIN_HOME}" = "$HOME" ]; then
	if platform_has obsidian; then
		echo "  Obsidian (graph + search): ${VAULT}"
	else
		offer_install obsidian || echo "  Obsidian (https://obsidian.md), then open: ${VAULT}"
	fi
fi
```

Keep the existing WSL-specific hint branch if present (WSL runs GUI apps on the
Windows side; `offer_install` returns absent there and the fallback echo covers it).

- [ ] **Step 3: Verify**

Run: `bash -n scripts/setup.sh && bash -n scripts/addons.sh` — clean syntax.
Run: `bash scripts/addons.sh check` — no crash.
Manual: on a machine with Obsidian present, `setup.sh` prints the "graph + search"
line (offer path skipped).

- [ ] **Step 4: Commit**

```bash
git add scripts/addons.sh scripts/setup.sh
git commit -m "feat(capabilities): offer_install at addon enable + obsidian via offer_install"
```

---

### Task 6: Stamp `runtime_requires:` on the ollama add-ons

**Files:**
- Modify: `system/addons/{weekly-review,youtube-digest,extract-learnings,graphify,headroom-proxy}/manifest.md`

- [ ] **Step 1: Verify each add-on's real ollama dependency**

For each id, confirm ollama is actually required (README/install.sh):

```bash
for id in weekly-review youtube-digest extract-learnings graphify headroom-proxy; do
  echo "== $id =="; grep -il ollama system/addons/$id/README.md system/addons/$id/install.sh 2>/dev/null
done
```

Only stamp the ones that truly need it. (headroom-proxy: confirm — its README
mentions ollama as a backend; include only if it genuinely calls ollama.)

- [ ] **Step 2: Add the field**

To each confirmed manifest frontmatter, add:

```yaml
runtime_requires: ollama
```

And in `system/addons/weekly-review/manifest.md`, remove `command: ollama` (ollama
is its dependency, not weekly-review's own CLI). If weekly-review has no own binary,
drop `command:` entirely; `addons.sh check` treats a command-less add-on as
"nothing to probe" (plugin/ai-driven) and the runtime warn now covers ollama.

- [ ] **Step 3: Verify**

Run: `bash scripts/check-addons.sh` → `all manifests valid` (tokens are known).
Run: `bash scripts/addons.sh check 2>&1 | grep -i ollama` → on a machine WITHOUT
ollama, expect `warn … needs runtime 'ollama'` for each enabled stamped add-on; on
this machine (ollama present) expect none.

- [ ] **Step 4: Commit**

```bash
git add system/addons/weekly-review/manifest.md system/addons/youtube-digest/manifest.md \
        system/addons/extract-learnings/manifest.md system/addons/graphify/manifest.md \
        system/addons/headroom-proxy/manifest.md
git commit -m "feat(addons): declare runtime_requires: ollama; drop weekly-review command: ollama hack"
```

---

### Task 7: Document the field

**Files:**
- Modify: `system/addons/README.md` (field table)
- Modify: `system/addons/_template/manifest.md`

- [ ] **Step 1: Add the field-table row**

In `system/addons/README.md`, after the `requires` row, add:

```
| `runtime_requires` | optional | space/comma-separated external runtime capabilities (`ollama`, `uv`, `devbox`, …); each must be a known `platform_has` capability (check-addons enforces). `addons.sh check` warns when missing; enabling an add-on offers to install them (opt-in). |
```

- [ ] **Step 2: Add the template hint**

In `system/addons/_template/manifest.md`, after the `requires:` comment block:

```
# Optional external runtime prerequisites (space/comma-separated capability
# tokens: ollama, uv, devbox, …). Each must be a known platform_has capability.
# check-addons validates; addons.sh check warns when missing; enable offers to
# install (opt-in, package-manager auto-run; services/pipe-to-shell shown only).
# runtime_requires: ollama
```

- [ ] **Step 3: Verify + commit**

Run: `bash scripts/check-addons.sh` and `bash scripts/check-readmes.sh` → pass.

```bash
git add system/addons/README.md system/addons/_template/manifest.md
git commit -m "docs(addons): document runtime_requires: field"
```

---

## Final verification (after all tasks)

- [ ] `bash scripts/test-platform.sh` — pass
- [ ] `bash scripts/test-capability-install.sh` — pass
- [ ] `bash scripts/check-addons.sh` — all manifests valid
- [ ] `bash scripts/doctor.sh --fast` — green (pre-push gate)
- [ ] On a machine without ollama: `addons.sh check` warns for the stamped add-ons;
      enabling one offers the install (opt-in). On this machine: no warns.
