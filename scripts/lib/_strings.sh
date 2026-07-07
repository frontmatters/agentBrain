#!/usr/bin/env bash
# i18n helper for agentBrain user-facing scripts.
# Usage:
#   source scripts/lib/_strings.sh
#   echo "$(t 'selftest.section.session_journal')"
#
# Locale resolution order:
#   1. $AGENTBRAIN_LOCALE  (explicit override: "nl" | "en")
#   2. $LANG               (system: "nl_NL.UTF-8" → "nl", "en_US.UTF-8" → "en")
#   3. fallback "en"
#
# String keys are namespaced dot.notation. To add a new key:
#   - Add a case branch in the language section.
#   - Keep the fallback identical to "en" so missing translations degrade safely.
#
# Bash 3-compatible (no associative arrays).

# Resolve locale once, cache. The internal cache var `_AGENTBRAIN_LOCALE` is
# prefixed with an underscore to mark it private (set by this helper, not by
# the user); the public knob is `AGENTBRAIN_LOCALE`.
if [[ -z "${_AGENTBRAIN_LOCALE:-}" ]]; then
	if [[ -n "${AGENTBRAIN_LOCALE:-}" ]]; then
		_AGENTBRAIN_LOCALE="${AGENTBRAIN_LOCALE:0:2}"
	elif [[ -n "${LANG:-}" ]]; then
		_AGENTBRAIN_LOCALE="${LANG:0:2}"
	else
		_AGENTBRAIN_LOCALE="en"
	fi
	# Normalize: only "nl" and "en" supported; anything else → en.
	case "$_AGENTBRAIN_LOCALE" in
		nl|en) ;;
		*) _AGENTBRAIN_LOCALE="en" ;;
	esac
	export _AGENTBRAIN_LOCALE
fi

t() {
	local key="$1"
	case "$_AGENTBRAIN_LOCALE" in
		nl) _t_nl "$key" ;;
		*)  _t_en "$key" ;;
	esac
}

