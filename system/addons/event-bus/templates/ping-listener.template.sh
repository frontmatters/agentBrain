#!/usr/bin/env bash
# ping-listener.template.sh — minimal pong responder for any agent.
#
# Copy this template to your agent's runtime location, customize AGENT_NAME,
# and run as a long-lived loop (or as a periodic cron).
#
# Behavior: polls for system.bus.ping events addressed to you, builds a
# spec-compliant system.bus.pong, emits it back to the pinger.

set -euo pipefail

# === Configure these ===
AGENT_NAME="${BRAIN_AGENT:-pi}"     # who am I on the bus
POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-2}"
LOOKBACK="${LOOKBACK:-5m}"
# =======================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
export AGENTBRAIN_DIR

EMIT="$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-emit"
POLL="$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-poll"
HOST_NAME="$(hostname -s)"
INSTANCE_ID="${BRAIN_INSTANCE_ID:-pid-$$}"

echo "ping-listener: starting as agent=$AGENT_NAME host=$HOST_NAME (poll every ${POLL_INTERVAL_SEC}s)" >&2

trap 'echo "ping-listener: stopped" >&2; exit 0' INT TERM

while :; do
    # Pull pings addressed to us, with --commit so we never pong the same one twice
    pings="$("$POLL" --agent="$AGENT_NAME" --type='system.bus.ping' --raw --commit --lookback="$LOOKBACK" 2>/dev/null || true)"

    if [ -n "$pings" ]; then
        while IFS= read -r ping; do
            [ -z "$ping" ] && continue

            ping_id="$(echo "$ping" | jq -r '.event_id')"
            ping_echo="$(echo "$ping" | jq -r '.payload.echo // empty')"
            ping_sent_at="$(echo "$ping" | jq -r '.payload.sent_at // empty')"
            ping_from_agent="$(echo "$ping" | jq -r '.from.agent')"

            received_at="$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ'))")"
            # responded_at: compute once right before emit (no double-set).
            responded_at="$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ'))")"

            pong_payload="$(jq -nc \
                --arg e "$ping_echo" \
                --arg sa "$ping_sent_at" \
                --arg ra "$received_at" \
                --arg respat "$responded_at" \
                --arg ag "$AGENT_NAME" \
                --arg ho "$HOST_NAME" \
                --arg iid "$INSTANCE_ID" \
                '{
                    echo: $e,
                    sent_at: $sa,
                    received_at: $ra,
                    responded_at: $respat,
                    pong_by: { agent: $ag, host: $ho, instance_id: $iid }
                }')"

            "$EMIT" \
                --type=system.bus.pong \
                --from="$AGENT_NAME" \
                --to="$ping_from_agent" \
                --in-reply-to="$ping_id" \
                --correlation-id="$ping_id" \
                --payload="$pong_payload" >/dev/null

            echo "ping-listener: pong'd $ping_id to $ping_from_agent" >&2
        done <<< "$pings"
    fi

    sleep "$POLL_INTERVAL_SEC"
done
