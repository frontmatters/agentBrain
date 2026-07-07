#!/usr/bin/env bash
# check-events.sh — Validate every event under local/events/inbox/ and archive/
# against the envelope schema (system/addons/event-bus/SPEC.md §1).
#
# Per SPEC: every event MUST have envelope fields {event_id, type,
# envelope_schema_version, payload_schema_version, from{agent,host,instance_id},
# to{agents,hosts,broadcast}, timestamp, correlation_id, payload}. type MUST
# match <context>.<entity>.<action> regex. event_id MUST be a UUID.
#
# Skips local/events/*.tmp (partial writes, expected during atomic-write).
# No-op if local/events/inbox/ does not exist (bus not yet used).
#
# Performance: all events are validated in a SINGLE batched jq pass (one process
# for the whole inbox+archive, keyed on input_filename) instead of ~13 jq spawns
# per event. On a real vault this is the difference between sub-second and many
# minutes — see scripts/check-events.sh history / event-bus SPEC-storage §8.
# A malformed-JSON file aborts a jq batch mid-stream, so on any batch failure we
# fall back to a robust per-file loop that pinpoints the offending event.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

INBOX="local/events/inbox"
ARCHIVE="local/events/archive"

if ! command -v jq >/dev/null 2>&1; then
    echo "check-events: jq not found (required); install via brew install jq" >&2
    exit 1
fi

# ── Single jq program validating one event value, keyed on input_filename ──
# Emits, per invalid file: an "INVALID <file>:" header followed by "  - <reason>"
# lines. Valid events emit nothing. Mirrors the SPEC §1 envelope rules; the
# `truthy` helper reproduces the `jq -e EXPR` (non-null, non-false) guard the
# previous per-field implementation relied on.
read -r -d '' EVENT_FILTER <<'JQ' || true
def truthy: . != null and . != false;
input_filename as $fn
| . as $e
| (
  if ($e | type) != "object" then ["event is not a JSON object"]
  else
    ( ["event_id","type","envelope_schema_version","payload_schema_version","from","to","timestamp","correlation_id","payload"]
      | map(select($e[.] == null) | "missing/null required field: \(.)") )
    + ( if (($e.type | type) == "string") and ($e.type != "")
           and (($e.type | test("^[a-z][a-z0-9-]*\\.[a-z][a-z0-9-]*\\.[a-z][a-z0-9-]*$")) | not)
         then ["invalid type format (expected <context>.<entity>.<action> lowercase kebab): \($e.type)"] else [] end )
    + ( if (($e.event_id | type) == "string") and ($e.event_id != "")
           and (($e.event_id | test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")) | not)
         then ["invalid event_id format (expected UUID): \($e.event_id)"] else [] end )
    + ( ["agent","host","instance_id"]
        | map( . as $k
               | select( (($e.from | type) != "object") or ($e.from[$k] == null) or ($e.from[$k] == "") )
               | "missing/empty from.\($k)" ) )
    + ( ["agents","hosts","broadcast"]
        | map( . as $k
               | select( (($e.to | type) != "object") or (($e.to | has($k)) | not) )
               | "missing to.\($k)" ) )
    + ( if (($e.to | type) == "object") and ($e.to | has("agents")) and ($e.to.agents | truthy)
           and (($e.to.agents | type) != "array") then ["to.agents must be array"] else [] end )
    + ( if (($e.to | type) == "object") and ($e.to | has("hosts")) and ($e.to.hosts | truthy)
           and (($e.to.hosts | type) != "array") then ["to.hosts must be array"] else [] end )
    + ( if (($e.to | type) == "object") and ($e.to | has("broadcast")) and ($e.to.broadcast | truthy)
           and (($e.to.broadcast | type) != "boolean") then ["to.broadcast must be boolean"] else [] end )
    + ( if (($e.timestamp | type) == "string") and ($e.timestamp != "")
           and (($e.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}")) | not)
         then ["timestamp not ISO-8601: \($e.timestamp)"] else [] end )
    + ( if (($e.correlation_id | type) == "string") and ($e.correlation_id != "")
           and (($e.correlation_id | test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")) | not)
         then ["invalid correlation_id format: \($e.correlation_id)"] else [] end )
    + ( if ($e.envelope_schema_version | truthy) and (($e.envelope_schema_version | type) != "number")
         then ["envelope_schema_version must be a number"] else [] end )
    + ( if ($e.payload_schema_version | truthy) and (($e.payload_schema_version | type) != "number")
         then ["payload_schema_version must be a number"] else [] end )
  end
  )
| if length == 0 then empty
  else ("INVALID \($fn):"), (.[] | "  - \(.)")
  end
JQ

# ── Collect events from inbox + archive (skip .tmp partial writes) ──
files=()
for dir in "$INBOX" "$ARCHIVE"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$dir" -maxdepth 1 -name "*.json" ! -name "*.tmp" -type f -print0 2>/dev/null)
done

total="${#files[@]}"
if [ "$total" -eq 0 ]; then
    echo "check-events: no events to validate (bus not yet used)"
    exit 0
fi

# ── Fast path: one batched jq over the whole set (keyed on input_filename) ──
# xargs splits the arg list to stay under ARG_MAX, spawning at most a handful of
# jq processes. A parse error makes that jq abort its chunk → non-zero rc → fall
# back to the robust per-file loop below so nothing is silently left unvalidated.
report=""
if report="$(printf '%s\0' "${files[@]}" | xargs -0 jq -r "$EVENT_FILTER" 2>/dev/null)"; then
    :
else
    # ── Fallback: per-file (handles malformed JSON with a precise message) ──
    report=""
    for f in "${files[@]}"; do
        if ! jq -e . "$f" >/dev/null 2>&1; then
            report+="INVALID $f: not valid JSON"$'\n'
            continue
        fi
        file_errs="$(jq -r "$EVENT_FILTER" "$f" 2>/dev/null || true)"
        [ -n "$file_errs" ] && report+="$file_errs"$'\n'
    done
fi

# Invalid-file count = number of "INVALID " header lines.
invalid=0
if [ -n "$report" ]; then
    invalid="$(printf '%s\n' "$report" | grep -c '^INVALID ' || true)"
    printf '%s\n' "$report" | sed '/^$/d' >&2
fi

if [ "$invalid" -gt 0 ]; then
    echo "check-events: $invalid invalid event(s) of $total total" >&2
    exit 1
fi

echo "check-events: $total event(s) valid"