# ── Dutch ─────────────────────────────────────────────────────
_t_nl() {
	case "$1" in
		# Generic
		generic.present)               echo "aanwezig" ;;
		generic.missing)               echo "ontbreekt" ;;
		generic.not_executable)        echo "is niet executable" ;;
		generic.exists)                echo "bestaat" ;;
		generic.does_not_exist)        echo "bestaat niet" ;;
		generic.is_symlink_to)         echo "is symlink →" ;;
		generic.is_directory)          echo "is een directory" ;;
		generic.summary)               echo "Samenvatting" ;;
		generic.passed)                echo "passed" ;;
		generic.failed)                echo "failed" ;;
		generic.warnings)              echo "warnings" ;;
		generic.done)                  echo "Klaar." ;;
		generic.dry_run_notice)        echo "(dry run — geen wijzigingen)" ;;
		generic.skipped)               echo "overgeslagen" ;;

		# Selftest sections
		selftest.section.brain_root)        echo "agentBrain root" ;;
		selftest.section.session_journal)   echo "session-journal addon" ;;
		selftest.section.memory_redirect)   echo "claude-memory-redirect addon" ;;
		selftest.section.uuid5)             echo "UUID5 + frontmatter validatie" ;;
		selftest.section.session_schema)    echo "Session schema" ;;

		selftest.brain_root.present)        echo "BRAIN_ROOT bestaat:" ;;
		selftest.brain_root.missing)        echo "BRAIN_ROOT mist:" ;;
		selftest.brain_root.symlink_intact) echo "~/agentBrain symlink intact →" ;;
		selftest.brain_root.is_dir)         echo "~/agentBrain is een directory" ;;
		selftest.brain_root.absent)         echo "~/agentBrain ontbreekt" ;;

		selftest.sj.config_seeded)          echo "journal-config.json geseed in local/" ;;
		selftest.sj.config_missing)         echo "journal-config.json mist in local/sessions/" ;;
		selftest.sj.stop_registered)        echo "Stop hook geregistreerd in settings.json" ;;
		selftest.sj.stop_not_registered)    echo "Stop hook NIET geregistreerd" ;;
		selftest.sj.autosave_registered)    echo "Autosave PostToolUse hook geregistreerd" ;;
		selftest.sj.autosave_not_registered) echo "Autosave hook NIET geregistreerd" ;;
		selftest.sj.slash_present)          echo "/journal slash command aanwezig" ;;
		selftest.sj.slash_missing)          echo "/journal slash command mist" ;;
		selftest.sj.journal_present)        echo "session-journal.md bestaat (last update:" ;;
		selftest.sj.journal_pending)        echo "session-journal.md bestaat nog niet — wordt aangemaakt bij eerstvolgende hook" ;;
		selftest.sj.update_works)           echo "journal-update.sh draait (selftest source zichtbaar)" ;;
		selftest.sj.update_unclear)         echo "journal-update.sh leverde geen duidelijke succes-output" ;;

		selftest.cmr.config_seeded)         echo "claude-redirect-config.json geseed in local/" ;;
		selftest.cmr.config_missing)        echo "claude-redirect-config.json mist in local/memories/" ;;
		selftest.cmr.active_mode)           echo "actieve mode:" ;;
		selftest.cmr.claudemd_present)      echo "CLAUDE.md instructie-blok aanwezig" ;;
		selftest.cmr.claudemd_missing)      echo "CLAUDE.md 'Memory — alleen via agentBrain' blok mist" ;;
		selftest.cmr.project_found)         echo "Huidige project gevonden in" ;;
		selftest.cmr.memory_is_symlink)     echo "memory dir is symlink →" ;;
		selftest.cmr.symlink_to_brain)      echo "Symlink wijst naar agentBrain" ;;
		selftest.cmr.symlink_wrong_target)  echo "Symlink wijst NIET naar agentBrain target" ;;
		selftest.cmr.write_through_ok)      echo "Write through symlink belandt in agentBrain" ;;
		selftest.cmr.write_through_fail)    echo "Write through symlink NIET zichtbaar in agentBrain" ;;
		selftest.cmr.memory_not_symlink)    echo "memory dir bestaat maar is GEEN symlink (mode is wellicht 'sync_hook' of 'instruction_only')" ;;
		selftest.cmr.memory_absent)         echo "memory dir bestaat (nog) niet voor dit project" ;;
		selftest.cmr.no_current_project)    echo "Huidige cwd is geen Claude project (geen Claude-projectmap gevonden)" ;;

		selftest.uuid5.valid)               echo "uuid5-gen.sh produceert geldige UUID5:" ;;
		selftest.uuid5.invalid)             echo "uuid5-gen.sh leverde geen geldige UUID5" ;;
		selftest.uuid5.script_missing)      echo "scripts/uuid5-gen.sh mist of niet executable" ;;
		selftest.uuid5.validate_present)    echo "claude-code-validate-note-id-hook.sh aanwezig" ;;
		selftest.uuid5.validate_missing)    echo "validate-note-id-hook.sh mist (PostToolUse validatie)" ;;

		selftest.schema.passes)             echo "check-session-schema.sh passes" ;;
		selftest.schema.fails)              echo "check-session-schema.sh fail:" ;;

		selftest.summary.all_good)          echo "Alles werkend." ;;
		selftest.summary.all_good_hint)     echo "Schrijf nu in een nieuwe Claude Code sessie test naar memory of laat 'm vanzelf bij Stop-event triggeren — beide komen automatisch in agentBrain terecht." ;;
		selftest.summary.failures)          echo "Er zijn failure(s). Check de regels hierboven. Re-run \`bash system/addons/<name>/install.sh\` als hooks/symlinks ontbreken." ;;

		# Install (session-journal)
		install.sj.seeded)                  echo "lokale config aangemaakt:" ;;
		install.sj.config_exists)           echo "lokale config bestaat al (onaangeraakt):" ;;
		install.sj.hooks_registered)        echo "hooks geregistreerd in" ;;
		install.sj.hooks_missing)           echo "hooks NIET gevonden in settings.json — registreer handmatig:" ;;
		install.sj.slash_present)           echo "/journal slash command aanwezig:" ;;
		install.sj.slash_missing)           echo "/journal slash command mist:" ;;
		install.sj.done)                    echo "Klaar. Herstart Claude Code (of wacht op nieuwe sessie) zodat hooks actief worden." ;;

		# Install (claude-memory-redirect)
		install.cmr.seeded)                 echo "lokale config aangemaakt:" ;;
		install.cmr.config_exists)          echo "lokale config bestaat al (onaangeraakt)" ;;
		install.cmr.active_mode)            echo "actieve mode:" ;;
		install.cmr.section_migrate)        echo "Migreren" ;;
		install.cmr.section_activation)     echo "Mode-activatie" ;;
		install.cmr.section_claudemd)       echo "CLAUDE.md instructie" ;;
		install.cmr.mode_instruction_only)  echo "instruction_only — leunt op CLAUDE.md om Claude te sturen" ;;
		install.cmr.mode_disabled)          echo "addon disabled in config — niets te activeren" ;;
		install.cmr.unknown_mode)           echo "onbekende mode:" ;;
		install.cmr.sync_hook_register)     echo "Voeg dit toe aan ~/.claude/settings.json onder .hooks.PostToolUse:" ;;
		install.cmr.sync_hook_present)      echo "sync hook al geregistreerd" ;;
		install.cmr.claudemd_present)       echo "CLAUDE.md instructie-blok aanwezig" ;;
		install.cmr.claudemd_missing)       echo "CLAUDE.md mist het 'Memory — alleen via agentBrain' blok — voeg toe vanuit README" ;;
		install.cmr.done)                   echo "Klaar. (Her)start Claude Code zodat de nieuwe memory routing actief wordt." ;;

		# Selftest — agent-agnostic dispatcher
		selftest.section.frontmatter)       echo "Frontmatter validatie" ;;
		selftest.frontmatter.passes)        echo "check-frontmatter.sh slaagt" ;;
		selftest.frontmatter.fails)         echo "check-frontmatter.sh faalt:" ;;
		selftest.frontmatter.script_missing) echo "check-frontmatter.sh mist of is niet executable" ;;
		selftest.agent.not_detected)        echo "niet gedetecteerd op deze machine" ;;

		# Selftest — Pi
		selftest.pi.cli_present)            echo "pi CLI aanwezig" ;;
		selftest.pi.cli_missing)            echo "pi CLI niet op PATH" ;;
		selftest.pi.home_present)           echo "~/.pi config dir aanwezig:" ;;
		selftest.pi.home_missing)           echo "~/.pi config dir ontbreekt:" ;;
		selftest.pi.extensions_linked)      echo "Extensions gesymlinkt vanuit system/pi-config/" ;;
		selftest.pi.extensions_partial)     echo "Extensions deels gesymlinkt" ;;
		selftest.pi.extensions_dir_missing) echo "extensions dir ontbreekt:" ;;
		selftest.pi.skills_linked)          echo "Skills gesymlinkt in ~/.pi/agent/skills/" ;;
		selftest.pi.skills_empty)           echo "~/.pi/agent/skills/ bestaat maar is leeg" ;;
		selftest.pi.skills_dir_missing)     echo "skills dir ontbreekt:" ;;
		selftest.pi.tsconfig_present)       echo "tsconfig.json aanwezig in ~/.pi/agent/" ;;
		selftest.pi.tsconfig_missing)       echo "tsconfig.json ontbreekt — run configure-pi.sh" ;;

		# Selftest — Copilot CLI
		selftest.copilot.pointer_present)   echo "copilot-instructions.md pointer aanwezig:" ;;
		selftest.copilot.pointer_missing)   echo "copilot-instructions.md pointer ontbreekt:" ;;
		selftest.copilot.pointer_links_brain) echo "Pointer verwijst naar agentBrain" ;;
		selftest.copilot.pointer_no_brain_ref) echo "Pointer noemt agentBrain niet — mogelijk handmatig overschreven" ;;
		selftest.copilot.skills_present)    echo "Skills aanwezig in ~/.copilot/skills/" ;;
		selftest.copilot.skills_empty)      echo "~/.copilot/skills/ bestaat maar is leeg" ;;
		selftest.copilot.skills_dir_absent) echo "geen ~/.copilot/skills/ — Copilot CLI gebruikt mogelijk .github/skills/ in projecten" ;;

		# Selftest — Gemini CLI
		selftest.gemini.pointer_present)    echo "GEMINI.md pointer aanwezig:" ;;
		selftest.gemini.pointer_missing)    echo "GEMINI.md pointer ontbreekt:" ;;
		selftest.gemini.pointer_links_brain) echo "Pointer verwijst naar agentBrain" ;;
		selftest.gemini.pointer_no_brain_ref) echo "Pointer noemt agentBrain niet — mogelijk handmatig overschreven" ;;

		*) _t_en "$1" ;;
	esac
}

