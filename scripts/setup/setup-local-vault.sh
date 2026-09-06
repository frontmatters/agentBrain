#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-local-vault.sh — Establish the private `local/` layer as either a real
# directory (default) or a symlink into a shared central vault.
#
# Why this exists: knowledge must live ONCE. A user running multiple checkouts of
# the same brain (e.g. `agentBrain` + `agentBrain-dev`) wants both to share a single
# private store so a `brain use dev|live` flip never touches knowledge. That is done
# by pointing each checkout's `local/` at one central vault. Until now this symlink
# was assumed by the validators (check-anchors.sh, check-local-content.sh) but created
# by no setup step — a fresh clone got a real, unshared `local/`. This step closes that.
#
# Vault selection (first match wins):
#   --vault=PATH / AGENTBRAIN_VAULT=PATH   explicit shared vault (strongest)
#   existing `local` symlink               keep its current target (idempotent)
#   existing ~/.agentBrain/vault dir        offer to link (a vault already exists)
#   otherwise                              real ./local dir, no symlink (the default)
#
# Data safety: an existing real `local/` is never destroyed. It is moved into the
# vault losslessly (it BECOMES the vault when the vault is absent), or merged only
# when the vault is empty. If both sides hold content, this refuses and asks the user
# to merge manually. Safe to re-run (idempotent).

set -euo pipefail
# shellcheck disable=SC1091
. "${VAULT}/scripts/installer/prompt-helper.sh"


VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LOCAL="${VAULT}/local"
ALIAS="${VAULT}/vault"

# `vault` is the link's name; `local` was the older name. Every note id hashes
# the local/ spelling and uuid5-gen.sh folds vault/ to it, so the rename never
# touched an id. An older install still carries local/: a plain directory
# becomes vault/, a link becomes the vault/ link. The local/ alias is not
# created any more; drop-local-alias.sh retires one that is still there once
# the agents' own links no longer run through it. Runs via the EXIT trap below.
# shellcheck disable=SC2329,SC2317  # invoked indirectly, via the EXIT trap below.
link_vault_alias() {
	[ -e "$LOCAL" ] || return 0            # nothing older to carry over
	[ -L "$ALIAS" ] && return 0            # vault/ is in place, idempotent
	[ -e "$ALIAS" ] && {                   # a real file/dir named vault: never touch it
		echo -e "${YELLOW}!${NC} ${ALIAS} exists and is not a symlink — leaving it alone." >&2
		return 0
	}
	if [ -L "$LOCAL" ]; then
		ln -sfn "$(readlink "$LOCAL")" "$ALIAS" && echo -e "${GREEN}Linked${NC} vault/ -> the vault (local/ is the old name; drop-local-alias.sh retires it)"
	else
		# a plain local/ directory from an older install: it becomes vault/
		mv "$LOCAL" "$ALIAS" && echo -e "${GREEN}Renamed${NC} local/ -> vault/"
	fi
}
# The workspace sits beside the vault, never inside it. Working material cannot
# meet the standard the vault holds its notes to, and asking it to is how an
# 89 MB third-party clone once produced 2521 schema failures. Created here so
# there is somewhere to put such a thing before someone puts it in the vault.
# shellcheck disable=SC2329,SC2317  # invoked indirectly, via the EXIT trap.
ensure_workspace() {
	local ws="${AGENTBRAIN_HOME:-$HOME}/.agentBrain/workspace"
	[ -d "$ws" ] && return 0
	mkdir -p "$ws/external" "$ws/derived" "$ws/scratch" || return 0
	[ -f "$BRAIN_README_SRC" ] && cp "$BRAIN_README_SRC" "$ws/README.md"
	echo -e "${GREEN}Created${NC} workspace/ beside the vault (external/, derived/, scratch/)"
}
BRAIN_README_SRC="$VAULT/templates/workspace-readme.md"

# Both run on every exit path, so both are defined before the trap is set.
trap 'link_vault_alias; ensure_workspace' EXIT

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# confirm <prompt> [<default Y|N>] — honours AGENTBRAIN_ASSUME_YES for unattended runs;
# a non-TTY run without it skips (returns non-zero) so the caller can ask and re-run.
confirm() {
	local prompt="$1" default="${2:-N}"
	[ "${AGENTBRAIN_ASSUME_YES:-}" = "1" ] && return 0
	if [ -t 0 ]; then
		local layout="no"
		[ "$default" = "Y" ] && layout="yes"
		ab_prompt_confirm --default "$layout" "$prompt"
		return
	fi
	echo "[non-interactive] skipped: $prompt"
	echo "  -> set AGENTBRAIN_VAULT=PATH and AGENTBRAIN_ASSUME_YES=1 to proceed, or ask the user."
	return 1
}

# dir_has_content <path> — true if path is a non-empty directory (any entry incl. dotfiles).
dir_has_content() {
	[ -d "$1" ] || return 1
	[ -n "$(ls -A "$1" 2>/dev/null)" ]
}

# ── Resolve the requested vault path ────────────────────────────────
# Flag wins over env; expand a leading ~. Empty means "no explicit request".
VAULT_PATH="${AGENTBRAIN_VAULT:-}"
for _arg in "$@"; do
	case "$_arg" in
	--vault=*) VAULT_PATH="${_arg#--vault=}" ;;
	esac
