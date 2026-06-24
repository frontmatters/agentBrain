---
name: onboard
description: Interactive onboarding for agentBrain users. Personalizes preference scopes (personal/organization/team), optionally installs opt-in addons, and sets the UI locale.
argument-hint: Optional focus area (e.g. "tech-stack", "communication", "organization", "team", "addons", or "locale")
user-invocable: true
resources:
  - user-preferences/communication.md
  - user-preferences/workflow.md
  - user-preferences/tech-stack.md
  - user-preferences/decision-making.md
  - user-preferences/design-philosophy.md
---

# Onboard

Interactive setup that personalizes agentBrain preference scopes.

## Preference scopes

Preferences live under `local/preferences/` in scopes:

1. `personal/` — individual preferences; always present and always filled by `/onboard`
2. `organization/` — optional broader rules/context for an organization
3. `team/` — optional agreements/context for a team

All scopes are markdown files. They are not enforced policy; they are context with different ownership/breadth. Agents should read all scopes that exist and surface tensions instead of inventing hidden precedence rules.

## Main flow

Start with what the user knows: their own preferences. Ask about broader scopes only after personal onboarding.

### Step 1 — Personal preferences (always)

Scan `local/preferences/personal/`. If it does not exist, create it. Seed missing files from `user-preferences/*.md`.

A file needs onboarding if it contains:

- `This is an example file`
- `e.g.` hints without actual values
- Empty sections (only headings, no content below)
- `<!-- Example:` comments without real content

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

Write answers to `local/preferences/personal/<file>.md`. Keep frontmatter when present, remove placeholder/example notes, and keep the structure readable.

### Step 2 — Organization scope (optional)

After personal preferences, ask:

> "Are there broader organization-wide rules or preferences that should guide agents here? Examples: AI usage rules, security expectations, tech stack, compliance, deployment, code review, design system."

If the answer is **no**, skip this scope.

If `local/preferences/organization/*.md` already exists:

- summarize the existing files
- ask whether they still apply
- if the user wants changes, update only the files they explicitly choose

If the answer is **yes** and no files exist, ask what should be captured and write concise files under `local/preferences/organization/`. Suggested files:

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

If `local/preferences/team/*.md` already exists:

- summarize the existing files
- ask whether they still apply
- if the user wants changes, update only the files they explicitly choose

If the answer is **yes** and no files exist, write concise files under `local/preferences/team/`. Suggested files:

- `stack.md`
- `workflow.md`
- `conventions.md`
- `review-process.md`

### Step 4 — Optional addons

After preference scopes, offer the opt-in addons under `system/addons/`. Use the
canonical registry to determine which are available and which are already enabled:

```bash
bash scripts/addons.sh status
```

An addon is **already enabled** when `local/addons/<id>/enabled` exists (the
`status` output shows `enabled` next to its name). For each addon that is NOT yet
enabled, decide whether to offer it:

- Skip if the user is on a non-Claude agent (Pi, Copilot, Gemini, etc.) AND the
  addon is Claude-Code-specific (check `support:` in its `manifest.md`).
- Otherwise ask:

  > "Install `<addon>`? (`y` to install / `n` to skip / `?` for details)"

If `y`, run:

```bash
bash scripts/addons.sh install <addon>
```

`addons.sh install` handles privacy disclosure, the install command, enabling, and
an optional launchd-schedule prompt automatically — no extra steps needed.

If the addon declares an `onboard:` step in its `manifest.md`, `addons.sh install`
also offers to run that interactive setup. To (re-)run it later, use:

    bash scripts/addons.sh onboard <addon>

If the addon needs hooks in `~/.claude/settings.json`, the installer prints the
JSON block — relay that to the user and ask them to paste it (we never auto-edit
settings.json to avoid corrupting their config).

After installs, suggest running `bash scripts/selftest.sh` (or `/selftest`) to verify.

### Step 5 — Locale

