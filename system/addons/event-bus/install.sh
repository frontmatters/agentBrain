#!/usr/bin/env bash
# install.sh — event-bus has no real install step: the bin/ scripts run directly
# from the addon path. This installer only (a) verifies the runtime dependencies
# are present and (b) makes the bin/ scripts executable. Idempotent + uninstall-
# symmetric. Errors are loud: a missing dependency prints how to get it and exits
# non-zero.
set -euo pipefail
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--uninstall" ]; then
	# Nothing was installed outside this dir; chmod is harmless to leave. The only
	# inverse worth offering is removing runtime state, gated behind --purge.
	echo "event-bus: nothing to uninstall (scripts run in place from $ADDON_DIR/bin)."
	echo "  Runtime state lives in local/events/ — remove it with: bash $ADDON_DIR/uninstall.sh --purge"
	exit 0
fi

# Dependency checks — loud and fatal so a broken host is obvious at install time.
missing=0
declare -A HINT=(
	[jq]="brew install jq        # or your distro's package manager"
	[python3]="brew install python  # or your distro's package manager"
	[openssl]="brew install openssl  # usually preinstalled"
)
for dep in jq python3 openssl; do
	if ! command -v "$dep" >/dev/null 2>&1; then
		echo "event-bus: missing dependency '$dep' — install it:" >&2
		echo "    ${HINT[$dep]}" >&2
		missing=1
	fi
done
[ "$missing" -eq 0 ] || { echo "event-bus: install aborted (missing dependencies above)." >&2; exit 1; }

# Make the entrypoints executable (idempotent).
for f in "$ADDON_DIR"/bin/*; do
	[ -f "$f" ] && chmod +x "$f"
done

echo "event-bus: ready. No install needed beyond this — run the bins directly:"
echo "    bash $ADDON_DIR/bin/brain-emit --help"
echo "    bash $ADDON_DIR/bin/brain-poll --help"
echo "    bash $ADDON_DIR/bin/brain-ping --help"
