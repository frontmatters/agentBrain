#!/usr/bin/env bash
# Install/remove the extract-learnings adapters per detected agent. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"
MODE="${1:-install}"
HOOK_REAL="$HERE/claude-precompact-hook.sh"
SETTINGS="$AGENT_HOME/.claude/settings.json"
# Register via the active-brain alias when it exists, so `brain use dev|live` flips the hook
# (like skills/configure-pi). Fall back to this checkout's path if there is no alias.
ALIAS_BASE="${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}"
if [ -e "$ALIAS_BASE" ]; then
  HOOK="$ALIAS_BASE/system/addons/extract-learnings/claude-precompact-hook.sh"
else
  HOOK="$HOOK_REAL"
fi

claude_register() {
  [ -d "$AGENT_HOME/.claude" ] || { echo "Skip Claude (no ~/.claude)"; return 0; }
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.bak"
  python3 - "$SETTINGS" "$HOOK" "$1" <<'PY'
import json,sys
path,hook,mode=sys.argv[1],sys.argv[2],sys.argv[3]
cfg=json.load(open(path)); hooks=cfg.setdefault("hooks",{}); arr=hooks.setdefault("PreCompact",[])
# Match by the hook script's identity (any path: alias OR checkout) so a path change replaces
# rather than duplicates our entry, and uninstall removes only ours.
MARK="extract-learnings/claude-precompact-hook.sh"
arr=[g for g in arr if not any(MARK in h.get("command","") for h in g.get("hooks",[]))]
if mode=="install":
    arr.append({"matcher":"*","hooks":[{"type":"command","command":hook}]})
hooks["PreCompact"]=arr
json.dump(cfg,open(path,"w"),indent=2); open(path,"a").write("\n")
PY
  rm -f "$SETTINGS.bak"
  label="$(printf '%s' "$1" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
  echo "$label Claude PreCompact adapter ($HOOK)"
}

case "$MODE" in
  install)   chmod +x "$HOOK_REAL"; claude_register install ;;
  --uninstall) claude_register uninstall ;;
  *) echo "usage: install.sh [install|--uninstall]"; exit 1 ;;
esac
# Pi adapter is the existing extension (configure-pi.sh symlinks it); nothing to do here.
