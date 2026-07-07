#!/usr/bin/env bash
# setup-shared-vault.sh — establish the top-level `shared/` layer: a symlink into a
# local clone of a scope's git repo. Host-agnostic, idempotent, data-safe.
#
# Remote selection (first match wins):
#   --remote=URL / AGENTBRAIN_SHARED_REMOTE=URL   BYO remote (cloned)
#   --bootstrap                                   git init --bare a local remote, then clone
#   (none)                                        instruct the user to pass --remote/--bootstrap
#
# Vault dir (the clone): --vault=PATH / AGENTBRAIN_SHARED_VAULT / default ~/.agentBrain/shared
set -euo pipefail

ROOT_DIR="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
SHARED_LINK="${ROOT_DIR}/shared"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REMOTE="${AGENTBRAIN_SHARED_REMOTE:-}"
SHARED_VAULT="${AGENTBRAIN_SHARED_VAULT:-${HOME}/.agentBrain/shared}"
BOOTSTRAP=0

if [ $# -gt 0 ]; then
  for a in "$@"; do
    case "$a" in
      --remote=*) REMOTE="${a#--remote=}" ;;
      --vault=*)  SHARED_VAULT="${a#--vault=}" ;;
      --bootstrap) BOOTSTRAP=1 ;;
    esac
  done
fi

SHARED_VAULT="${SHARED_VAULT/#\~/$HOME}"

fail() { printf '%b! %s\n' "${YELLOW}" "$*${NC}" >&2; exit 1; }

if [ -L "$SHARED_LINK" ]; then
  if [ ! -e "$SHARED_LINK" ]; then
    fail "shared/ is a DANGLING symlink -> $(readlink "$SHARED_LINK"). Restore target or remove and re-run."
  fi
  printf '%bOK%b shared/ already linked -> %s\n' "${GREEN}" "${NC}" "$(readlink "$SHARED_LINK")"
  exit 0
fi

if [ -e "$SHARED_LINK" ] && [ ! -L "$SHARED_LINK" ]; then
  fail "shared/ exists as a real path; refusing to overwrite. Move it aside and re-run."
fi

if [ ! -d "${SHARED_VAULT}/.git" ]; then
  # Clone stderr goes to a temp log, shown on failure — a silent "clone failed"
  # (auth? DNS? wrong URL?) is undebuggable otherwise.
  CLONE_LOG="$(mktemp "${TMPDIR:-/tmp}/agentbrain-shared-clone.XXXXXX")"
  if [ -n "$REMOTE" ]; then
    printf 'Cloning shared scope from %s\n' "$REMOTE"
    if ! git clone "$REMOTE" "$SHARED_VAULT" 2>"$CLONE_LOG"; then
      cat "$CLONE_LOG" >&2
      fail "Clone failed. Is the remote reachable and do you have access (ssh keys / token)?"
    fi
    rm -f "$CLONE_LOG"
  elif [ "$BOOTSTRAP" = "1" ]; then
    BARE="${HOME}/.agentBrain/shared-remote.git"
    if [ ! -d "$BARE" ]; then
      git init --bare -b main "$BARE" >/dev/null \
        || fail "Could not create bare repo at $BARE (writable path?)."
    fi
    if [ ! -d "${SHARED_VAULT}/.git" ]; then
      if ! git clone "$BARE" "$SHARED_VAULT" 2>"$CLONE_LOG"; then
        cat "$CLONE_LOG" >&2
        fail "Could not clone the bootstrap bare repo at $BARE."
      fi
      rm -f "$CLONE_LOG"
      # Force the branch to 'main' so it matches sync-agentbrain-shared.sh (which targets
      # main); without this the clone of an empty bare defaults to the host's init branch
      # (often 'master'), leaving sync to create a second, divergent 'main'.
      if ! ( cd "$SHARED_VAULT" \
        && git -c user.email=brain@local -c user.name=agentBrain \
             commit --allow-empty -m "init shared scope" >/dev/null \
        && git branch -M main \
        && git push -u origin main >/dev/null 2>&1 ); then
        printf '%b!%b Could not init/push branch main to the bootstrap remote — run "git push -u origin main" inside %s manually.\n' \
          "${YELLOW}" "${NC}" "$SHARED_VAULT" >&2
      fi
    fi
  else
    fail "No shared scope configured. Pass --remote=URL (BYO) or --bootstrap (local bare repo)."
  fi
fi

ln -sfn "$SHARED_VAULT" "$SHARED_LINK"
printf '%bLinked%b shared/ -> %s\n' "${GREEN}" "${NC}" "$SHARED_VAULT"

if [ -n "$REMOTE" ]; then
  if printf '%s' "$REMOTE" | grep -qiE 'github\.com|gitlab\.com'; then
    printf '%b!%b Remote looks public (%s). shared/ is NOT private — ensure repo visibility is private/internal.\n' \
      "${YELLOW}" "${NC}" "$REMOTE"
  fi
fi