done

# ── Case A: the vault link is already there (vault/, or local/ on an older install) ──
# Idempotent. Honour it; only warn if an explicit request points elsewhere (re-pointing
# could orphan a populated vault, so we refuse to do it silently).
LINK="$ALIAS"; [ -L "$LINK" ] || LINK="$LOCAL"
if [ -L "$LINK" ]; then
	current="$(readlink "$LINK")"
	if [ -n "$VAULT_PATH" ]; then
		VAULT_PATH="${VAULT_PATH/#\~/$HOME}"
		req="$(cd "$(dirname "$VAULT_PATH")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$VAULT_PATH")")"
		if [ "$current" != "$VAULT_PATH" ] && [ "$current" != "$req" ]; then
			echo -e "${YELLOW}!${NC} $(basename "$LINK")/ already links to $current (requested $VAULT_PATH)."
			echo "  Leaving it. To re-point, move knowledge yourself then recreate the link."
		fi
	fi
	if [ ! -e "$LINK" ]; then
		echo -e "${YELLOW}!${NC} $(basename "$LINK")/ is a DANGLING symlink -> $current — your vault is unreachable."
		echo "  Restore the target or remove the link and re-run."
		# Halt the install: later steps write into local/ and would fail through
		# the broken link anyway, but with a far more confusing error. Exiting
		# non-zero lets setup.sh (set -e) stop here with this clear message.
		exit 1
	fi
	exit 0
fi

# ── No explicit request: maybe offer an existing default vault ──────
# If a central vault already exists, a sibling checkout almost certainly wants to share
# it — OFFER to link, but only interactively. Adopting a pre-existing vault is a
# meaningful action, so unattended runs (--yes / non-TTY) require an explicit --vault
# rather than silently adopting whatever happens to sit at the default path (this keeps
# CI/install-validation deterministic). Otherwise the default is a real local/ dir,
# which Structure populates next.
DEFAULT_VAULT="${AGENTBRAIN_HOME:-$HOME}/.agentBrain/vault"

# The vault never lives inside the checkout. Without an explicit --vault it is
# ~/.agentBrain/vault (AGENTBRAIN_HOME overrides $HOME): created when absent,
# adopted when present, and every checkout on the machine shares it. A
# checkout is disposable; the vault is not, and a vault inside a checkout is
# how knowledge gets deleted with a directory.
if [ -z "$VAULT_PATH" ]; then
	VAULT_PATH="$DEFAULT_VAULT"
	[ -d "$VAULT_PATH" ] && echo "Using the vault at $VAULT_PATH (shared by every checkout on this machine)."
fi

VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

# ── Case B: link local/ -> VAULT_PATH, migrating any existing content ──
if [ ! -e "$LOCAL" ]; then
	# No local/ yet: ensure the vault exists, then link.
	mkdir -p "$VAULT_PATH"
	ln -sfn "$VAULT_PATH" "$ALIAS"
	echo -e "${GREEN}Linked${NC} vault/ -> $VAULT_PATH"
	exit 0
fi

# local/ exists as a real directory here (not a symlink — Case A returned above).
if [ ! -d "$VAULT_PATH" ]; then
	# Vault absent: the existing local/ losslessly BECOMES the vault. No merge, no data risk.
	if dir_has_content "$LOCAL"; then
		confirm "Move existing local/ to $VAULT_PATH and link it back?" Y ||
			{ echo "  Skipped — local/ left as a real dir."; exit 0; }
	fi
	mkdir -p "$(dirname "$VAULT_PATH")"
	mv "$LOCAL" "$VAULT_PATH"
	ln -sfn "$VAULT_PATH" "$ALIAS"
	echo -e "${GREEN}Migrated${NC} local/ -> $VAULT_PATH (now shared, as vault/)"
	exit 0
fi

# Vault exists AND local/ exists — both real dirs.
if ! dir_has_content "$LOCAL"; then
	# Empty local/: safe to discard and link.
	rmdir "$LOCAL"
	ln -sfn "$VAULT_PATH" "$ALIAS"
	echo -e "${GREEN}Linked${NC} vault/ -> $VAULT_PATH"
	exit 0
fi

if ! dir_has_content "$VAULT_PATH"; then
	# Empty vault: move local/ content into it, then link.
	confirm "Move local/ content into $VAULT_PATH and link it?" Y ||
		{ echo "  Skipped — local/ left as a real dir."; exit 0; }
	# dotglob so dotfiles move too; nullglob so an only-dotfiles dir doesn't break.
	shopt -s dotglob nullglob
	mv "$LOCAL"/* "$VAULT_PATH"/
	shopt -u dotglob nullglob
	rmdir "$LOCAL"
	ln -sfn "$VAULT_PATH" "$ALIAS"
	echo -e "${GREEN}Merged${NC} local/ -> $VAULT_PATH (now shared, as vault/)"
	exit 0
fi

# Conflict: both hold content. Refuse — merging is the user's call, never silent data loss.
echo -e "${YELLOW}!${NC} Both local/ and $VAULT_PATH contain content — cannot link automatically."
echo "  Merge them by hand, then: mv '$LOCAL' '$LOCAL.merged' && ln -sfn '$VAULT_PATH' '$ALIAS'"
exit 0
