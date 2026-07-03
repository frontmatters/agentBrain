#!/usr/bin/env bash
# Generic (agent-agnostic) selftest checks.
# Always runs. Verifies the agentBrain framework itself: vault root, the active-brain
# symlink, the UUID5 generator, the frontmatter validate hook, and session schema.
# Variables BRAIN_ROOT and the i18n `t` function are provided by the dispatcher.

run_generic() {
	hdr "$(t selftest.section.brain_root)"
	if [[ -d "$BRAIN_ROOT" ]]; then
		ok "$(t selftest.brain_root.present) $BRAIN_ROOT"
	else
		nok "$(t selftest.brain_root.missing) $BRAIN_ROOT"
	fi
	if [[ -L "$HOME/agentBrain" ]]; then
		local target; target="$(readlink "$HOME/agentBrain")"
		ok "$(t selftest.brain_root.symlink_intact) $target"
	elif [[ -d "$HOME/agentBrain" ]]; then
		ok "$(t selftest.brain_root.is_dir)"
	else
		nok "$(t selftest.brain_root.absent)"
	fi

	hdr "$(t selftest.section.uuid5)"
	if [[ -x "$BRAIN_ROOT/scripts/uuid5-gen.sh" ]]; then
		local probe; probe="$(bash "$BRAIN_ROOT/scripts/uuid5-gen.sh" "selftest/probe" 2>/dev/null || echo "")"
		if [[ "$probe" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
			ok "$(t selftest.uuid5.valid) $probe"
		else
			nok "$(t selftest.uuid5.invalid) ($probe)"
		fi
	else
		nok "$(t selftest.uuid5.script_missing)"
	fi
	if [[ -x "$BRAIN_ROOT/scripts/claude-code-validate-note-id-hook.sh" ]]; then
		ok "$(t selftest.uuid5.validate_present)"
	else
		wrn "$(t selftest.uuid5.validate_missing)"
	fi

	hdr "$(t selftest.section.frontmatter)"
	if [[ -x "$BRAIN_ROOT/scripts/check-frontmatter.sh" ]]; then
		local fm_out; fm_out="$(bash "$BRAIN_ROOT/scripts/check-frontmatter.sh" 2>&1 || true)"
		if [[ "$fm_out" == *"passed"* ]]; then
			ok "$(t selftest.frontmatter.passes)"
		else
			nok "$(t selftest.frontmatter.fails)"
			note "$fm_out"
		fi
	else
		wrn "$(t selftest.frontmatter.script_missing)"
	fi

	hdr "$(t selftest.section.session_schema)"
	if [[ -x "$BRAIN_ROOT/scripts/check-session-schema.sh" ]]; then
		local schema_out; schema_out="$(bash "$BRAIN_ROOT/scripts/check-session-schema.sh" 2>&1 || true)"
		if [[ "$schema_out" == *"passed"* ]] || [[ -z "$schema_out" ]]; then
			ok "$(t selftest.schema.passes)"
		else
			nok "$(t selftest.schema.fails) $schema_out"
		fi
	else
		wrn "$(t selftest.schema.script_missing)"
	fi
}
