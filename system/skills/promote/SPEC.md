---
date: 2026-05-24
type: spec
tags: [spec]
source: session
version: 1.1.0
id: ba078183-8f50-52f6-9750-37216b124a51
---

# promote/demote — agentBrain mirror-path swapper

**Status**: v1.1
**Implementation language**: bash (no runtime deps beyond standard CLI)
**Skill location**: `$BRAIN_DIR/system/skills/promote/` (`$BRAIN_DIR` is the resolved agentBrain root, see section 3)
**OS assumption**: macOS in v1 (see section 8)

---

## 1. Purpose

agentBrain has a canonical scope axis (per `system/rules.md`):

> Public = HOW/WHERE (`system/`). Private = WHAT (`vault/`).

Five subfolders exist in **both** scopes and form a mirror: `addons/`, `agent-config/`, `integrations/`, `pi-config/`, `skills/`. Artifacts in those folders are routinely written in `vault/` first (private, experimental) and eventually graduate to `system/` (canonical, shared across agents).

Today this graduation happens by hand: pick the file, copy it across, delete the old location, remember to do the inverse if you change your mind. This is error-prone (forgotten `rm`, wrong target subfolder) and inconsistent (sometimes `cp` + stub, sometimes `mv`, sometimes outright duplicated).

The `promote`/`demote` skill makes the move explicit, atomic, and symmetric. It only operates on the canonical mirror — nothing else.

## 2. Scope (v1)

**In scope**:
- Path-swap between mirror subfolders only (the 5 listed below).
- Works on files and on directories (a directory move is one `mv` operation).
- Idempotent: refuses to overwrite an existing target unless `--force`.
- Helpful refusal for non-mirror paths, with pointers to existing alternative skills.

