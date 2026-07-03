#!/usr/bin/env bash
# setup-addon-launchd.sh — generic launchd installer for any addon that declares
# a `schedule:` block in its manifest. Reads the manifest, renders
# system/launchd/addon.plist.template, and bootstraps the LaunchAgent.
#
# Convention: addon entrypoint is system/addons/<id>/bin/<id>.
#
# Usage:
#   bash scripts/setup-addon-launchd.sh install <addon-id>
#   bash scripts/setup-addon-launchd.sh uninstall <addon-id>
#   bash scripts/setup-addon-launchd.sh kickstart <addon-id>
#   bash scripts/setup-addon-launchd.sh status <addon-id>
#
# macOS only. Other platforms: exit 2.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "setup-addon-launchd: macOS only — skip" >&2
    exit 2
fi

VAULT="${VAULT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TEMPLATE="${VAULT}/system/launchd/addon.plist.template"
LOGS_DIR="${VAULT}/local/logs"
LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"

CMD="${1:-}"
ID="${2:-}"

if [[ -z "$CMD" || -z "$ID" ]]; then
    echo "usage: $(basename "$0") install|uninstall|kickstart|status <addon-id>" >&2
    exit 2
fi

# Resolve the addon's directory across both roots — a local/downloaded copy in
# local/addons overrides a bundled one in system/addons. Mirrors addons.sh's
# dual-root resolution, so registry-installed addons can get a launchd job too.
STATE_ROOT="${ADDONS_STATE:-${VAULT}/local/addons}"
ADDON_DIR=""
for _root in "$STATE_ROOT" "${VAULT}/system/addons"; do
    if [[ -f "${_root}/${ID}/manifest.md" ]]; then ADDON_DIR="${_root}/${ID}"; break; fi
done
[[ -n "$ADDON_DIR" ]] || { echo "setup-addon-launchd: no manifest for '$ID' in local/ or system/addons" >&2; exit 1; }
MANIFEST="${ADDON_DIR}/manifest.md"
BIN="${ADDON_DIR}/bin/${ID}"
LABEL="local.agentbrain.${ID}"
PLIST_PATH="${LAUNCH_AGENTS}/${LABEL}.plist"
UID_NUMERIC="$(id -u)"
TARGET_DOMAIN="gui/${UID_NUMERIC}"

# ─────────────────────────────────────────────────────────────────
# Subcommands that don't need parsing
# ─────────────────────────────────────────────────────────────────
case "$CMD" in
    uninstall)
        if launchctl print "${TARGET_DOMAIN}/${LABEL}" >/dev/null 2>&1; then
            launchctl bootout "${TARGET_DOMAIN}/${LABEL}" 2>/dev/null || true
            echo "✓ unloaded ${LABEL}"
        fi
        [[ -f "$PLIST_PATH" ]] && { rm "$PLIST_PATH"; echo "✓ removed ${PLIST_PATH}"; }
        exit 0
        ;;
    kickstart)
        if ! launchctl print "${TARGET_DOMAIN}/${LABEL}" >/dev/null 2>&1; then
            echo "setup-addon-launchd: ${LABEL} not loaded — run 'install' first" >&2
            exit 1
        fi
        launchctl kickstart -k "${TARGET_DOMAIN}/${LABEL}"
        echo "✓ kickstarted ${LABEL}"
        exit 0
        ;;
    status)
        if launchctl print "${TARGET_DOMAIN}/${LABEL}" >/dev/null 2>&1; then
            launchctl print "${TARGET_DOMAIN}/${LABEL}" | grep -E "state|last exit|path"
        else
            echo "${LABEL} not loaded"
        fi
        exit 0
        ;;
    install) ;; # fall through
    *) echo "unknown subcommand: $CMD" >&2; exit 2 ;;
esac

# ─────────────────────────────────────────────────────────────────
# install — parse manifest, render template, bootstrap
# ─────────────────────────────────────────────────────────────────
[[ -f "$TEMPLATE" ]] || { echo "setup-addon-launchd: no template at $TEMPLATE" >&2; exit 1; }

