# Capability provisioning — design (APPROVED, minimal core)

**Status:** approved 2026-08-14. Scope reduced from the initial full-catalog design
after self-review + a gpt-oss:120b peer-review both converged on "over-engineered
for ~4 capabilities" (archived: `local/reviews/20260814T133935-…-by-claude-autostart.md`).
This spec is the **minimal core**; the heavy catalog machinery is explicitly deferred.

## Goal

Replace four ad-hoc mechanisms for external prerequisites (obsidian hardcoded in
setup.sh, ollama in READMEs, `platform_has` probes, per-addon `install.sh`
preflights) with one small, shared **declare → detect → offer-install** path that
works for obsidian, ollama, and future capabilities (uv, devbox, open-webui).

## Approved decision

Build the **minimal core** (three small helpers + a declarative field + the
obsidian refactor). **Defer** the formal catalog file, schema, `ensure()` lifecycle
phases, and any code-generation step until ≥5 capabilities prove the need. Each
capability's probe + install-recipe lives centrally as a `case`-arm — necessary so
a multi-consumer runtime (ollama, needed by ~5 add-ons + onboarding) is defined
once, not duplicated per caller. That central per-capability arm is the minimal
core, NOT the deferred machinery.

## Architecture

Two facets per capability, each a central `case`-arm:

1. **Probe** — `scripts/platform.sh` `platform_has <cap>` (extend with `ollama`,
   `uv`, `devbox`, `obsidian`, `open-webui`) + a new `platform_capabilities()`
   that lists the known tokens (so `check-addons` can validate without drift).
   Probes differ per capability and that is intended. Depth is "**installed?**" —
   the gate for install-offers; a present binary must never be re-offered. Runtime
   health (daemon up, model pulled) is a separate, deferred, per-capability concern
   owned by the add-on's own preflight (e.g. graphify's `install.sh` checks the
   ollama daemon) — probing it in `platform_has` would make `offer_install` wrongly
   offer to install an already-present tool whose daemon is merely idle.
   - obsidian → `/Applications/Obsidian.app` OR `command -v obsidian`
   - ollama → `command -v ollama` (installed only — daemon/model health deferred)
   - uv / devbox → `command -v`
   - open-webui → service port reachable (`curl localhost:8080/health`) — it is a
     service with no CLI, so port-reachability is its "installed?" signal
2. **Provision** — new sourceable `scripts/capability-install.sh`:
   - `capability_install_cmd <cap>` → the OS-aware install command string, or empty
     if none is known for this OS. macOS→brew; Linux→apt/flatpak/curl; a service
     (open-webui) or a pipe-to-shell (ollama `curl…|sh`) returns a **show-only**
     recipe.
   - `offer_install <cap>` → probe; if absent, print an opt-in prompt (`N` default)
     with the recipe and a "Later: <cmd>" fallback; run it only when it is a safe
     package-manager command and the user opts in; **show, never auto-run** for
     services, pipe-to-shell, and privilege-escalating (`sudo`) recipes. Re-probe
     after. Exit codes: `0` available,
     `1` user declined, `2` install attempted but still absent.

## Declaration: `runtime_requires:`

New optional manifest field, mirror of `requires:` (addon→addon). Space/comma list
of capability tokens: `runtime_requires: ollama`.

- `check-addons.sh`: each token must be in `platform_capabilities()` (typo-guard,
  exactly like `requires:` validates against known add-ons).
- `addons.sh check`: for each enabled add-on, `platform_has <token>`; if absent,
  **warn** (soft, like the addon→addon `requires` warn). Never blocks.

## Invocation moments (one helper, several call-sites)

- **Core (obsidian)** — `scripts/setup.sh`: the hardcoded block becomes
  `offer_install obsidian`.
- **Add-on runtime at enable** — `scripts/addons.sh` enable flow: after enabling,
  for each `runtime_requires:` token call `offer_install <token>`.
- **Broadly-useful runtimes early** — because onboarding enables its essentials
  through the same `addons.sh` enable path, the enable-flow offer above already
  surfaces each essential's `runtime_requires:` (e.g. ollama) during onboarding —
  no separate aggregation step is needed. A dedicated pre-aggregated prompt in the
  addon-selection UI is a deferred nicety, not required for the contract.

Asymmetry (obsidian = genuine core; ollama = add-on-declared, surfaced early) is
intentional: same helper, different call-sites. Late-enabled add-ons resolve at
enable, so multi-moment is inherent — no single "resolution phase" can replace it.

## Stamping + cleanup

- `runtime_requires: ollama` on: weekly-review, youtube-digest, extract-learnings,
  graphify, headroom-proxy (verify each against its README/install.sh first).
- Drop the `command: ollama` hack from weekly-review (ollama is its dependency, not
  its own CLI; `command:` is for the add-on's own binary).
- graphify's `install.sh` ollama preflight may stay (belt-and-suspenders) or defer
  to the field — decide during implementation, don't duplicate the message.

## Docs

- `system/addons/README.md` field table + `system/addons/_template/manifest.md`:
  document `runtime_requires:`.
- `system/versioning.md` or the addons README: note the declare/detect/offer model
  and that the full catalog is deferred.

## Files to touch

- `scripts/platform.sh` — probe arms + `platform_capabilities()`.
- `scripts/capability-install.sh` — new: `capability_install_cmd` + `offer_install`.
- `scripts/check-addons.sh` — validate `runtime_requires:` tokens.
- `scripts/addons.sh` — `cmd_check` warn + enable-flow `offer_install`.
- `scripts/setup.sh` — obsidian block → `offer_install obsidian`.
- 5 add-on `manifest.md` — add `runtime_requires:`; weekly-review drops `command: ollama`.
- `system/addons/README.md`, `system/addons/_template/manifest.md` — docs.
- Tests: extend `scripts/test-platform.sh` (new probes + enumerator); a test for
  `offer_install`'s decline/show-only paths (using `echo`-style dry recipes).

## Non-goals (deferred until ≥5 capabilities earn it)

- A formal catalog file/schema as single source of truth.
- An `ensure()` lifecycle with named phases or a code-generation step.
- Version management / upgrades of external runtimes.
- Auto-running services (docker) or pipe-to-shell without an explicit opt-in that
  shows the exact command.

## Open choice for spec review

- Field name `runtime_requires:` (chosen, mirrors `requires:`) vs `capabilities:`
  (120b's suggestion). Flag now if you prefer the latter.
