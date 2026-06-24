---
name: add-locale
description: Add a new UI language to agentBrain's i18n layer (scripts/lib/_strings.sh). Interactive flow: collects the locale code + display name, extracts all string keys from the canonical English source, prompts for translations, inserts a new _t_xx() function, and extends the dispatcher. Use when the user wants to add Dutch/English-beyond support — e.g. German, French, Spanish.
argument-hint: Optional ISO 639-1 locale code (e.g. "de", "fr", "es") — if omitted, the skill asks
user-invocable: true
date: 2026-05-29
type: skill
tags: [skill, i18n, locale, scripts]
id: 7c1cfee0-4c91-548d-9b71-544695bc18f6
---

# Add Locale

Add a new language to `scripts/lib/_strings.sh` so install scripts, selftest, and doctor output appear in the user's preferred language.

## Supported state

Out of the box: `nl`, `en`. English is the safe fallback. Anything else falls back to English silently. This skill turns "silently falls back" into "first-class translated".

## When to use

- User wants UI output in a third language (German, French, Spanish, etc.)
- A collaborator on the agentBrain project speaks a different language
- You're preparing the framework for a wider audience

**Do NOT use** for one-off translations of a single message — edit `_strings.sh` directly. This skill is for adding a whole new language with full coverage.

## Prerequisites

- `~/agentBrain/scripts/lib/_strings.sh` exists (it does in any agentBrain install)
- You know the target language well enough to translate technical strings (or have the user translate them)

## Flow

### Step 1 — Collect locale metadata

Ask the user:

1. **ISO 639-1 code** (2 letters, lowercase). Examples: `de`, `fr`, `es`, `it`, `pt`.
   - If passed as skill argument, use that and confirm.
   - Validate: must be exactly 2 lowercase letters. Reject anything else.
2. **Display name** in the target language. Examples: `Deutsch`, `Français`, `Español`. Used in section headers and code comments.
3. **Confirmation** that this locale should be added as a first-class language (not just a partial set).

Refuse if the code is already `nl` or `en` (those exist).

### Step 2 — Extract keys from the canonical English source

`_t_en()` is the canonical source — every key MUST exist there. Extract all keys:

```bash
awk '/^_t_en\(\)/,/^}/' ~/agentBrain/scripts/lib/_strings.sh \
  | grep -oE '^\s*[a-z][a-z_.]+\)' \
  | sed 's/)$//' | sed 's/^[[:space:]]*//' | sort -u
```

This gives you the complete key list. Read the English values for each key by re-running the extraction with the value column.

Report the total count back to the user: *"Found N keys to translate. Want to proceed?"*

### Step 3 — Collect translations

