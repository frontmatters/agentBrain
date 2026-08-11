---
date: 2026-05-24
type: spec
tags: [spec]
source: session
version: 1.1.0
id: ba078183-8f50-52f6-9750-37216b124a51
---

# promote/demote — agentBrain mirror-path swapper

**Status**: draft v1.1 (post Pi peer-review)
**Implementation language**: bash (no runtime deps beyond standard CLI)
**Skill location**: `$BRAIN_DIR/local/skills/promote/` (where `$BRAIN_DIR` is the realpath of `~/agentBrain`)
**OS assumption**: macOS-only in v1 (consistent with user's environment)

---

## 1. Purpose

agentBrain has a canonical scope axis (per `system/rules.md`):

> Public = HOW/WHERE (`system/`). Private = WHAT (`local/`).

Five subfolders exist in **both** scopes and form a mirror: `addons/`, `agent-config/`, `integrations/`, `pi-config/`, `skills/`. Artifacts in those folders are routinely written in `local/` first (private, experimental) and eventually graduate to `system/` (canonical, shared across agents).

Today this graduation happens by hand: pick the file, copy it across, delete the old location, remember to do the inverse if you change your mind. This is error-prone (forgotten `rm`, wrong target subfolder) and inconsistent (sometimes `cp` + stub, sometimes `mv`, sometimes outright duplicated).

The `promote`/`demote` skill makes the move explicit, atomic, and symmetric. It only operates on the canonical mirror — nothing else.

## 2. Scope (v1-strak)

**In scope**:
- Path-swap between mirror subfolders only (the 5 listed below).
- Works on files and on directories (a directory move is one `mv` operation).
- Idempotent: refuses to overwrite an existing target unless `--force`.
- Helpful refusal for non-mirror paths, with pointers to existing alternative skills.

**Explicitly out of scope** (deferred to v2):
- Abstract-to-rules flow for non-mirror folders (extracting a pattern from `local/learnings/` into a rule in `system/rules.md` with privacy-scrub + diff-review).
- `/promotion-candidates` scanner (suggests rip-for-promotion items).
- Mentions-counter in frontmatter or a `WATCHLIST.md` register.
- Stub-pointers in source (path-swap moves the file; source is gone, no pointer needed).
- Frontmatter rewriting (mirror-folder artifacts don't use the agentBrain `date/type/tags/id` frontmatter contract — those are for `local/learnings/`, `local/sessions/`, etc.).
- Git operations (commits, branches). The user runs git separately.

## 3. Path conventions & commands

### `BRAIN_DIR`

`~/agentBrain` is (on this system) a symlink to `~/Developer/agentBrain-dev`. To stay symlink-agnostic and robust to renames, the script resolves the canonical path at startup:

```bash
BRAIN_DIR="$(realpath ~/agentBrain 2>/dev/null \
            || (cd ~/agentBrain && pwd -P))"
```

The fallback handles macOS versions without BSD `realpath` (rare on modern macOS, but cheap insurance). For truly portable resolution, a Python3 third fallback can be added:

```bash
BRAIN_DIR="${BRAIN_DIR:-$(python3 -c 'import os; print(os.path.realpath(os.path.expanduser("~/agentBrain")))')}"
```

All paths in this spec use `$BRAIN_DIR/...` rather than `~/agentBrain/...`.

### Commands

```
promote <local-path> [--force]
demote  <system-path> [--force]
```

`<local-path>` must be inside `$BRAIN_DIR/local/<mirror>/…`.
`<system-path>` must be inside `$BRAIN_DIR/system/<mirror>/…`.

Both relative and absolute paths are accepted; the script normalizes via `realpath` and verifies the result starts with `$BRAIN_DIR/local/` or `$BRAIN_DIR/system/` as appropriate.

### Examples

```bash
# Promote a tested skill from local to system
promote $BRAIN_DIR/local/skills/yt-digest

# Demote a system integration back to private experimentation
demote $BRAIN_DIR/system/integrations/lightpanda.md

# Promote a single addon file
promote $BRAIN_DIR/local/addons/extract-learnings
```

## 4. Mirror folders

Hardcoded constant in the script. As of 2026-05-24 the disk state matches this list; the script self-checks at startup (logs a warning if `$BRAIN_DIR/system/<mirror>` doesn't exist for any folder it expects, so drift gets caught early):

| Folder | Typical artifacts |
|---|---|
| `addons` | Plugins/extensions (folders or .md files) |
| `agent-config` | Per-agent config files (e.g., `claude.md`, `copilot.md`) |
| `integrations` | External-system integration notes (.md files) |
| `pi-config` | Pi-related scripts, binaries, configs (mixed: `.md`, `.sh`, `.ts`, `bin/`) |
| `skills` | Skill packages (folders containing `SKILL.md`) |

A path qualifies as mirror-eligible iff the first path component after `local/` or `system/` is in this list.

## 5. Behavior (per command)

### `promote <local-path>`

1. **Validate source**: file or directory exists and is not a symlink (see section 6 for symlink policy). If not → error, exit 1.
2. **Normalize & verify scope**: resolve source to absolute path via `realpath`; verify it starts with `$BRAIN_DIR/local/`. If not → error suggesting `demote`.
3. **Compute target via prefix-strip-and-prepend**:
   - `relative="${source#$BRAIN_DIR/local/}"` (strip the local prefix)
   - `target="$BRAIN_DIR/system/$relative"` (prepend the system prefix)
   - This avoids substring-replace edge cases when a path contains `local/` twice (e.g., `$BRAIN_DIR/local/skills/local/foo.md`).
4. **Verify mirror constraints (both sides)**:
   - First component of `$relative` must be in the mirror list. If not → friendly refusal:
     > Path `local/<X>/…` is not a mirror folder. For `learnings`: use `/save-learning`. For `sessions`/`memories`/etc.: not promotable in v1. For abstract-to-rules: see v2 backlog.
   - **Defensive sanity check**: confirm computed `$target` starts with `$BRAIN_DIR/system/<mirror>/` for the same mirror folder. If somehow not → error (shouldn't happen after step 3, but cheap to verify).
5. **Verify target absent**: target path does not exist. If it does → error unless `--force`. (`--force` first moves the existing target to a central trash dir; see section 6.)
6. **Create target parent dir** if needed (`mkdir -p "$(dirname "$target")"`).
7. **Move**: `mv "$source" "$target"`. Atomic within the same filesystem (agentBrain lives on one disk — see "Cross-filesystem" note in section 8).
8. **Echo**: `promoted: <source> → <target>`.

### `demote <system-path>`

Identical to `promote` with `local/` and `system/` swapped in step 2 and step 3 (strip `$BRAIN_DIR/system/`, prepend `$BRAIN_DIR/local/`).

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
| Target exists | Refuse with exit 2. `--force` first moves the existing target to **central trash**: `$BRAIN_DIR/local/.trash/promote/<YYYYMMDD-HHMMSS>/<relative-target-path>`, preserving structure. Never `rm`. The `.trash/` folder is gitignored (see section 8). |
| Source path is exactly `$BRAIN_DIR/local/<mirror>` (the mirror folder itself, no child) | Refuse — promoting the whole mirror folder would clobber `system/<mirror>`. |
| Source path is `$BRAIN_DIR/local/<mirror>/something/nested/file.md` | Allowed; the relative structure under `<mirror>` is preserved on the system side. |
| User passes a relative path like `local/skills/foo` | Normalize via `realpath` (with fallback); result must start with `$BRAIN_DIR/local/`. |
| Mirror folder names with hyphens (e.g., `agent-config`) | Treated as literal strings; no glob/regex. |
| Permission denied on `mv` | Surface the OS error verbatim, exit 1. |
| Cross-filesystem `mv` | Theoretically possible (e.g., if user puts `local/` and `system/` on different mounts), but `~/agentBrain` lives on one disk in this user's setup. Out of scope to guard for v1 — see section 8. |

## 7. File layout

```
~/agentBrain/local/skills/promote/
├── SKILL.md            # discovery: name, description, when-to-use, 3 examples
├── SPEC.md             # this document
└── bin/
    └── promote         # bash entrypoint with promote/demote subcommands
                        # (the same script handles both verbs via $0 or arg-0)
```

The single bash script handles both verbs by checking its invocation (`basename "$0"` or first argument). Simplest setup: one script `bin/promote`, and `bin/demote` is a symlink to it.

## 8. Implementation notes

- **Shell**: `#!/usr/bin/env bash`, `set -euo pipefail`.
- **Mirror constant**: `MIRROR_FOLDERS=(addons agent-config integrations pi-config skills)`.
- **Path normalization**: BSD `realpath` first (modern macOS ships it); fall back to `(cd "$dir" && pwd -P)` for portability; final fallback to `python3 -c 'import os; print(os.path.realpath(...))'` if both fail. See section 3.
- **`BRAIN_DIR` resolution**: computed once at startup; all path operations use it.
- **No external runtime deps**: bash + standard CLI (`mv`, `mkdir`, `realpath` or fallbacks). No `jq`, no Bun, no Python required (but Python3 used as a fallback if installed).
- **Trash folder**: `$BRAIN_DIR/local/.trash/promote/` — append `local/.gitignore` line `/.trash/` (or `.trash/` if at root) during skill setup. Never auto-`rm`.
- **OS assumption**: macOS-only in v1. The Pi reviewer flagged that `stat -f %d` (cross-FS device check) is macOS-specific; we explicitly skip cross-FS guarding in v1 because `~/agentBrain` lives on a single disk in this user's setup. Cross-platform support is v2.
- **Logging**: stdout only (one line per action). No log file in v1.
- **Idempotency check**: simple `[ -e "$target" ]`.
- **Git interaction**: none. `mv` leaves the working tree with deletions in `local/` and additions in `system/`; the user runs `git status` and stages as desired.

## 9. Testing (smoke)

Manual smoke test post-implementation:

1. **Happy path — file promote**:
   - Create `~/agentBrain/local/integrations/test-smoke.md`.
   - `promote ~/agentBrain/local/integrations/test-smoke.md`.
   - Assert: source gone, target present at `~/agentBrain/system/integrations/test-smoke.md`.
2. **Happy path — directory promote**:
   - Create `~/agentBrain/local/skills/test-smoke/SKILL.md`.
   - `promote ~/agentBrain/local/skills/test-smoke`.
   - Assert: target directory present with SKILL.md.
3. **Demote round-trip**:
   - `demote ~/agentBrain/system/skills/test-smoke`.
   - Assert: back at `~/agentBrain/local/skills/test-smoke`.
4. **Non-mirror refusal**:
   - `promote ~/agentBrain/local/learnings/anything.md`.
   - Assert: exit 3, friendly message naming `/save-learning`.
5. **Target-exists refusal**:
   - Create both source and target.
   - `promote …`. Assert: exit 2.
   - `promote … --force`. Assert: succeeds, old target moved to `$BRAIN_DIR/local/.trash/promote/<timestamp>/…`.
6. **Symlink refusal**:
   - `ln -s ~/agentBrain/local/skills/yt-digest /tmp/symlink-test`.
   - `promote /tmp/symlink-test`. Assert: exit 1, helpful "symlink not supported" message.
7. **Cleanup**: remove `test-smoke` artifacts; `.trash/` contents preserved (never-delete-compliant).

## 10. Open questions for the reviewer

### Resolved by Pi peer-review (2026-05-24)

- ~~`--force` semantics~~ → **central trash folder pattern adopted** (`$BRAIN_DIR/local/.trash/promote/<ts>/…`), gitignored. See section 6 + 8.
- ~~Cross-filesystem guard~~ → **dropped from v1**; documented as macOS-single-disk assumption in section 8. Re-evaluate if Linux/multi-mount setup ever appears.
- ~~`~/agentBrain` path hardcoding~~ → **replaced by `$BRAIN_DIR`** resolved at startup with realpath + fallbacks. Reviewer's specific suggestion of `~/Developer/agentBrain` was based on a wrong assumption (actual symlink target is `~/Developer/agentBrain-dev`); the `$BRAIN_DIR` approach handles this regardless.
- ~~Symlink semantics~~ → **refuse symlinks in v1**; v2 may revisit. See section 6.
- ~~Target-parent verification~~ → **prefix-strip-and-prepend** plus explicit mirror-folder match in section 5 step 4.

### Still open

1. **`demote` as a symlink to `promote`**: clean (one script), but slightly clever. Alternative: a 5-line `bin/demote` that just `exec`s the main script with a flag. Which do you prefer?
2. **Should the skill auto-`git add` after a move?** agentBrain is git-tracked (`~/Developer/agentBrain-dev`). A `mv` leaves both source-removed and target-added unstaged. Auto-`git add -A` would keep the working tree easier to review but might over-stage. Default in v1: skill does **not** touch git; user runs git themselves.
3. **`agent-config/` collision risk**: the target subfolder has canonical filenames (`claude.md`, `copilot.md`). Promoting `local/agent-config/claude.md` to `system/agent-config/claude.md` would silently overwrite the canonical version (without `--force` it refuses, which is correct). Should this folder get an extra "are you sure?" prompt because blast radius is larger? Current design: no — uniform `--force` guard applies.
4. **Mirror-folder list maintenance**: hardcoded list of 5. If a new mirror folder appears (e.g., `templates/`), the script needs updating. Acceptable burden, or auto-detect via `comm` between `system/` and `local/` subfolders at startup? Auto-detect adds robustness but masks design intent (mirror folders are deliberate, not coincidental).

## 11. Out of scope — v2 backlog

| Feature | Why deferred |
|---|---|
| `/promotion-candidates` scanner | No use case yet (only 1 deferred item; user's "2x+"-rule says wait) |
| Abstract-to-rules flow (non-mirror → `system/rules.md`) | Needs privacy-scrub + diff-review UI; substantial design |
| Mentions counter | Premature infrastructure; revisit when 3+ deferred items exist |
| Git auto-staging | Couples skill to git assumptions; add only if it stops being silent friction |
| WATCHLIST.md register | Premature; one item is not a register |
