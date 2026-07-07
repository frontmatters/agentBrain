---
name: onboard
description: Interactive onboarding for agentBrain users. Personalizes preference scopes (personal/organization/team), installs recommended and optional addons, sets the UI locale, and configures the release channel + update mode.
argument-hint: Optional focus area (e.g. "tech-stack", "communication", "organization", "team", "addons", "locale", or "channel")
user-invocable: true
---

# Onboard

Interactive setup that personalizes agentBrain preference scopes.

## Preference scopes

Preferences live under `~/agentBrain/local/preferences/` in scopes:

1. `personal/` — individual preferences; always present and always filled by `/onboard`
2. `organization/` — optional broader rules/context for an organization
3. `team/` — optional agreements/context for a team

All scopes are markdown files. They are not enforced policy; they are context with different ownership/breadth. Agents should read all scopes that exist and surface tensions instead of inventing hidden precedence rules.

## Main flow

Start with what the user knows: their own preferences. Ask about broader scopes only after personal onboarding.

### Step 1 — Personal preferences (always)

Scan `~/agentBrain/local/preferences/personal/`. If it does not exist, create it.

Seeding missing files from the repo templates (`~/agentBrain/user-preferences/*.md`)
should already have happened during setup (`~/agentBrain/scripts/setup-templates.sh`). If you must
seed manually, use `bash ~/agentBrain/scripts/new-note.sh` so frontmatter and UUID5
come out correct — never raw `cp`: the templates contain `id: {{uuid5}}` placeholders
and the validate hook rejects nil/mismatched ids.

A file needs onboarding if it contains a placeholder marker — the same explicit set
`/config preferences` greps for:

- `This is an example`
- `<!-- Example:` at the start of a line (`^<!-- Example:`)

(Empty sections — headings with no content — are a soft signal worth asking about,
but the two markers above are the canonical skip-if-done test.)

Ask questions in this order:

1. `communication.md`
   - "What language do you prefer for conversation? (e.g. English, Dutch, mixed)"
   - "How verbose should I be? (concise / detailed / depends on topic)"
   - "Should I ask before acting, or just do it for trivial decisions?"
2. `tech-stack.md`
   - "What's your primary OS and editor?"
   - "What languages and frameworks do you use most?"
   - "Where do you host code? (GitHub, GitLab, self-hosted, etc.)"
   - "Any infrastructure preferences? (Docker, cloud provider, database, etc.)"
3. `workflow.md`
   - "Where do your projects live on disk?"
   - "How autonomous should I be? (ask often / only for blockers / full autonomy)"
   - "Any shell or tooling preferences? (zsh, bash, package managers, etc.)"
4. `design-philosophy.md`
   - "Do you have a preferred visual style? (minimal, Material, custom design system, etc.)"
   - "Dark mode, light mode, or both?"
   - "Any icon/typography preferences?"
5. `decision-making.md`
   - "How do you approach technical decisions? (pragmatic, thorough, move fast, etc.)"
   - "Build vs buy — do you prefer libraries or custom code?"
   - "How important is backwards compatibility vs. clean breaks?"

Write answers to `~/agentBrain/local/preferences/personal/<file>.md`. Keep frontmatter when present, remove placeholder/example notes, and keep the structure readable.

### Step 2 — Organization scope (optional)

After personal preferences, ask:

> "Are there broader organization-wide rules or preferences that should guide agents here? Examples: AI usage rules, security expectations, tech stack, compliance, deployment, code review, design system."

If the answer is **no**, skip this scope.

If `~/agentBrain/local/preferences/organization/*.md` already exists:

- summarize the existing files
- ask whether they still apply
- if the user wants changes, update only the files they explicitly choose

If the answer is **yes** and no files exist, ask what should be captured and write concise files under `~/agentBrain/local/preferences/organization/`. Suggested files:

- `stack.md`
- `security-policy.md`
- `compliance.md`
- `deployment.md`
- `code-review.md`
- `design-system.md`

Do not use domain-specific examples unless the user provides them.

### Step 3 — Team scope (optional)

After organization scope, ask:

> "Are there team-specific agreements that differ from or add to the broader organization context?"

