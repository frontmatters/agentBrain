#!/usr/bin/env bash
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

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOCAL="${VAULT}/local"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# confirm <prompt> [<default Y|N>] — honours AGENTBRAIN_ASSUME_YES for unattended runs;
# a non-TTY run without it skips (returns non-zero) so the caller can ask and re-run.
confirm() {
	local prompt="$1" default="${2:-N}"
	[ "${AGENTBRAIN_ASSUME_YES:-}" = "1" ] && return 0
	if [ -t 0 ]; then
		local hint="[y/N]"
		[ "$default" = "Y" ] && hint="[Y/n]"
		read -p "$prompt $hint " -n 1 -r
		echo
		if [ "$default" = "Y" ]; then [[ ! $REPLY =~ ^[Nn]$ ]]; else [[ $REPLY =~ ^[Yy]$ ]]; fi
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

# ── Case A: `local` is already a symlink ────────────────────────────
# Idempotent. Honour it; only warn if an explicit request points elsewhere (re-pointing
# could orphan a populated vault, so we refuse to do it silently).
if [ -L "$LOCAL" ]; then
	current="$(readlink "$LOCAL")"
	if [ -n "$VAULT_PATH" ]; then
		VAULT_PATH="${VAULT_PATH/#\~/$HOME}"
		req="$(cd "$(dirname "$VAULT_PATH")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$VAULT_PATH")")"
		if [ "$current" != "$VAULT_PATH" ] && [ "$current" != "$req" ]; then
			echo -e "${YELLOW}!${NC} local/ already links to $current (requested $VAULT_PATH)."
			echo "  Leaving it. To re-point, move knowledge yourself then recreate the link."
		fi
	fi
	if [ ! -e "$LOCAL" ]; then
		echo -e "${YELLOW}!${NC} local/ is a DANGLING symlink -> $current — the private vault is unreachable."
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
if [ -z "$VAULT_PATH" ]; then
	if [ -d "$DEFAULT_VAULT" ] && [ "$DEFAULT_VAULT" != "$LOCAL" ] &&
		[ -t 0 ] && [ "${AGENTBRAIN_ASSUME_YES:-}" != "1" ]; then
		echo "A shared vault already exists at $DEFAULT_VAULT."
		if confirm "Point this checkout's local/ at it (share knowledge across checkouts)?" Y; then
			VAULT_PATH="$DEFAULT_VAULT"
		else
			echo "  Keeping a separate local/ for this checkout."
			exit 0
		fi
	else
		exit 0 # default: real local/ dir, created by setup-structure.sh
	fi
fi

VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

# ── Case B: link local/ -> VAULT_PATH, migrating any existing content ──
if [ ! -e "$LOCAL" ]; then
	# No local/ yet: ensure the vault exists, then link.
	mkdir -p "$VAULT_PATH"
	ln -sfn "$VAULT_PATH" "$LOCAL"
	echo -e "${GREEN}Linked${NC} local/ -> $VAULT_PATH"
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
	ln -sfn "$VAULT_PATH" "$LOCAL"
	echo -e "${GREEN}Migrated${NC} local/ -> $VAULT_PATH (now shared)"
	exit 0
fi

# Vault exists AND local/ exists — both real dirs.
if ! dir_has_content "$LOCAL"; then
	# Empty local/: safe to discard and link.
	rmdir "$LOCAL"
	ln -sfn "$VAULT_PATH" "$LOCAL"
	echo -e "${GREEN}Linked${NC} local/ -> $VAULT_PATH"
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
	ln -sfn "$VAULT_PATH" "$LOCAL"
	echo -e "${GREEN}Merged${NC} local/ -> $VAULT_PATH (now shared)"
	exit 0
fi

# Conflict: both hold content. Refuse — merging is the user's call, never silent data loss.
echo -e "${YELLOW}!${NC} Both local/ and $VAULT_PATH contain content — cannot link automatically."
echo "  Merge them by hand, then: rm -rf '$LOCAL' && ln -sfn '$VAULT_PATH' '$LOCAL'"
exit 0