Show the currently resolved locale and offer to change it:

```bash
echo "Current: ${AGENTBRAIN_LOCALE:-${LANG:0:2}} (fallback: en)"
```

Ask:

> "Set a preferred UI locale for agentBrain scripts? (`nl` / `en` / `skip` to use system default)"

- If `nl` or `en`: append `export AGENTBRAIN_LOCALE=<choice>` to the user's shell rc —
  idempotently (grep-before-append, never a duplicate) and with a backup first. Use this
  exact snippet, substituting `<choice>`:

```bash
case "${SHELL##*/}" in bash) rc="$HOME/.bashrc" ;; *) rc="$HOME/.zshrc" ;; esac
if grep -q '^export AGENTBRAIN_LOCALE=' "$rc" 2>/dev/null; then
    echo "AGENTBRAIN_LOCALE already set in $rc — leaving it."
else
    [ -f "$rc" ] && cp "$rc" "$rc.bak.$(date +%Y%m%d%H%M%S)"
    printf '\nexport AGENTBRAIN_LOCALE=%s\n' "<choice>" >> "$rc"   # >> creates the rc if absent
    echo "Set AGENTBRAIN_LOCALE in $rc (backup made if the file existed)."
fi
```

- If `skip`: do nothing — `$LANG` auto-detection will handle it.
- If the user wants a language other than `nl`/`en`, point them at `/add-locale` to add it first.

### Step 6 — Release channel & updates

Choose which release channel agentBrain follows and how updates are applied.
Skip-if-done: read `local/update/config.json`; only prompt if `auto_update` is
unset or the user asks to change it.

```bash
bash scripts/channel.sh status   # shows current channel + where each one points
```

Ask two questions:

> "Which release channel? (`stable` = only finished releases · `prerelease` = early access · `edge` = bleeding edge)"

> "How should updates be applied? (`ask` = prompt you when one is available · `notify` = just tell you at session start · `auto` = update automatically behind the doctor gate · `off` = manual only)"

- Channel: `bash scripts/channel.sh set <stable|prerelease|edge>`.
- Update mode: set `auto_update` in `local/update/config.json` to one of `ask` (install default), `notify`, `auto`, or `off`. There is no `channel.sh` helper for this key — write it directly, e.g.:

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("local/update/config.json")
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
/onboard <focus>          # walk-one: just that scope (personal, organization, team, addons, locale, …)
/onboard --list           # show available scopes
```

Three rules, inherited from the pattern:

1. **Idempotent per scope** — re-running `/onboard locale` is a no-op unless the user wants to change it
2. **Detect before ask** — read existing `local/preferences/personal/*.md`, addon configs, shell rc; only prompt for what is missing or stale
3. **`/onboard <focus>` ≡ running it 10×** — identical observable behaviour

### Scope detection (skip-if-done logic)

| Scope | "Done" marker |
|-------|---------------|
| `personal/<file>.md` | File exists AND no placeholder strings (`This is an example`, `e.g.`, empty sections, `<!-- Example:`) |
| `organization/`, `team/` | Directory has at least one non-template `.md` file |
| `addons` | Addon is enabled — `local/addons/<id>/enabled` exists (see `addons.sh is_enabled`) |
| `locale` | `AGENTBRAIN_LOCALE` is set in shell rc OR exported in current environment |

When a scope is "done", skip it silently in walk-all mode; in walk-one mode (`/onboard locale`), confirm the current state and offer to change.

## Rules

- Ask one scope/file at a time — don't overwhelm the user
- Always start with `personal/`
- Organization/team scopes are optional; do not assume the user works in a company
- Avoid domain-specific terms unless the user uses them
- Accept short answers — fill in structure while preserving meaning
- If the user says "skip", move to the next scope/file
- After each file, confirm what was written and ask whether to continue
- After onboarding, list updated files and suggest running `/brain-review` or `scripts/doctor.sh --summary`