For each section (Generic, Selftest, Install — they're commented as `# Generic`, `# Selftest sections`, etc. in `_t_en()`), present the English source and ask the user for translations.

Two presentation modes — pick based on count:

- **≤ 20 keys total**: ask one-by-one with the English string and a suggested translation (you may translate yourself, but explicitly mark suggestions as `[draft]` and ask the user to accept/edit/replace).
- **> 20 keys**: show the user the full block in a markdown table:

  | Key | English | Translation (`<code>`) |
  |---|---|---|
  | `generic.present` | `present` | |
  | … | … | |

  Ask them to fill in the right column or send it back as a list. Accept partial submissions — untranslated keys fall back to English at runtime anyway.

For technical terms (`UUID5`, `frontmatter`, `hook`, `addon`, `symlink`) — keep them in English unless the target language has a well-established translation. Tell the user this is the convention.

### Step 4 — Build the `_t_xx()` function

Construct the new function body. Follow the exact style of `_t_nl()`:

- Same comment dividers (`# Generic`, `# Selftest sections`, `# Selftest brain root`, etc.)
- Same key order as `_t_en()`
- Tab indentation (NOT spaces — `_strings.sh` is tabs)
- Format: `<key>)<spaces-to-align>echo "<translation>" ;;`

Example for German:

```bash
# ── German ────────────────────────────────────────────────────
_t_de() {
	case "$1" in
		# Generic
		generic.present)               echo "vorhanden" ;;
		generic.missing)               echo "fehlt" ;;
		…
		*) _t_en "$1" ;;  # fallback for any missing keys
	esac
}
```

**Critical**: include `*) _t_en "$1" ;;` as the last case so missing translations fall back to English instead of producing empty strings.

### Step 5 — Apply the changes

Three edits to `scripts/lib/_strings.sh`:

**Edit 1 — Extend the locale normalization** (around line 28-32):

```bash
# Before:
case "$_AGENTBRAIN_LOCALE" in
    nl|en) ;;
    *) _AGENTBRAIN_LOCALE="en" ;;
esac

# After:
case "$_AGENTBRAIN_LOCALE" in
    nl|en|de) ;;       # ← add new code here
    *) _AGENTBRAIN_LOCALE="en" ;;
esac
```

**Edit 2 — Extend the dispatcher** in `t()` (around line 36-40):

```bash
# Before:
case "$_AGENTBRAIN_LOCALE" in
    nl) _t_nl "$key" ;;
    *)  _t_en "$key" ;;
esac

# After:
case "$_AGENTBRAIN_LOCALE" in
    nl) _t_nl "$key" ;;
    de) _t_de "$key" ;;       # ← add new dispatch here
    *)  _t_en "$key" ;;
esac
```

**Edit 3 — Append the new `_t_xx()` function** AFTER `_t_en()` (currently ends around line 246-249).

Use the `Edit` tool with the closing `}` of `_t_en()` as the anchor to ensure the new function is inserted in the right place.

### Step 6 — Verify

Run a quick smoke test:

```bash
AGENTBRAIN_LOCALE=<code> bash -c 'source ~/agentBrain/scripts/lib/_strings.sh; echo "$(t generic.summary)"; echo "$(t generic.done)"'
```

Both should print in the new language. If they print English, the dispatcher edit didn't land — re-check Edit 2.

Then run the selftest to confirm nothing broke:

```bash
AGENTBRAIN_LOCALE=<code> bash ~/agentBrain/scripts/selftest-claude-integration.sh
```

It should still show 35/35 passes, with section headers in the new language.

### Step 7 — Update docs

- Add the new code to README.md's Locale section (currently mentions only `nl` and `en` as supported).
- Optionally: add a coverage check by comparing key counts between `_t_en()` and `_t_xx()`. If `_t_xx()` has fewer keys, list the missing ones for the user.

## Coverage check (optional helper)

After Step 5, run this to verify coverage:

```bash
en_keys=$(awk '/^_t_en\(\)/,/^}/' ~/agentBrain/scripts/lib/_strings.sh | grep -oE '^\s*[a-z][a-z_.]+\)' | sort -u)
xx_keys=$(awk '/^_t_<code>\(\)/,/^}/' ~/agentBrain/scripts/lib/_strings.sh | grep -oE '^\s*[a-z][a-z_.]+\)' | sort -u)
diff <(echo "$en_keys") <(echo "$xx_keys")
```

Lines starting with `<` are keys present in EN but missing in the new locale. They fall back to English (safe), but flag them so the user can fill them in later.

## Notes

- This skill modifies `scripts/lib/_strings.sh` — a public file in the framework. The change should be committed to the agentBrain repo if you want collaborators to inherit the new language.
- `_AGENTBRAIN_LOCALE` is cached per-shell, so a user who runs `export AGENTBRAIN_LOCALE=de` in their `.zshrc` gets the new language permanently. Suggest this at the end.
- Bash 3 compatibility: no associative arrays, no `local -A` — stick to `case` statements like the existing code.

## Related

- `scripts/lib/_strings.sh` — the i18n source
- `README.md#locale` — user-facing documentation
- `system/addons/session-journal/install.sh` — example of how addons use `t()`
- `scripts/selftest.sh` — primary consumer; good smoke-test target