**Explicitly out of scope** (deferred to v2):
- Abstract-to-rules flow for non-mirror folders (extracting a pattern from `vault/learnings/` into a rule in `system/rules.md` with privacy-scrub + diff-review).
- `/promotion-candidates` scanner (suggests rip-for-promotion items).
- Mentions-counter in frontmatter or a `WATCHLIST.md` register.
- Stub-pointers in source (path-swap moves the file; source is gone, no pointer needed).
- Frontmatter rewriting (mirror-folder artifacts don't use the agentBrain `date/type/tags/id` frontmatter contract — those are for `vault/learnings/`, `vault/sessions/`, etc.).
- Git operations (commits, branches). The user runs git separately.

## 3. Path conventions & commands

### `BRAIN_DIR`

The script resolves the agentBrain root once at startup, in this order:

1. `$BRAIN_DIR` from the environment, when set.
2. The checkout the script itself lives in (`<root>/system/skills/promote/bin/promote`,
   resolved with `cd -P`), when that root has `system/rules.md`. A dev or sandbox
   checkout therefore promotes inside itself, not into the one `~/agentBrain` points at.
3. The realpath of `~/agentBrain`.

It exits 1 when none of these resolves.

All paths in this spec use `$BRAIN_DIR/...` rather than `~/agentBrain/...`.

### Commands

```
promote <local-path> [--force]
demote  <system-path> [--force]
```

`<local-path>` must be inside `$VAULT_DIR/<mirror>/…`.
`<system-path>` must be inside `$BRAIN_DIR/system/<mirror>/…`.

`$VAULT_DIR` is the private root: the vault as resolved by `scripts/lib/vault.sh`, the
same resolution every other script uses (`AGENTBRAIN_VAULT` or one of its older spellings if set, else the checkout's
`vault/` link, else the legacy `local/` alias), then resolved to its physical path. It
normally lives outside the checkout (`~/.agentBrain/vault`), so `$BRAIN_DIR/vault/…` and
the physical vault path are both accepted and name the same place.

Both relative and absolute paths are accepted; the script normalizes via `realpath` and verifies the result starts with `$VAULT_DIR/` or `$BRAIN_DIR/system/` as appropriate.

### Examples

```bash
# Promote a tested skill from local to system
promote $BRAIN_DIR/vault/skills/yt-digest

# Demote a system integration back to private experimentation
demote $BRAIN_DIR/system/integrations/lightpanda.md

# Promote a single addon file
promote $BRAIN_DIR/vault/addons/extract-learnings
```

## 4. Mirror folders

Hardcoded constant in the script:

| Folder | Typical artifacts |
|---|---|
| `addons` | Plugins/extensions (folders or .md files) |
| `agent-config` | Per-agent config files (e.g., `claude.md`, `copilot.md`) |
| `integrations` | External-system integration notes (.md files) |
| `pi-config` | Pi-related scripts, binaries, configs (mixed: `.md`, `.sh`, `.ts`, `bin/`) |
| `skills` | Skill packages (folders containing `SKILL.md`) |

A path qualifies as mirror-eligible iff the first path component after `vault/` or `system/` is in this list.

## 5. Behavior (per command)

### `promote <local-path>`

1. **Validate source**: file or directory exists and is not a symlink (see section 6 for symlink policy). If not → error, exit 1.
2. **Normalize & verify scope**: resolve source to absolute path via `realpath`; verify it starts with `$VAULT_DIR/`. If not → error; when the source is under `system/` the message suggests `demote`.
3. **Compute target via prefix-strip-and-prepend**:
   - `relative="${source#$VAULT_DIR/}"` (strip the private-root prefix)
   - `target="$BRAIN_DIR/system/$relative"` (prepend the system prefix)
   - This avoids substring-replace edge cases when the path repeats a scope name further down (e.g., `$VAULT_DIR/skills/vault/foo.md`, where replacing `vault/` would hit the wrong segment).
4. **Verify mirror constraints (both sides)**:
   - First component of `$relative` must be in the mirror list. If not → friendly refusal:
     > Path `vault/<X>/…` is not a mirror folder. For `learnings`: use `/save-learning`. For `sessions`/`memories`/etc.: not promotable in v1. For abstract-to-rules: see v2 backlog.
   - **Defensive sanity check**: confirm computed `$target` starts with `$BRAIN_DIR/system/<mirror>/` for the same mirror folder. If somehow not → error (shouldn't happen after step 3, but cheap to verify).
5. **Verify target absent**: target path does not exist. If it does → error unless `--force`. (`--force` first moves the existing target to a central trash dir; see section 6.)
6. **Create target parent dir** if needed (`mkdir -p "$(dirname "$target")"`).
7. **Move**: `mv "$source" "$target"`. Atomic within the same filesystem (agentBrain lives on one disk — see "Cross-filesystem" note in section 8).
8. **Echo**: `promoted: <source> → <target>`.

### `demote <system-path>`

Identical to `promote` with the two roots swapped in step 2 and step 3 (strip `$BRAIN_DIR/system/`, prepend `$VAULT_DIR/`).

### Error/refusal messages

All refusals print:
- The reason (1 sentence).
- The exact path that was rejected.
- A pointer to the right alternative when applicable.

Exit codes: `0` success, `1` validation error, `2` target exists (without `--force`), `3` mirror constraint violated.

## 6. Edge cases

| Case | Behavior |
|---|---|
| Source is a symlink | **Refuse in v1** (exit 1) with message: "Source is a symlink; v1 only operates on real files/dirs to avoid ambiguous semantics. Resolve the link manually or pass the real path." Following the link and then moving the link itself was considered but creates a class of bugs where the moved link points outside the brain. v2 may revisit with an explicit "both link and target inside brain" check. |
| Source is a directory with many files | Single `mv`; atomic on same FS. No partial-move risk. |
| Target exists | Refuse with exit 2. `--force` first moves the existing target to **central trash**: `$VAULT_DIR/.trash/promote/<YYYYMMDD-HHMMSS>/<to-scope>/<relative-path>` (`<to-scope>` is `system` for promote, `local` for demote), preserving structure. Never `rm`. See section 8 for keeping `.trash/` out of a synced vault. |
| Source path is exactly `$VAULT_DIR/<mirror>` (the mirror folder itself, no child) | Refuse — promoting the whole mirror folder would clobber `system/<mirror>`. |
| Source path is `$VAULT_DIR/<mirror>/something/nested/file.md` | Allowed; the relative structure under `<mirror>` is preserved on the system side. |
| User passes a relative path like `vault/skills/foo` | Normalize via `realpath` (with fallback), which follows the `vault/` link; result must start with `$VAULT_DIR/`. |
| Mirror folder names with hyphens (e.g., `agent-config`) | Treated as literal strings; no glob/regex. |
| Permission denied on `mv` | Surface the OS error verbatim, exit 1. |
| Cross-filesystem `mv` | Possible when `vault/` and `system/` sit on different mounts; `mv` then copies and deletes, which is not atomic. Not guarded in v1; see section 8. |

## 7. File layout

```
~/agentBrain/system/skills/promote/
├── SKILL.md            # discovery: name, description, when-to-use, 3 examples
├── SPEC.md             # this document
└── bin/
    └── promote         # bash entrypoint with promote/demote subcommands
                        # (the same script handles both verbs via its invocation name)
```

The single bash script handles both verbs by its invocation name (`basename "$0"`). Simplest setup: one script `bin/promote`, and `bin/demote` is a symlink to it.

## 8. Implementation notes

- **Shell**: `#!/usr/bin/env bash`, `set -euo pipefail`.
- **Mirror constant**: `MIRROR_FOLDERS=(addons agent-config integrations pi-config skills)`.
- **Path normalization**: BSD `realpath` first (modern macOS ships it); fall back to `(cd "$dir" && pwd -P)` for portability; final fallback to `python3 -c 'import os; print(os.path.realpath(...))'` if both fail. See section 3.
- **`BRAIN_DIR` resolution**: computed once at startup; all path operations use it.
- **No external runtime deps**: bash + standard CLI (`mv`, `mkdir`, `realpath` or fallbacks). No `jq`, no Bun, no Python required (but Python3 used as a fallback if installed).
- **Trash folder**: `$VAULT_DIR/.trash/promote/`. Never auto-`rm`. Nothing adds it to the vault's `.gitignore` for you: if you sync the vault with git, add `/.trash/` there yourself.
- **OS assumption**: macOS-only in v1. `stat -f %d` (cross-FS device check) is macOS-specific, so v1 skips cross-FS guarding and assumes `~/agentBrain` lives on a single disk. Cross-platform support is v2.
- **Logging**: stdout only (one line per action). No log file in v1.
- **Idempotency check**: simple `[ -e "$target" ]`.
- **Git interaction**: none. `mv` leaves the working tree with deletions in `vault/` and additions in `system/`; the user runs `git status` and stages as desired.

## 9. Testing (smoke)

Manual smoke test post-implementation:

1. **Happy path — file promote**:
   - Create `~/agentBrain/vault/integrations/test-smoke.md`.
   - `promote ~/agentBrain/vault/integrations/test-smoke.md`.
   - Assert: source gone, target present at `~/agentBrain/system/integrations/test-smoke.md`.
2. **Happy path — directory promote**:
   - Create `~/agentBrain/vault/skills/test-smoke/SKILL.md`.
   - `promote ~/agentBrain/vault/skills/test-smoke`.
   - Assert: target directory present with SKILL.md.
3. **Demote round-trip**:
   - `demote ~/agentBrain/system/skills/test-smoke`.
   - Assert: back at `~/agentBrain/vault/skills/test-smoke`.
4. **Non-mirror refusal**:
   - `promote ~/agentBrain/vault/learnings/anything.md`.
   - Assert: exit 3, friendly message naming `/save-learning`.
5. **Target-exists refusal**:
   - Create both source and target.
   - `promote …`. Assert: exit 2.
   - `promote … --force`. Assert: succeeds, old target moved to `$BRAIN_DIR/vault/.trash/promote/<timestamp>/…`.
6. **Symlink refusal**:
   - `ln -s ~/agentBrain/vault/skills/yt-digest /tmp/symlink-test`.
   - `promote /tmp/symlink-test`. Assert: exit 1, helpful "symlink not supported" message.
7. **Cleanup**: remove `test-smoke` artifacts; `.trash/` contents preserved (never-delete-compliant).

## 10. Out of scope — v2 backlog

| Feature | Why deferred |
|---|---|
| `/promotion-candidates` scanner | No use case yet; wait until the pattern recurs |
| Abstract-to-rules flow (non-mirror → `system/rules.md`) | Needs privacy-scrub + diff-review UI; substantial design |
| Mentions counter | Premature infrastructure; revisit when 3+ deferred items exist |
| Git auto-staging | Couples skill to git assumptions; add only if it stops being silent friction |
| WATCHLIST.md register | Premature; one item is not a register |
