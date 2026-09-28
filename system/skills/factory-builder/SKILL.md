---
name: factory-builder
version: 0.4.1
description: >-
  Scaffold, audit and mature a standalone tool factory. Use when a tool needs
  dev/next/live lanes, R&D, releases, clean-install validation, promotion,
  rollback, consumer packaging, or a release gate. Also use when asking which
  projects should become factories.
---

# factory-builder: make active tools releasable without losing the live tool

Use a factory for an actively used standalone CLI, service, integration runtime
or product with its own release lifecycle. Do not create one for every
experiment, client project, library or AgentBrain addon.

## Minimum factory

```text
<tool>-factory/
├── <tool>-dev/
├── <tool>-next/
├── <tool>/              # validated live lane
├── releases/
├── R&D/
├── factory.json
├── README.md
├── VERSION
└── CHANGELOG.md
```

`R&D/` must use the shared layout from `rnd-init`:
`dashboards/`, `decisions/`, `captures/`, `renders/`, `logs/` and
`experiments/`. Quote `R&D` in shell commands.

## Retiring a factory

A factory that another factory succeeds is archived, not deleted and not left
beside the active ones:

- It moves to the successor's `R&D/legacy/<name>/`. Standalone material that is
  only kept for reference goes to `R&D/reference/`. Both directories come from
  `layout.json`.
- The successor records it as `"legacy_factory": "R&D/legacy/<name>"` in its
  `factory.json`. The registry scans `<root>/*/factory.json`, so an archived
  factory drops out of it by itself; a symlink at the old place would keep it in.
- Before the move: a `git bundle --all` and a tarball of the old factory, kept
  beside the archive.
- **The successor must own its git history first.** When the successor's lanes
  are worktrees of the old factory's repository, move that repository into the
  successor's dev lane (`.git` plus that worktree's HEAD, index and reflog, then
  `git worktree repair`) before archiving. Otherwise the archive holds the
  successor's history. Afterwards remove the old factory's worktree link files
  and run `git worktree prune`.
- Update every reference to the old path: the successor's README, skills and
  addons that name it, and the notes that describe its current location.
  History (logs, decisions, gaplogs) keeps the old path.

`factory-doctor.sh` fails when `legacy_factory` does not exist or when a lane
keeps its git history inside it, and notes a legacy factory outside
`R&D/legacy/` or still beside the others in the registry root.

`legacy_checkout` is a different thing: an older standalone checkout still in
use as an external lane (`lanePolicy`). It is active and stays where it is.

## Factory profiles

The registry and doctor support two explicit layouts through a shared normalizer:

- `standard` (default): `lanes.dev/next/live`, factory-local `releases/`, and the
  full `R&D/` layout. Existing factory configs need no change.
- `composite`: set `"profile": "composite"`; read the primary lanes from
  `framework.dev/next/live` and the archive directory from `releases.root`.
  This is for a factory with additional product lines that it measures itself
  through `obeya.stations`. Its `R&D/` directory is required, but the standard
  subdirectories and single-product `commands.test`/`distribution` warnings
  are not imposed on it.

An unknown profile fails closed. Both tools report the same normalized lane
paths and archive root; profile selection does not change release or promotion
scripts. Keep the actual station measurements in the factory's own board.

## Andon and obeya

Every factory keeps an **andon** and shows an **obeya**.

- **Andon** (`R&D/dashboards/andon.md` by default): the signal board above the
  line. Only what is stopped or waiting, one line per pulled cord, each with
  `since YYYY-MM-DD` and what it waits on. Kept by hand; a resolved cord is
  removed and recorded in the log. Plans do not belong here.
