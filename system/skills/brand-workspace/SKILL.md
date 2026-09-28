---
name: brand-workspace
description: >-
  Organize independent brand workspaces, connect each brand to renderer adapters
  such as veneer-ui, and safely migrate existing brand assets or website concepts.
  Use for "organize my brands", "new label", "brand folder", "migrate existing
  brands", "where should the veneer theme live", or "link this theme to a brand".
  Inventories first; asks for approval before moving or retiring existing files.
argument-hint: "[status|init|link|migrate] [brand]"
user-invocable: true
resources:
  - system/skills/brand-workspace/templates/brand.json
---

# Brand workspace

A **brand** owns its identity, approved tokens and site concepts. A renderer
adapter (e.g. a veneer-ui theme) expresses that brand in one technical system.
The adapter source can live inside the brand folder or in its own private repo,
but the brand's `brand.json` records which one is current. Neutral component
libraries and client-confidential projects remain independent. Do not copy
token values into two repos and call both canonical. Do not make symlinks the
source of truth: local navigation aliases are fine, builds/releases must use
pinned artifacts.

This is a **subcommand-based skill**, not an addon or a factory. Default is
`status` (read-only). It intentionally has **no custom CLI**: filesystem tools,
`git`, `shasum`, and the existing `rnd-init`/`project-init` skills are enough.
Introduce automation only after a repeated operation has a concrete, proven
pain point. If a script becomes necessary, read the neighboring code first;
when the surrounding workflow is Bash, use Bash rather than reflexively
introducing Python. A user's paths, labels and client details never belong in this
public skill; optional local refinements go in `vault/skills/brand-workspace.private.md`.

## When to use

Use for several independent brands under a neutral workspace, or when a brand's
logo, site POCs and technical themes have ended up in different repositories.
For visual identity itself, use a brand-guidelines workflow; for a genuinely
independent release factory, use factory-builder. Never infer client ownership
from a brand name; verify the public/private boundary before copying anything.

## Procedure

### `status` — map the real state, no changes

1. Ask for the workspace root **only if it cannot be established from context**.
   Read existing AGENTS.md in every repository you will touch. Inspect real
   folders and git status, including untracked/ignored items (`git status
   --short --untracked-files=all`, `git status --ignored --short` where useful).
2. Inventory each asset's path, owner, current purpose (active/concept/legacy),
   git status, inbound links, outbound file/URL assets, and rights. Identify
   separate product repos and private client repos. A three-page site is one
   concept, not three independent brands. A design-system showcase is not a
   production site.
3. Show a **current path → proposed destination** table. Mark unknowns and
   conflicts in canonical tokens (never silently declare one old design-system
   file the truth). Note every tracked repo's history and current dirty state.
   Do not move files during inventory.

### `init <brand>` — scaffold one independent brand

After the owner chooses the *neutral workspace* and stable brand id, create
only the folders actually needed:

```text
<brand-workspace>/
  README.md                         # links to existing repos; no source duplication
  brands/<brand-id>/
    brand.json                      # identity + source of truth + adapter references
    brand/                          # approved brand values and assets
    website/concepts/<concept-id>/  # each entire concept, incl. sibling pages
    R&D/decisions/                  # rationale/evidence
    R&D/legacy/                     # only versions actually decommissioned
    adapters/veneer/                # if this brand owns the theme source here
```

Use `mkdir -p` with quoted paths only after checking for collisions and
symlinks. For a repo's R&D scaffold, prefer existing `rnd-init`; for repo-local
git identity use `project-init`. Don't create empty directories for possible
future features. Start `brand.json` from `templates/brand.json` and fill only
verified fields; leave unknown values `null`. Re-running `init` is a no-op for
folders and manifests that already match; never overwrite an existing brand.
A company can have multiple sibling brands; do not nest other labels beneath
its company-name brand solely because it owns them.

### `link <brand>` — associate a technical brand layer

Read `brand.json`, the adapter repo and its package metadata. Record the
adapter source (relative path where possible; otherwise a repo identity/URL),
renderer kind (`veneer`, `flux`, etc.), theme scope, CSS entry point, release
package/version (only when one actually exists), and status (`concept` or
`released`). The brand id, CSS scope and npm package name are **different
identifiers**; do not infer one from another. A brand can have several adapters.
If the theme lives in the brand folder, its code is under `adapters/veneer/`;
if a client-owned rich instance has its own repo, link it without moving it.
For example, once verified, one `adapters` entry may look like:

```json
{"kind":"veneer","source":"adapters/veneer/","scope":"sample","css":"theme.css","package":null,"version":null,"status":"concept"}
```

