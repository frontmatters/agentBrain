#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# vault-pre-commit.sh — the vault's pre-commit gate, versioned SOURCE.
#
# Installed into every vault by scripts/sync/sync-agentbrain-local.sh (idempotent
# self-heal, into whatever directory core.hooksPath names). Until 2026-09-05 this
# file carried only the note-id layer while the maintainer's own vault ran four;
# a fresh install got no secret scan, no NDA gate and no intake check at commit
# time, and nothing compared the two. This is now the one copy.
#
# pre-commit (local/ repo) — validates UUID5 frontmatter on staged .md files.
#
# Per the agent-agnostic + always-validate principle: every commit to local/
# should pass the same content rules that doctor.sh enforces.
#
# Layers:
#   1. validate-note-id.sh on each staged .md (cheap, per-file)
#   2. check-agentbrain-local.sh — plaintext-secret scan over the working tree.
#      This vault is private, so private URLs and project names are allowed; the
#      scan blocks high-confidence credential patterns only. It ran in doctor
#      before, which is after the fact — a pushed secret stays in the history.
#   3. (deferred) full check-local-content.sh — covers wikilinks too but scans
#      the entire tree; would slow commits noticeably
#
# Skip-escape: COMMIT_SKIP_VALIDATE=1 git commit … (use sparingly)

set -euo pipefail

if [[ "${COMMIT_SKIP_VALIDATE:-0}" = "1" ]]; then
  echo "pre-commit (vault/): COMMIT_SKIP_VALIDATE=1 — skipping note validation" >&2
  exit 0
fi

# Resolve agentBrain root (where validate-note-id.sh lives).
BRAIN_DIR="${BRAIN_DIR:-$(realpath ~/agentBrain 2>/dev/null \
                       || (cd ~/agentBrain 2>/dev/null && pwd -P))}"
VALIDATOR="$BRAIN_DIR/scripts/validate-note-id.sh"

if [ ! -x "$VALIDATOR" ]; then
  echo "pre-commit (local/): validate-note-id.sh not found at $VALIDATOR — skipping" >&2
  exit 0
fi

# Collect staged .md files (NUL-safe).
staged=()
while IFS= read -r -d '' path; do
  [[ "$path" == *.md ]] && staged+=("$path")
done < <(git diff --cached --name-only -z --diff-filter=ACMR)

if [[ ${#staged[@]} -eq 0 ]]; then
  exit 0
fi

# Validate each. The repo root maps to `local/` inside the brain.
fail=0
for rel_local in "${staged[@]}"; do
  abs="$BRAIN_DIR/vault/$rel_local"
  if [ -f "$abs" ]; then
    if ! "$VALIDATOR" "$abs"; then
      fail=1
    fi
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "✗ pre-commit (vault/) BLOCKED: at least one staged file failed UUID5 validation." >&2
  echo "  Fix: regenerate id via 'bash \$BRAIN_DIR/scripts/uuid5-gen.sh local/<path-no-ext>'" >&2
  echo "  Bypass (use sparingly): COMMIT_SKIP_VALIDATE=1 git commit …" >&2
  exit 1
fi

# --- layer 2: plaintext-secret scan -----------------------------------------
# Missing checkout or missing check → don't block on infrastructure; doctor
# remains the backstop. A present check that FAILS does block.
SECRET_CHECK="$BRAIN_DIR/scripts/checks/check-agentbrain-local.sh"
if [ -x "$SECRET_CHECK" ]; then
  if ! bash "$SECRET_CHECK" >/tmp/agentbrain-secret-scan.$$ 2>&1; then
    echo "" >&2
    echo "✗ pre-commit (vault/) BLOCKED: possible plaintext secret in the vault." >&2
    sed 's/^/    /' /tmp/agentbrain-secret-scan.$$ >&2
    rm -f /tmp/agentbrain-secret-scan.$$
    echo "  Bypass (use sparingly): COMMIT_SKIP_VALIDATE=1 git commit …" >&2
    exit 1
  fi
  rm -f /tmp/agentbrain-secret-scan.$$
fi

# --- layer 3: owner material outside its space ------------------------------
# Ratchet, not amnesty: the baseline of pre-existing material is exempted in
# local/.nda-allow, so this blocks what is NEW. Staged-only, so it costs ~50ms.
NDA_CHECK="$BRAIN_DIR/scripts/checks/check-nda.sh"
if [ -x "$NDA_CHECK" ]; then
  if ! bash "$NDA_CHECK" --staged >/tmp/agentbrain-nda.$$ 2>&1; then
    echo "" >&2
    sed 's/^/  /' /tmp/agentbrain-nda.$$ >&2
    rm -f /tmp/agentbrain-nda.$$
    echo "  Bypass (use sparingly): COMMIT_SKIP_VALIDATE=1 git commit …" >&2
    exit 1
  fi
  rm -f /tmp/agentbrain-nda.$$
fi

# --- layer 4: invisible characters carried in from outside -------------------
# The vault is read back by agents at session start, so imported text is
# untrusted input. Measured: 188 zero-width characters already sit in the
# vault, all of them in archive/chatgpt-2023-2024/ — an import, not a note
# anyone typed. Staged-only, so this gates what is new.
INTAKE_CHECK="$BRAIN_DIR/scripts/checks/check-intake.sh"
if [ -x "$INTAKE_CHECK" ]; then
  if ! bash "$INTAKE_CHECK" --staged >/tmp/agentbrain-intake.$$ 2>&1; then
    echo "" >&2
    sed 's/^/  /' /tmp/agentbrain-intake.$$ >&2
    rm -f /tmp/agentbrain-intake.$$
    echo "  Fix zero-width residue: bash $INTAKE_CHECK --fix <file>" >&2
    echo "  Bypass (use sparingly): COMMIT_SKIP_VALIDATE=1 git commit …" >&2
    exit 1
  fi
  rm -f /tmp/agentbrain-intake.$$
fi