# ── English ───────────────────────────────────────────────────
_t_en() {
	case "$1" in
		# Generic
		generic.present)               echo "present" ;;
		generic.missing)               echo "missing" ;;
		generic.not_executable)        echo "is not executable" ;;
		generic.exists)                echo "exists" ;;
		generic.does_not_exist)        echo "does not exist" ;;
		generic.is_symlink_to)         echo "is symlink →" ;;
		generic.is_directory)          echo "is a directory" ;;
		generic.summary)               echo "Summary" ;;
		generic.passed)                echo "passed" ;;
		generic.failed)                echo "failed" ;;
		generic.warnings)              echo "warnings" ;;
		generic.done)                  echo "Done." ;;
		generic.dry_run_notice)        echo "(dry run — no changes)" ;;
		generic.skipped)               echo "skipped" ;;

		# Selftest sections
		selftest.section.brain_root)        echo "agentBrain root" ;;
		selftest.section.session_journal)   echo "session-journal addon" ;;
		selftest.section.memory_redirect)   echo "claude-memory-redirect addon" ;;
		selftest.section.uuid5)             echo "UUID5 + frontmatter validation" ;;
		selftest.section.session_schema)    echo "Session schema" ;;

		selftest.brain_root.present)        echo "BRAIN_ROOT exists:" ;;
		selftest.brain_root.missing)        echo "BRAIN_ROOT missing:" ;;
		selftest.brain_root.symlink_intact) echo "~/agentBrain symlink intact →" ;;
		selftest.brain_root.is_dir)         echo "~/agentBrain is a directory" ;;
		selftest.brain_root.absent)         echo "~/agentBrain is missing" ;;

		selftest.sj.config_seeded)          echo "journal-config.json seeded in local/" ;;
		selftest.sj.config_missing)         echo "journal-config.json missing in local/sessions/" ;;
		selftest.sj.stop_registered)        echo "Stop hook registered in settings.json" ;;
		selftest.sj.stop_not_registered)    echo "Stop hook NOT registered" ;;
		selftest.sj.autosave_registered)    echo "Autosave PostToolUse hook registered" ;;
		selftest.sj.autosave_not_registered) echo "Autosave hook NOT registered" ;;
		selftest.sj.slash_present)          echo "/journal slash command present" ;;
		selftest.sj.slash_missing)          echo "/journal slash command missing" ;;
		selftest.sj.journal_present)        echo "session-journal.md exists (last update:" ;;
		selftest.sj.journal_pending)        echo "session-journal.md does not exist yet — will be created on first hook" ;;
		selftest.sj.update_works)           echo "journal-update.sh runs (selftest source visible)" ;;
		selftest.sj.update_unclear)         echo "journal-update.sh produced no clear success output" ;;

		selftest.cmr.config_seeded)         echo "claude-redirect-config.json seeded in local/" ;;
		selftest.cmr.config_missing)        echo "claude-redirect-config.json missing in local/memories/" ;;
		selftest.cmr.active_mode)           echo "active mode:" ;;
		selftest.cmr.claudemd_present)      echo "CLAUDE.md instruction block present" ;;
		selftest.cmr.claudemd_missing)      echo "CLAUDE.md 'Memory — agentBrain only' block missing" ;;
		selftest.cmr.project_found)         echo "Current project found in" ;;
		selftest.cmr.memory_is_symlink)     echo "memory dir is symlink →" ;;
		selftest.cmr.symlink_to_brain)      echo "Symlink points to agentBrain" ;;
		selftest.cmr.symlink_wrong_target)  echo "Symlink does NOT point to agentBrain target" ;;
		selftest.cmr.write_through_ok)      echo "Write through symlink lands in agentBrain" ;;
		selftest.cmr.write_through_fail)    echo "Write through symlink NOT visible in agentBrain" ;;
		selftest.cmr.memory_not_symlink)    echo "memory dir exists but is NOT a symlink (mode is likely 'sync_hook' or 'instruction_only')" ;;
		selftest.cmr.memory_absent)         echo "memory dir does not exist (yet) for this project" ;;
		selftest.cmr.no_current_project)    echo "Current cwd is not a Claude project (no project dir found)" ;;

		selftest.uuid5.valid)               echo "uuid5-gen.sh produces valid UUID5:" ;;
		selftest.uuid5.invalid)             echo "uuid5-gen.sh did not return a valid UUID5" ;;
		selftest.uuid5.script_missing)      echo "scripts/uuid5-gen.sh missing or not executable" ;;
		selftest.uuid5.validate_present)    echo "claude-code-validate-note-id-hook.sh present" ;;
		selftest.uuid5.validate_missing)    echo "validate-note-id-hook.sh missing (PostToolUse validation)" ;;

		selftest.schema.passes)             echo "check-session-schema.sh passes" ;;
		selftest.schema.fails)              echo "check-session-schema.sh failed:" ;;

		selftest.summary.all_good)          echo "All working." ;;
		selftest.summary.all_good_hint)     echo "Start a fresh Claude Code session and write a test memory, or let the Stop-event fire on its own — both land in agentBrain automatically." ;;
		selftest.summary.failures)          echo "There are failure(s). See the lines above. Re-run \`bash system/addons/<name>/install.sh\` if hooks/symlinks are missing." ;;

		# Install (session-journal)
		install.sj.seeded)                  echo "seeded local config:" ;;
		install.sj.config_exists)           echo "local config already exists (left untouched):" ;;
		install.sj.hooks_registered)        echo "hooks registered in" ;;
		install.sj.hooks_missing)           echo "hooks NOT found in settings.json — register manually:" ;;
		install.sj.slash_present)           echo "/journal slash command present:" ;;
		install.sj.slash_missing)           echo "/journal slash command missing:" ;;
		install.sj.done)                    echo "Done. Restart Claude Code (or wait for the next session) for hooks to take effect." ;;

		# Install (claude-memory-redirect)
		install.cmr.seeded)                 echo "seeded local config:" ;;
		install.cmr.config_exists)          echo "local config exists (left untouched)" ;;
		install.cmr.active_mode)            echo "active mode:" ;;
		install.cmr.section_migrate)        echo "Migrate" ;;
		install.cmr.section_activation)     echo "Mode activation" ;;
		install.cmr.section_claudemd)       echo "CLAUDE.md instruction" ;;
		install.cmr.mode_instruction_only)  echo "instruction_only — relies on CLAUDE.md to guide Claude" ;;
		install.cmr.mode_disabled)          echo "addon disabled in config — nothing to activate" ;;
		install.cmr.unknown_mode)           echo "unknown mode:" ;;
		install.cmr.sync_hook_register)     echo "Add this to ~/.claude/settings.json under .hooks.PostToolUse:" ;;
		install.cmr.sync_hook_present)      echo "sync hook already registered" ;;
		install.cmr.claudemd_present)       echo "CLAUDE.md instruction block present" ;;
		install.cmr.claudemd_missing)       echo "CLAUDE.md missing the 'Memory — agentBrain only' block — add from README" ;;
		install.cmr.done)                   echo "Done. (Re)start Claude Code so it picks up the new memory routing." ;;

		# Selftest — agent-agnostic dispatcher
		selftest.section.frontmatter)       echo "Frontmatter validation" ;;
		selftest.frontmatter.passes)        echo "check-frontmatter.sh passes" ;;
		selftest.frontmatter.fails)         echo "check-frontmatter.sh failed:" ;;
		selftest.frontmatter.script_missing) echo "check-frontmatter.sh missing or not executable" ;;
		selftest.agent.not_detected)        echo "not detected on this machine" ;;

		# Selftest — Pi
		selftest.pi.cli_present)            echo "pi CLI present" ;;
		selftest.pi.cli_missing)            echo "pi CLI not on PATH" ;;
		selftest.pi.home_present)           echo "~/.pi config dir present:" ;;
		selftest.pi.home_missing)           echo "~/.pi config dir missing:" ;;
		selftest.pi.extensions_linked)      echo "Extensions symlinked from system/pi-config/" ;;
		selftest.pi.extensions_partial)     echo "Extensions partially symlinked" ;;
		selftest.pi.extensions_dir_missing) echo "extensions dir missing:" ;;
		selftest.pi.skills_linked)          echo "Skills symlinked into ~/.pi/agent/skills/" ;;
		selftest.pi.skills_empty)           echo "~/.pi/agent/skills/ exists but is empty" ;;
		selftest.pi.skills_dir_missing)     echo "skills dir missing:" ;;
		selftest.pi.tsconfig_present)       echo "tsconfig.json present in ~/.pi/agent/" ;;
		selftest.pi.tsconfig_missing)       echo "tsconfig.json missing — run configure-pi.sh" ;;

		# Selftest — Copilot CLI
		selftest.copilot.pointer_present)   echo "copilot-instructions.md pointer present:" ;;
		selftest.copilot.pointer_missing)   echo "copilot-instructions.md pointer missing:" ;;
		selftest.copilot.pointer_links_brain) echo "Pointer references agentBrain" ;;
		selftest.copilot.pointer_no_brain_ref) echo "Pointer does not reference agentBrain — may have been overwritten manually" ;;
		selftest.copilot.skills_present)    echo "Skills present in ~/.copilot/skills/" ;;
		selftest.copilot.skills_empty)      echo "~/.copilot/skills/ exists but is empty" ;;
		selftest.copilot.skills_dir_absent) echo "no ~/.copilot/skills/ — Copilot CLI may use .github/skills/ in projects" ;;

		# Selftest — Gemini CLI
		selftest.gemini.pointer_present)    echo "GEMINI.md pointer present:" ;;
		selftest.gemini.pointer_missing)    echo "GEMINI.md pointer missing:" ;;
		selftest.gemini.pointer_links_brain) echo "Pointer references agentBrain" ;;
		selftest.gemini.pointer_no_brain_ref) echo "Pointer does not reference agentBrain — may have been overwritten manually" ;;

		# Fallback: return the key itself so missing translations are visible.
		*) echo "$1" ;;
	esac
}

# Expose the resolved locale for debug/banner use.
agentbrain_locale() { echo "$_AGENTBRAIN_LOCALE"; }