A separate index of veneer themes can **discover** brands; it must not own a
second copy of their values. The app still pins the built CSS/package itself;
`brand.json` is a map, not a runtime loader. A page builder additionally needs
its own component manifest and bundle: linkage alone does not prove it is
loadable there.

Before marking `released`, check: sheet exists; scope is declared once;
`--vnr-*` mapping obeys veneer theme rules; font/image licenses, light/dark,
contrast and reduced motion were tested; consumer pin + rollback exist.

### `migrate <brand>` — plan, obtain approval, copy, verify, retire later

Choose the scenario **before** choosing a file operation:

| Existing state | Safe migration path | Don't do |
|---|---|---|
| Untracked multi-page site POC inside a design-system repo | Copy **all sibling pages and assets together** to one `website/concepts/<id>/`, verify internal links and browser render; stage/commit the source or preserve a hash manifest before retiring it | Move one page or treat the POC as a shipped site |
| Standalone brand repo with `.git` history | Keep repo independent and link it in `brand.json`; if a physical relocation is approved, move the **entire repo** with history and check remotes/worktrees and consumer paths | Flatten into a new directory or copy `.git` as ordinary content |
| Existing veneer theme in a central collection | Choose one canonical brand-value source, then copy the adapter **source** into the owning brand (or link a private separate repo); verify scope, core compatibility, license, tests and pinned consumers before deprecating the old sheet | Maintain two writable token sources or replace a consumer's runtime with a symlink |
| Live website/app using an old brand folder | Keep deployment untouched; archive the exact deployed release, rehearse redirect/build/cutover and rollback with data safety before switching consumers | Assume a source-folder move also migrates runtime state |
| Folder containing multiple brands or client assets | Inventory ownership and confidentiality per file; split into separate brand folders/spaces with explicit approved file lists | Sweep everything into a public company folder |
| Conflicting old and new token/design concepts | Preserve each version as evidence; ask which is canonical and label concept vs approved vs retired | Merge values by filename or silently overwrite |
| Symlinked source, ignored assets or external font/video | Resolve provenance and destinations manually; list exactly what is intentionally imported, review rights and runtime dependencies | Recursively follow a symlink or claim a broken reference is migrated |

1. Make a durable migration plan in the brand's `R&D/decisions/`: enumerate
   **exact** files (including untracked and supporting assets), SHA-256 hashes
   (`shasum -a 256`), repo HEAD and dirty status, old/new paths, links to
   update, license/privacy boundaries, test command and rollback route. Check
   ownership of any existing destination. If the source is a git repo, do not
   flatten or discard its history; keep the repo and link it, or plan an
   explicitly approved git-preserving move.
2. **Stop and present the plan for explicit owner approval**. An earlier
   statement like "I'd like things tidied" does not authorize deleting or
   moving unrelated work. The owner chooses the canonical token source and
   resolves ambiguities. Mark the site POC as a concept, not shipped brand UI.
3. After approval, **copy** just the approved files into a new staging folder
   (e.g. `rsync -a -- <source>/ <staging>/` for one already-isolated concept),
   never over an occupied target. Do not follow symlinks. Verify exact file
   hashes and sibling links; move the verified staging folder into the empty
   destination. Record the source revision and the migration in R&D. This is
   a verified copy, not yet an assertion the source was physically moved.
4. Render-check desktop/mobile, theme and keyboard; run tests where present,
   check external fonts/video/rights, update inbound paths and package/build
   references, and test a clean consumer. **Only then**, with separate owner
   approval, archive the old location under R&D/legacy (or preserve the git
   tag) and retire the old path. Don't silently delete originals or make a
   symlink that disguises a broken import. The rollback is always possible
   from the original until retirement, then from the verified archive/tag.

## Pitfalls

- Never put confidential client assets into a shared or public brand repo.
- Don't make a rich branded component package into a plain CSS file; only
  migrate the actual owner-controlled source if its release boundary permits.
- A symlink may aid navigation locally, but does not travel with a release.
- A static website POC belongs with its sibling pages in a site concept folder,
  not among design-system token examples. Concept is not synonymous with legacy.
- Migrating a live app is separate from organizing a brand; safeguard user
  data/progress and follow its own release plan first.

## Verification

- Inspect the generated manifest against `templates/brand.json` and verify no
  values or release statuses were invented.
- Check original and copied files with `shasum -a 256`; check git history,
  modified/untracked state, links, and rights before moving/retiring sources.
- If the skill itself changes: run `bash scripts/checks/check-frontmatter.sh`,
  `bash scripts/privacy-scan.sh`, sync skill links with the standard setup
  scripts, and verify `check-skill-links.sh`.
