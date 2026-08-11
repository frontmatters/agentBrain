#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# session-digest.sh — deterministic digest of agent sessions (Claude Code + Pi).
# One row per session: project, date, user turns, models, tool counts, invoked
# skills, error count, sidechain count, first prompt (100 chars max).
# Input layer for /brain-insights session audits and /brain-retro skills audits.
# No LLM involved; no transcript content beyond the first prompt line (privacy).
#
# Usage:
#   bash scripts/session-digest.sh [--days N] [--min-turns N] [--format md|tsv] [--out FILE]
#
# Env overrides (used by tests): CLAUDE_PROJECTS_DIR, PI_SESSIONS_DIR.

set -euo pipefail

DAYS=30
MIN_TURNS=2
FORMAT=md
OUT=""

while [ $# -gt 0 ]; do
	case "$1" in
		--days) DAYS="$2"; shift 2 ;;
		--days=*) DAYS="${1#--days=}"; shift ;;
		--min-turns) MIN_TURNS="$2"; shift 2 ;;
		--min-turns=*) MIN_TURNS="${1#--min-turns=}"; shift ;;
		--format) FORMAT="$2"; shift 2 ;;
		--format=*) FORMAT="${1#--format=}"; shift ;;
		--out) OUT="$2"; shift 2 ;;
		--out=*) OUT="${1#--out=}"; shift ;;
		-h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "session-digest: unknown arg: $1" >&2; exit 2 ;;
	esac
done

command -v jq >/dev/null 2>&1 || { echo "session-digest: jq is required" >&2; exit 1; }

CLAUDE_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
PI_DIR="${PI_SESSIONS_DIR:-$HOME/.pi/agent/sessions}"

ROWS="$(mktemp "${TMPDIR:-/tmp}/session-digest-XXXXXX")"
trap 'rm -f "$ROWS"' EXIT
SKIPPED=0

# Shared row tail: filter on min turns, sort tools desc, emit TSV.
JQ_EMIT='
| select(.u >= ($mt|tonumber))
| [$src, $proj, $date, $file,
   (.u|tostring),
   (.models|keys|sort|join(",")),
   ([.tools|to_entries|sort_by(-.value)[]|"\(.key):\(.value)"]|join(" ")),
   ([.skills|to_entries|sort_by(-.value)[]|"\(.key):\(.value)"]|join(",")),
   (.err|tostring), (.side|tostring),
   (.first | gsub("\\|"; "/"))]
| @tsv
'

JQ_CLAUDE='
reduce inputs as $l (
	{u:0, err:0, side:0, models:{}, tools:{}, skills:{}, first:""};
	if ($l.isSidechain == true) then .side += 1
	else
		(if $l.type=="user" and ($l.isMeta != true) and (($l.message.content|type)=="string")
			then .u += 1
				| (if .first=="" and (($l.message.content|startswith("<"))|not)
					then .first = ($l.message.content | split("\n")[0] | .[0:100])
					else . end)
			else . end)
		| (if $l.type=="user" and (($l.message.content|type)=="array")
			then .err += ([$l.message.content[] | select(type=="object" and .type=="tool_result" and .is_error==true)] | length)
			else . end)
		| (if $l.type=="assistant"
			then (if (($l.message.model? // "") != "") then .models[$l.message.model] = true else . end)
				| reduce ($l.message.content[]? | select(type=="object" and .type=="tool_use")) as $t (.;
					.tools[$t.name] = ((.tools[$t.name] // 0) + 1)
					| (if $t.name=="Skill" and (($t.input.skill? // "") != "")
						then .skills[$t.input.skill] = ((.skills[$t.input.skill] // 0) + 1)
						else . end))
			else . end)
	end
)
'

JQ_PI='
reduce inputs as $l (
	{u:0, err:0, side:0, models:{}, tools:{}, skills:{}, first:""};
	(if $l.type=="message" and $l.message.role=="user"
		then .u += 1
			| (if .first==""
				then .first = (([$l.message.content[]? | select(.type=="text") | .text] | join(" ")) | split("\n")[0] | .[0:100])
				else . end)
		else . end)
	| (if $l.type=="message" and $l.message.role=="assistant" and (($l.message.model? // "") != "")
		then .models[$l.message.model] = true else . end)
	| (if $l.type=="message" and $l.message.role=="assistant"
		then reduce ($l.message.content[]? | select(.type=="toolCall")) as $t (.;
			.tools[$t.name] = ((.tools[$t.name] // 0) + 1))
		else . end)
	| (if $l.type=="message" and $l.message.role=="toolResult" and ($l.message.isError == true)
		then .err += 1 else . end)
)
'

digest_file() {
	# $1=source label, $2=project, $3=file, $4=jq program
	local src="$1" proj="$2" f="$3" prog="$4" fdate
	fdate="$(date -r "$f" +%Y-%m-%d 2>/dev/null || echo unknown)"
	if ! jq -cR 'fromjson? // empty' "$f" 2>/dev/null \
		| jq -rn --arg src "$src" --arg proj "$proj" --arg date "$fdate" \
			--arg file "$(basename "$f")" --arg mt "$MIN_TURNS" \
			"${prog}${JQ_EMIT}" >> "$ROWS" 2>/dev/null; then
		SKIPPED=$((SKIPPED+1))
	fi
}

if [ -d "$CLAUDE_DIR" ]; then
	while IFS= read -r f; do
		digest_file "claude" "$(basename "$(dirname "$f")")" "$f" "$JQ_CLAUDE"
	done < <(find "$CLAUDE_DIR" -name '*.jsonl' -type f -mtime -"$DAYS" 2>/dev/null)
fi

if [ -d "$PI_DIR" ]; then
	while IFS= read -r f; do
		digest_file "pi" "$(basename "$(dirname "$f")")" "$f" "$JQ_PI"
	done < <(find "$PI_DIR" -name '*.jsonl' -type f -mtime -"$DAYS" 2>/dev/null)
fi

emit() {
	if [ "$FORMAT" = "tsv" ]; then
		sort -t$'\t' -k3,3 "$ROWS"
		return
	fi
	echo "# Session digest — last ${DAYS} days ($(date +%Y-%m-%d))"
	echo
	echo "Sessions: $(wc -l < "$ROWS" | tr -d ' ') (min ${MIN_TURNS} turns) · skipped files: ${SKIPPED}"
	echo
	echo "| Date | Src | Project | Turns | Models | Skills | Err | Side | Top tools | First prompt |"
	echo "|---|---|---|---|---|---|---|---|---|---|"
	sort -t$'\t' -k3,3 "$ROWS" | awk -F'\t' '{
		tools=$7; n=split(tools, tt, " "); top="";
		for (i=1; i<=n && i<=5; i++) top = top (i>1 ? " " : "") tt[i];
		printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n",
			$3, $1, $2, $5, $6, $8, $9, $10, top, $11
	}'
	echo
	echo "## Skill usage (aggregated)"
	echo
	awk -F'\t' '$8 != "" {
		n=split($8, ss, ",");
		for (i=1; i<=n; i++) {
			# split on the LAST colon: skill names may be namespaced (plugin:skill)
			if (match(ss[i], /:[0-9]+$/)) {
				agg[substr(ss[i], 1, RSTART-1)] += substr(ss[i], RSTART+1);
			}
		}
	} END { for (k in agg) printf "- %s: %d\n", k, agg[k] }' "$ROWS" | sort -k3 -rn
}

if [ -n "$OUT" ]; then
	mkdir -p "$(dirname "$OUT")"
	emit > "$OUT"
	echo "$OUT"
else
	emit
fi