- **Obeya** (`R&D/dashboards/obeya.md` by default): the one place to look. It
  is generated, never edited, from four sources read fresh: the measured
  stations (the lanes, or the JSON of the factory's own board), the andon, the
  factory's open backlog items by priority and rank, and the newest log entries.

`factory-obeya.sh --init` creates the andon; `--write` regenerates the obeya.
`factory-doctor.sh` notes a missing andon, stale cords and undated cords;
`factory-registry.sh` shows every factory's andon and next step in one table.
Every path, heading, threshold and count comes from `"obeya"` in
`factory.json` over `obeya.defaults.json`:

```json
"obeya": {
  "backlog": "~/agentBrain/vault/backlog",
  "project": "my-factory",
  "log": "~/agentBrain/vault/projects/my-factory/index.md",
  "stations": "bash tools/board.sh --json"
}
```

## Commands

Run these from a factory root, or set `FACTORY_PATH`:

```bash
bash ~/agentBrain/system/skills/factory-builder/bin/factory-doctor.sh --factory .
bash ~/agentBrain/system/skills/factory-builder/bin/factory-check.sh
bash ~/agentBrain/system/skills/factory-builder/bin/factory-test.sh
bash ~/agentBrain/system/skills/factory-builder/bin/factory-release.sh
bash ~/agentBrain/system/skills/factory-builder/bin/factory-promote.sh
bash ~/agentBrain/system/skills/factory-builder/bin/factory-rollback.sh --confirm
bash ~/agentBrain/system/skills/factory-builder/bin/factory-registry.sh
bash ~/agentBrain/system/skills/factory-builder/bin/factory-inventory.sh
bash ~/agentBrain/system/skills/factory-builder/bin/factory-obeya.sh --write
```

`factory-doctor.sh` is the read-only consistency gate. `factory-registry.sh` scans `~/Developer/*/factory.json` and writes a machine-readable registry plus a Markdown dashboard. `factory-inventory.sh` scans project-like directories and writes evidence for deciding which projects should become factories. Its heuristics are discovery hints only; it never registers a factory automatically. `factory-check.sh` is
strict and blocks dirty/incomplete release candidates. Promotion and rollback
are deliberately separate commands because they change lane state.

## Lane placement policy

A lane is a lifecycle role, not a required filesystem location. The factory
control plane must declare `dev`, `next` and `live`, but an existing production
checkout may remain outside the factory during safe adoption. This is an
explicit compatibility state, not an error to fix by copying files.

- New factories should prefer factory-local worktrees.
- Existing projects must not be moved or overwritten merely for layout
  consistency.
- An external lane must be recorded with its path and reason in `factory.json`.
- The `live` lane is a release/source baseline; the installed or deployed
  runtime is a separate production artifact.
- Normal changes flow `dev -> next -> live`. Before testing or promoting, `factory-lane-origin.sh` requires live's HEAD to be reachable from next and next's HEAD from dev. A next-only commit must reach dev; a live-only hotfix must reach next **and** dev. This checks ancestry, not where a human originally typed the change.

Example:

```json
{
  "lanes": { "live": "~/projects/example-tool" },
  "lanePolicy": { "live": "external-legacy-checkout" }
}
```

## Mature factory contract

A mature factory also has:

- `factory-check.sh`: structure, JSON, clean lanes and policy checks;
- `factory-test.sh`: unit, type, privacy and smoke gates;
- `factory-release.sh`: pinned archive, checksum, manifest and provenance;
- `factory-promote.sh`: next to live only after gates pass;
- `factory-rollback.sh`: restore the previous live release;
- clean-install tests with no private paths, secrets or symlinks;
- explicit support/runtime matrix;
- install, uninstall, update and health checks;
- backlog and gaplog in agentBrain with evidence links.

## Distribution: write down how a user gets the tool

Lanes and `releases/` say how the tool is built. They do not say how anyone else gets it.
Record that in `factory.json`:

```json
"distribution": {
  "format":     "what an artifact is (npm tarball, tar.gz of a lane, a binary)",
  "channel":    "where it lives (releases/ in this factory, a registry, a site)",
  "install":    "the one command a user runs, and what it checks first",
  "uninstall":  "the one command, and what it deliberately leaves alone",
  "maintainer": "how the maintainer's own machine runs the tool (usually the live lane)",
  "versioning": "the steps from commits to a tag (e.g. bump in dev, tag, promote)",
  "release":    "the command that builds and proves an artifact"
},
"commands": { "release": "...", "release_check": "..." }
```

`factory-doctor.sh` notes a factory without it. These rules apply to every
standalone tool:

- **Release only what live is, on its tag.** The release script refuses unless live sits
  exactly on `vX.Y.Z` and equals next, so the gate tested what ships.
- **Test the real installer in isolation.** Run `install.sh` and `uninstall.sh` against a
  throwaway prefix with a PATH that holds nothing else, then load every module from the
  installed tree. A module the package leaves out stays invisible from the checkout
  and only fails there.
- **The installer never replaces a development install.** If the command on the PATH runs
  from a git checkout, install and uninstall refuse unless `--force`.
- **Uninstall never removes user data.** Say where that data lives and prove it survives.
- **Whitelist what ships** (`files` in package.json, or an explicit tar list). An ignore
  list drifts; a whitelist fails loudly in the clean-install test.

## Language gate

For products with English CLI/help/report output, configure `languageCheck` in
`factory.json` with `language: "en"` and exact `paths` relative to each product
lane. `factory-test.sh` checks the next lane before tests; during development run
`bash factory-language-check.sh --factory . --lane dev`. The vocabulary lives in
`languages.json`, separated by target language and source language. A factory
may point `wordList` to its own JSON to support another target or vocabulary.
Scan only non-localized output code, not translations or study content. See
`README.md` for schema and limitations: this is a guard for known words, not
full automatic language identification.

## Required release gates

1. Read the project context, backlog and gaplog.
2. Check `factory.json` and current lane status.
3. Run tests and diagnostics.
4. Run privacy/secrets and licence/provenance scans.
5. Build a versioned artifact with checksum and manifest.
6. Install the artifact in a clean temporary environment.
7. Run the clean-install smoke test.
8. Promote only the validated candidate.
9. Record the commit, artifact, evidence and rollback target.

Never replace a real system installation silently. Actual sends and other
personal integrations use mocks in ship-tests; real local checks require an
explicit owner-approved gate.

## Public/private boundary

If an open wrapper uses a controlled product engine, separate them:

```text
open wrapper / protocol / AgentBrain adapter
controlled engine / GUI / hosted service
```

The wrapper's licence must not accidentally grant rights to the engine.
Consumer installers use pinned releases, checksums and explicit licence terms.

## Definition of done

A factory is mature when a clean machine can install a pinned release, run the
smoke tests, use the live lane, and roll back without rediscovery.