# Parse schedule block — emit JSON via python3 (yaml-ish minimal parser).
SCHED_JSON=$(python3 - "$MANIFEST" <<'PY'
import sys, re, json

content = open(sys.argv[1]).read()
m = re.match(r'---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
if not m:
    sys.exit(0)

fm = m.group(1)
result = {}
in_sched = False
in_args = False
args = []

for raw in fm.split('\n'):
    if raw.startswith('schedule:'):
        in_sched = True
        continue
    if in_sched:
        # End of block when a new top-level key starts (non-indented, non-empty).
        if raw and not raw[0].isspace():
            in_sched = False
            in_args = False
            continue
        s = raw.strip()
        if not s:
            continue
        if s.startswith('args:'):
            in_args = True
            continue
        if in_args and s.startswith('- '):
            v = s[2:].strip().strip('"').strip("'")
            args.append(v)
            continue
        if in_args and not s.startswith('- '):
            in_args = False
        if ':' in s and not in_args:
            k, v = s.split(':', 1)
            result[k.strip()] = v.strip().strip('"').strip("'")

if args:
    result['args'] = args

print(json.dumps(result))
PY
)

if [[ -z "$SCHED_JSON" || "$SCHED_JSON" == "{}" ]]; then
    echo "setup-addon-launchd: addon '$ID' has no 'schedule:' block in manifest" >&2
    exit 1
fi

command -v jq >/dev/null || { echo "setup-addon-launchd: jq required" >&2; exit 1; }
CRON=$(echo "$SCHED_JSON" | jq -r '.cron // empty')
ENTRYPOINT=$(echo "$SCHED_JSON" | jq -r '.entrypoint // empty')

# Resolve binary: default convention bin/<id>, override via schedule.entrypoint.
if [[ -n "$ENTRYPOINT" ]]; then
    BIN="${ADDON_DIR}/${ENTRYPOINT}"
fi
[[ -f "$BIN" ]] || { echo "setup-addon-launchd: no binary at $BIN" >&2; exit 1; }
[[ -x "$BIN" ]] || echo "setup-addon-launchd: WARN $BIN exists but is not executable (chmod +x) — launchd will fail to run it" >&2

if [[ -z "$CRON" ]]; then
    echo "setup-addon-launchd: schedule.cron required in manifest" >&2
    exit 1
fi

# Validate + parse cron (minute hour day month weekday).
read -r MIN HOUR DOM MON DOW <<< "$CRON" || true
if [[ -z "$MIN" || -z "$HOUR" || -z "$DOM" || -z "$MON" || -z "$DOW" ]]; then
    echo "setup-addon-launchd: cron must be 5 fields (got: '$CRON')" >&2
    exit 1
fi

# Detect `*/N` patterns in any cron field. launchd's StartCalendarInterval can
# only express absolute matches (Hour=18) — for "every N minutes/hours" we drop
# to StartInterval (seconds). Pick the first */N field that matches and convert.
INTERVAL_SECONDS=""
for pair in "minute:$MIN:60" "hour:$HOUR:3600" "day:$DOM:86400"; do
    # `_name` kept for readability of the loop pairs; only val and mult are used downstream.
    # shellcheck disable=SC2034
    _name="${pair%%:*}" rest="${pair#*:}" val="${rest%%:*}" mult="${rest##*:}"
    if [[ "$val" =~ ^\*/([0-9]+)$ ]]; then
        n="${BASH_REMATCH[1]}"
        INTERVAL_SECONDS=$((n * mult))
        break
    fi
done

# `*/N` collapses to launchd StartInterval (every N seconds), which CANNOT honor
# any calendar constraint. Warn loudly for every other field the cron restricted,
# so a schedule like `*/5 * * * 1-5` (meant: weekdays only) doesn't silently run
# all week. Ranges/lists in the non-interval path are rejected loudly downstream.
if [[ -n "$INTERVAL_SECONDS" ]]; then
    for pair in "minute:$MIN" "hour:$HOUR" "day-of-month:$DOM" "month:$MON" "weekday:$DOW"; do
        fname="${pair%%:*}" fval="${pair#*:}"
        if [[ "$fval" != "*" && ! "$fval" =~ ^\*/[0-9]+$ ]]; then
            echo "setup-addon-launchd: WARN cron field ${fname}='${fval}' is IGNORED — '*/N' uses StartInterval (every ${INTERVAL_SECONDS}s), which cannot honor calendar constraints." >&2
        fi
    done
fi

# Build CalendarInterval XML — skip wildcards ('*'). Numeric only for now.
build_calendar_xml() {
    local out=""
    for pair in "Minute:$MIN" "Hour:$HOUR" "Day:$DOM" "Month:$MON" "Weekday:$DOW"; do
        local key="${pair%%:*}" val="${pair#*:}"
        if [[ "$val" == "*" ]]; then continue; fi
        if [[ ! "$val" =~ ^[0-9]+$ ]]; then
            echo "setup-addon-launchd: cron field '$key' must be numeric or '*' (got: '$val')" >&2
            exit 1
        fi
        out+="        <key>${key}</key><integer>${val}</integer>"$'\n'
    done
    printf "%s" "$out"
}

# Build ARGS_XML from JSON args.
build_args_xml() {
    local args_xml=""
    local args_count
    args_count=$(echo "$SCHED_JSON" | jq -r '.args | length // 0')
    for ((i=0; i<args_count; i++)); do
        local a
        a=$(echo "$SCHED_JSON" | jq -r ".args[$i]")
        # XML-escape minimal (args from manifest, user-controlled, low risk).
        a="${a//&/&amp;}"; a="${a//</&lt;}"; a="${a//>/&gt;}"
        args_xml+="        <string>${a}</string>"$'\n'
    done
    printf "%s" "$args_xml"
}

ARGS_XML=$(build_args_xml)
LOG_OUT="${LOGS_DIR}/${ID}.out.log"
LOG_ERR="${LOGS_DIR}/${ID}.err.log"

# Build the schedule XML — StartInterval (seconds) when any */N field was
# detected, otherwise StartCalendarInterval (dict of absolute matches).
if [[ -n "$INTERVAL_SECONDS" ]]; then
    SCHEDULE_XML="    <key>StartInterval</key>
    <integer>${INTERVAL_SECONDS}</integer>"
else
    CALENDAR_XML=$(build_calendar_xml)
    SCHEDULE_XML="    <key>StartCalendarInterval</key>
    <dict>
${CALENDAR_XML%$'\n'}
    </dict>"
fi

mkdir -p "$LAUNCH_AGENTS" "$LOGS_DIR"

# Build PATH for the launchd job: bun (if present) + brew prefix + system paths.
_agent_path_parts=("/usr/local/bin" "/usr/bin" "/bin")
if command -v brew >/dev/null 2>&1; then
    _brew_prefix="$(brew --prefix)"
    _agent_path_parts=("${_brew_prefix}/bin" "${_agent_path_parts[@]}")
elif [[ "$(uname -m)" == "arm64" ]]; then
    _agent_path_parts=("/opt/homebrew/bin" "${_agent_path_parts[@]}")
fi
[[ -d "${HOME}/.bun/bin" ]] && _agent_path_parts=("${HOME}/.bun/bin" "${_agent_path_parts[@]}")
AGENT_PATH="$(IFS=:; echo "${_agent_path_parts[*]}")"

# Render template — write via python to handle multiline placeholders cleanly.
python3 - "$TEMPLATE" "$PLIST_PATH" \
    "$LABEL" "$BIN" "$ARGS_XML" "$SCHEDULE_XML" \
    "$LOG_OUT" "$LOG_ERR" "$HOME" "$AGENT_PATH" <<'PY'
import sys
src, dst, label, bin_path, args_xml, sched_xml, log_out, log_err, home, agent_path = sys.argv[1:11]
with open(src) as f:
    t = f.read()
args_xml = args_xml.rstrip('\n')
sched_xml = sched_xml.rstrip('\n')
# XML-escape the command path, mirroring what build_args_xml does for args —
# a path containing & or <> would otherwise render an invalid plist.
bin_path = bin_path.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
out = (t
    .replace('{{LABEL}}', label)
    .replace('{{COMMAND_PATH}}', bin_path)
    .replace('{{ARGS_XML}}', args_xml)
    .replace('{{SCHEDULE_XML}}', sched_xml)
    .replace('{{LOG_OUT}}', log_out)
    .replace('{{LOG_ERR}}', log_err)
    .replace('{{HOME}}', home)
    .replace('{{AGENT_PATH}}', agent_path))
with open(dst, 'w') as f:
    f.write(out)
PY

# Validate.
if ! plutil -lint "$PLIST_PATH" >/dev/null; then
    echo "setup-addon-launchd: rendered plist failed plutil -lint" >&2
    plutil -lint "$PLIST_PATH" >&2
    exit 1
fi

# Idempotent reload.
if launchctl print "${TARGET_DOMAIN}/${LABEL}" >/dev/null 2>&1; then
    launchctl bootout "${TARGET_DOMAIN}/${LABEL}" 2>/dev/null || true
fi
launchctl bootstrap "$TARGET_DOMAIN" "$PLIST_PATH"
echo "✓ loaded ${LABEL} → cron '${CRON}', logs in ${LOG_OUT}"