If the answer is **no**, skip this scope.

If `~/agentBrain/local/preferences/team/*.md` already exists:

- summarize the existing files
- ask whether they still apply
- if the user wants changes, update only the files they explicitly choose

If the answer is **yes** and no files exist, write concise files under `~/agentBrain/local/preferences/team/`. Suggested files:

- `stack.md`
- `workflow.md`
- `conventions.md`
- `review-process.md`

### Step 4 — Addons (recommended first, then optional)

After preference scopes, offer the addons under `system/addons/`. Use the
canonical registry to determine which are available and which are already enabled:

```bash
bash ~/agentBrain/scripts/addons.sh status
```

**Offer the essentials first.** Read the current list from
`~/agentBrain/scripts/lib/essential-addons.txt` and present those addons as
**recommended**: the MCP server and session-journal are what the rest of the
framework leans on (brain search/read tools, session continuity), so most
installs want them. Only after the essentials, offer the remaining opt-in addons.

An addon is **already enabled** when `~/agentBrain/local/addons/<id>/enabled` exists
(the `status` output shows `enabled` next to its name). For each addon that is NOT yet
enabled, decide whether to offer it:

- Skip if the user is on a non-Claude agent (Pi, Copilot, Gemini, etc.) AND the
  addon is Claude-Code-specific (check `support:` in its `manifest.md`).
- Otherwise ask:

  > "Install `<addon>`? (`y` to install / `n` to skip / `?` for details)"

If `y`, run:

```bash
bash ~/agentBrain/scripts/addons.sh install <addon>
```

`addons.sh install` handles privacy disclosure, the install command, enabling, and
an optional launchd-schedule prompt automatically — no extra steps needed.

If the addon declares an `onboard:` step in its `manifest.md`, `addons.sh install`
also offers to run that interactive setup. To (re-)run it later, use:

    bash ~/agentBrain/scripts/addons.sh onboard <addon>

If the addon needs hooks in `~/.claude/settings.json`, the installer prints the
JSON block — relay that to the user and ask them to paste it (we never auto-edit
settings.json to avoid corrupting their config).

After installs, suggest running `bash ~/agentBrain/scripts/selftest.sh` (or `/selftest`) to verify.

### Step 5 — Locale

Show the currently resolved locale and offer to change it:

```bash
echo "Current: ${AGENTBRAIN_LOCALE:-${LANG:0:2}} (fallback: en)"
```

Derive the supported locale codes from the normalization case in
`~/agentBrain/scripts/lib/_strings.sh` — the single source of truth, so locales
added later via `/add-locale` are offered automatically:

```bash
sed -n '/# Normalize/,/esac/p' ~/agentBrain/scripts/lib/_strings.sh
# The first case branch (e.g. `nl|en) ;;`) lists the supported codes.
```

Ask, substituting the codes you found:

> "Set a preferred UI locale for agentBrain scripts? (`<code>` / … / `skip` to use system default)"

- If the user picks a supported code: persist `AGENTBRAIN_LOCALE=<choice>` —
  idempotently (check-before-write, never a duplicate) and with a backup first. Use this
  exact snippet, substituting `<choice>`:

```bash
case "${SHELL##*/}" in
    bash) rc="$HOME/.bashrc" ;;
    fish) rc="" ;;   # fish: no rc edit — universal variable persists on its own
    *)    rc="$HOME/.zshrc" ;;
esac
if [ -z "$rc" ]; then
    fish -c 'set -Ux AGENTBRAIN_LOCALE <choice>'
    echo "Set AGENTBRAIN_LOCALE as a fish universal variable."
elif grep -q '^export AGENTBRAIN_LOCALE=' "$rc" 2>/dev/null; then
    echo "AGENTBRAIN_LOCALE already set in $rc — leaving it."
else
    [ -f "$rc" ] && cp "$rc" "$rc.bak.$(date +%Y%m%d%H%M%S)"
    printf '\nexport AGENTBRAIN_LOCALE=%s\n' "<choice>" >> "$rc"   # >> creates the rc if absent
    echo "Set AGENTBRAIN_LOCALE in $rc (backup made if the file existed)."
fi
```

  Also apply the choice to the **running session**, not just the rc — the rc only
  affects new shells. Prefix every subsequent script invocation in this onboarding
  with `AGENTBRAIN_LOCALE=<choice>` (e.g. `AGENTBRAIN_LOCALE=<choice> bash
  ~/agentBrain/scripts/selftest.sh`) so the rest of the flow uses the new locale.

