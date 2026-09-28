#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# flow.sh — install-flow journal: main (install.sh) is the traffic controller;
# this file is its logbook + state. The step PLAN lives in install.sh; the
# journal answers: which flow, which step now, which subflow started, where it
# came from, what is next. Subflows inherit the journal via the environment.
#
# Requires platform.sh to be sourced first (flow_init records platform_id).
#
# Usage:
#   source scripts/installer/flow.sh
#   flow_init "install-<platform_id>-<ts>"
#   flow_begin "bootstrap-linux" "tools+brain+pi+doctor"; ...; flow_end "bootstrap-linux" "$rc"
#
# Journal: ${AB_INSTALL_STATE_DIR:-${TMPDIR:-/tmp}/agentbrain-install}/<flow-id>.journal

FLOW_ID=""
AB_INSTALL_JOURNAL="${AB_INSTALL_JOURNAL:-}"

flow_init() { # flow_init <flow-id>
	FLOW_ID="$1"
	local dir="${AB_INSTALL_STATE_DIR:-${TMPDIR:-/tmp}/agentbrain-install}"
	mkdir -p "$dir"
	AB_INSTALL_JOURNAL="$dir/$FLOW_ID.journal"
	export AB_INSTALL_JOURNAL FLOW_ID
	{
		echo "flow: $FLOW_ID"
		echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
		echo "platform: $(platform_id) (flavor: $(platform_flavor))"
		echo "host: $(hostname 2>/dev/null || echo unknown)"
	} >> "$AB_INSTALL_JOURNAL"
}

flow_begin() { # flow_begin <step> [detail]
	[ -n "$AB_INSTALL_JOURNAL" ] || return 0
	echo "begin: $1 ${2:-}" >> "$AB_INSTALL_JOURNAL"
}

flow_end() { # flow_end <step> <rc>
	[ -n "$AB_INSTALL_JOURNAL" ] || return 0
	echo "end: $1 rc=$2" >> "$AB_INSTALL_JOURNAL"
}
