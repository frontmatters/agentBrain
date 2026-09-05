#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# lib/locale.sh — resolve the active locale for a write path (agentBrain i18n, Fase 1).
#
# Emission is locale-specific: a note written under a space inherits that space's
# locale; otherwise the vault default (brain.json `defaultLocale`) applies; otherwise
# `en`. Detection stays locale-agnostic elsewhere. See local/specs/agentbrain-i18n.md.
#
# API:
#   locale_for <write-path> [root]   echo the locale code (e.g. nl, en). Never empty.

# brain.json top-level `defaultLocale` (no jq dependency).
_locale_brain_default() {
	grep -oE '"defaultLocale"[[:space:]]*:[[:space:]]*"[^"]*"' "$1/brain.json" 2>/dev/null \
		| sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/'
}

# `locale:` from a space paspoort frontmatter (local/spaces/<slug>/index.md).
_locale_space() {  # $1 root, $2 slug
	local pp="$1/vault/spaces/$2/index.md"
	[ -f "$pp" ] || return 1
	awk -F'locale:' '/^locale:/{gsub(/[ "'"'"']/,"",$2); print $2; exit}' "$pp"
}

# locale_for <write-path> [root] -> space override, else vault default, else en.
locale_for() {
	local path="$1" root="${2:-.}" slug="" loc=""
	# Match a spaces/<slug>/ segment, whether the path uses the local/ symlink or the
	# resolved vault path (…/vault/spaces/<slug>/…).
	case "$path" in
		*/spaces/*/*) slug="$(printf '%s' "$path" | sed -E 's#.*/spaces/([^/]+)/.*#\1#')" ;;
	esac
	[ -n "$slug" ] && loc="$(_locale_space "$root" "$slug")"
	[ -n "$loc" ] || loc="$(_locale_brain_default "$root")"
	[ -n "$loc" ] || loc="en"
	printf '%s\n' "$loc"
}