- If `skip`: do nothing — `$LANG` auto-detection will handle it.
- If the user wants a language that is not in the supported set, point them at
  `/add-locale` to add it first.

### Step 6 — Release channel & updates

Choose which release channel agentBrain follows and how updates are applied.
Skip-if-done: read `~/agentBrain/local/update/config.json`; only prompt if `auto_update` is
unset or the user asks to change it.

```bash
bash ~/agentBrain/scripts/channel.sh status   # shows current channel + where each one points
```

Ask two questions:

> "Which release channel? (`stable` = only finished releases · `prerelease` = early access · `edge` = bleeding edge)"

> "How should updates be applied? (`ask` = prompt you when one is available · `notify` = just tell you at session start · `auto` = update automatically behind the doctor gate · `off` = manual only)"

- Channel: `bash ~/agentBrain/scripts/channel.sh set <stable|prerelease|edge>`.
- Update mode: set `auto_update` in `~/agentBrain/local/update/config.json` to one of `ask` (install default), `notify`, `auto`, or `off`. Default cascade when the key is not set explicitly: config file missing entirely → behaves as `off`; file exists but key missing → behaves as `ask`; `channel.sh` seeds `ask` when it first writes the config — so a fresh install effectively defaults to `ask`. There is no `channel.sh` helper for this key — write it directly, e.g.:

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("~/agentBrain/local/update/config.json").expanduser()
cfg = json.loads(p.read_text()) if p.exists() else {}   # first run: file may not exist yet
cfg["auto_update"] = "ask"   # ask | notify | auto | off
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(cfg, indent=2) + "\n")
PY
```

- Explain that `auto` is safe: every update passes `doctor --fast` first and rolls back on failure.
- A second machine or a client typically wants `stable` + `notify`; a dev machine `prerelease`/`edge` + `auto`.

## Pattern

This skill follows the **focus-based skill** pattern — see `system/skill-patterns.md#focus-based-skill` for the full contract. Summary:

```
/onboard                  # walk-all: every scope, skip-if-done
/onboard <focus>          # walk-one: just that scope (personal, organization, team, addons, locale, channel, …)
/onboard --list           # show available scopes
```

Three rules, inherited from the pattern:

1. **Idempotent per scope** — re-running `/onboard locale` is a no-op unless the user wants to change it
2. **Detect before ask** — read existing `~/agentBrain/local/preferences/personal/*.md`, addon configs, shell rc; only prompt for what is missing or stale
3. **`/onboard <focus>` ≡ running it 10×** — identical observable behaviour

### Scope detection (skip-if-done logic)

| Scope | "Done" marker |
|-------|---------------|
| `personal/<file>.md` | File exists AND no placeholder markers (`This is an example`, `^<!-- Example:`) |
| `organization/`, `team/` | Directory has at least one non-template `.md` file |
| `addons` | Addon is enabled — `~/agentBrain/local/addons/<id>/enabled` exists (see `addons.sh is_enabled`) |
| `locale` | `AGENTBRAIN_LOCALE` is set in shell rc (or as fish universal variable) OR exported in current environment |
| `channel` | `~/agentBrain/local/update/config.json` exists AND contains an `auto_update` key |

When a scope is "done", skip it silently in walk-all mode; in walk-one mode (`/onboard locale`), confirm the current state and offer to change.

## Rules

- Ask one scope/file at a time — don't overwhelm the user
- Always start with `personal/`
- Organization/team scopes are optional; do not assume the user works in a company
- Avoid domain-specific terms unless the user uses them
- Accept short answers — fill in structure while preserving meaning
- If the user says "skip", move to the next scope/file
- After each file, confirm what was written and ask whether to continue
- After onboarding, list updated files and suggest running `/brain-review` or `bash ~/agentBrain/scripts/doctor.sh --summary`
