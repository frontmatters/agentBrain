#!/usr/bin/env bash
# Claude Code agent — session-journal + claude-memory-redirect addon checks.
# Migrated from scripts/selftest-claude-integration.sh.

detect_claude_code() {
	# Claude Code stores its config in ~/.claude. Treat the dir as the marker — the
	# CLI is not always on $PATH (it might run inside an IDE wrapper).
	[[ -d "$HOME/.claude" ]] || command -v claude &>/dev/null
}

run_claude_code() {
	local SETTINGS="$HOME/.claude/settings.json"

	# ── session-journal addon ──
	hdr "$(t selftest.section.session_journal)"
	local SJ="$BRAIN_ROOT/system/addons/session-journal"
	local f
	for f in journal-update.sh claude-stop-hook.sh claude-autosave-hook.sh \
	         journal-show.sh journal-save.sh journal-archive.sh \
	         config.default.json install.sh manifest.md README.md; do
		if [[ -f "$SJ/$f" ]]; then ok "$f $(t generic.present)"; else nok "$f $(t generic.missing)"; fi
	done
	for f in journal-update.sh claude-stop-hook.sh claude-autosave-hook.sh \
	         journal-show.sh journal-save.sh journal-archive.sh install.sh; do
		[[ -x "$SJ/$f" ]] || wrn "$f $(t generic.not_executable)"
	done
	if [[ -f "$BRAIN_ROOT/local/sessions/journal-config.json" ]]; then
		ok "$(t selftest.sj.config_seeded)"
	else
		nok "$(t selftest.sj.config_missing)"
	fi
	if grep -q "session-journal/claude-stop-hook.sh" "$SETTINGS" 2>/dev/null; then
		ok "$(t selftest.sj.stop_registered)"
	else
		nok "$(t selftest.sj.stop_not_registered)"
	fi
	if grep -q "session-journal/claude-autosave-hook.sh" "$SETTINGS" 2>/dev/null; then
		ok "$(t selftest.sj.autosave_registered)"
	else
		nok "$(t selftest.sj.autosave_not_registered)"
	fi
	if [[ -f "$HOME/.claude/commands/journal.md" ]]; then
		ok "$(t selftest.sj.slash_present)"
	else
		nok "$(t selftest.sj.slash_missing)"
	fi
	if [[ -f "$BRAIN_ROOT/local/sessions/session-journal.md" ]]; then
		local mt_human
		mt_human="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$BRAIN_ROOT/local/sessions/session-journal.md" 2>/dev/null \
		         || stat -c '%y' "$BRAIN_ROOT/local/sessions/session-journal.md" 2>/dev/null)"
		ok "$(t selftest.sj.journal_present) $mt_human)"
	else
		wrn "$(t selftest.sj.journal_pending)"
	fi
	local SJ_TEST_OUT
	SJ_TEST_OUT="$(echo '{}' | bash "$SJ/journal-update.sh" --stdin --source selftest 2>&1 || true)"
	if [[ "$SJ_TEST_OUT" == *"journal updated"* ]] || grep -q "(auto: selftest)" "$BRAIN_ROOT/local/sessions/session-journal.md" 2>/dev/null; then
		ok "$(t selftest.sj.update_works)"
	else
		wrn "$(t selftest.sj.update_unclear) ($SJ_TEST_OUT)"
	fi

	# ── claude-memory-redirect addon ──
	hdr "$(t selftest.section.memory_redirect)"
	local CMR="$BRAIN_ROOT/system/addons/claude-memory-redirect"
	for f in claude-memory-migrate.sh claude-memory-symlink.sh claude-memory-sync-hook.sh \
	         slug.sh config.default.json install.sh manifest.md README.md; do
		if [[ -f "$CMR/$f" ]]; then ok "$f $(t generic.present)"; else nok "$f $(t generic.missing)"; fi
	done
	for f in claude-memory-migrate.sh claude-memory-symlink.sh claude-memory-sync-hook.sh slug.sh install.sh; do
		[[ -x "$CMR/$f" ]] || wrn "$f $(t generic.not_executable)"
	done
	if [[ -f "$BRAIN_ROOT/local/memories/claude-redirect-config.json" ]]; then
		ok "$(t selftest.cmr.config_seeded)"
		local mode
		mode="$(python3 -c "
import json
print(json.load(open('$BRAIN_ROOT/local/memories/claude-redirect-config.json')).get('mode','?'))
" 2>/dev/null || echo "?")"
		note "$(t selftest.cmr.active_mode) $mode"
	else
		nok "$(t selftest.cmr.config_missing)"
	fi
	if grep -q "Memory — alleen via agentBrain\|Memory — agentBrain only" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
		ok "$(t selftest.cmr.claudemd_present)"
	else
		nok "$(t selftest.cmr.claudemd_missing)"
	fi

	local projects_root="$HOME/.claude/projects"
	local pwd_encoded; pwd_encoded="$(printf '%s' "$PWD" | tr '/_ ' '---')"
	local cur_proj="$projects_root/$pwd_encoded"

	if [[ -d "$cur_proj" ]]; then
		ok "$(t selftest.cmr.project_found) $projects_root"
		local mem_path="$cur_proj/memory"
		if [[ -L "$mem_path" ]]; then
			local target; target="$(readlink "$mem_path")"
			ok "$(t selftest.cmr.memory_is_symlink) $target"
			if [[ "$target" == "$BRAIN_ROOT"* ]]; then
				ok "$(t selftest.cmr.symlink_to_brain)"
			else
				wrn "$(t selftest.cmr.symlink_wrong_target) ($target)"
			fi
			local test_file="$mem_path/.selftest-$$"
			local expected="$target/.selftest-$$"
			echo "selftest" > "$test_file" 2>/dev/null
			if [[ -f "$expected" ]] && [[ "$(cat "$expected")" == "selftest" ]]; then
				ok "$(t selftest.cmr.write_through_ok)"
				rm -f "$test_file"
			else
				nok "$(t selftest.cmr.write_through_fail) ($expected)"
			fi
		elif [[ -d "$mem_path" ]]; then
			wrn "$(t selftest.cmr.memory_not_symlink)"
		else
			wrn "$(t selftest.cmr.memory_absent)"
		fi
	else
		wrn "$(t selftest.cmr.no_current_project)"
	fi
}
