#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# install.sh — (a) verifies the runtime dependencies are present, (b) makes the
# bin/ scripts executable and (c) symlinks each of them into
# $EVENT_BUS_BIN_DIR (default ~/.local/bin) so they are callable by name.
# Idempotent + uninstall-symmetric: --uninstall removes exactly those links.
# Errors are loud: a missing dependency prints how to get it and exits non-zero.
set -euo pipefail
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--uninstall" ]; then
	# The only thing installed outside this dir is the set of links in $DEST;
	# remove those. chmod is harmless to leave. Removing runtime state is a
	# separate step, gated behind uninstall.sh --purge.
	DEST="${EVENT_BUS_BIN_DIR:-$HOME/.local/bin}"
	removed=0
	for f in "$ADDON_DIR"/bin/*; do
		[ -f "$f" ] || continue
		link="$DEST/$(basename "$f")"
		# Only remove a link that points back here, never a same-named binary
		# somebody else installed.
		[ -L "$link" ] && [ "$(realpath "$link" 2>/dev/null)" = "$(realpath "$f")" ] \
			&& { rm -f "$link"; removed=$((removed + 1)); }
	done
	echo "event-bus: removed $removed link(s) from $DEST. Scripts stay in $ADDON_DIR/bin."
	echo "  Runtime state lives in vault/events/ — remove it with: bash $ADDON_DIR/uninstall.sh --purge"
	exit 0
fi

# Dependency checks — loud and fatal so a broken host is obvious at install time.
missing=0
# A function, not an associative array: macOS ships bash 3.2 and every fresh
# Mac installs this essential addon on it.
hint() {
	case "$1" in
		jq) echo "brew install jq        # or your distro's package manager" ;;
		python3) echo "brew install python  # or your distro's package manager" ;;
		openssl) echo "brew install openssl  # usually preinstalled" ;;
	esac
}
for dep in jq python3 openssl; do
	if ! command -v "$dep" >/dev/null 2>&1; then
		echo "event-bus: missing dependency '$dep' — install it:" >&2
		echo "    $(hint "$dep")" >&2
		missing=1
	fi
done
[ "$missing" -eq 0 ] || { echo "event-bus: install aborted (missing dependencies above)." >&2; exit 1; }

# Make the entrypoints executable (idempotent).
for f in "$ADDON_DIR"/bin/*; do
	[ -f "$f" ] && chmod +x "$f"
done

# Link the entrypoints onto PATH, same pattern as the pubcheck addon, so
# agents in other sessions and directories can run them by name.
DEST="${EVENT_BUS_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$DEST"
linked=0
for f in "$ADDON_DIR"/bin/*; do
	[ -f "$f" ] || continue
	ln -sf "$f" "$DEST/$(basename "$f")"
	linked=$((linked + 1))
done
echo "event-bus: ready. $linked command(s) linked at $DEST/"
command -v brain-chat >/dev/null 2>&1 \
	|| echo "NOTE: $DEST is not on your PATH, so the commands are not callable by name yet."
echo "    brain-chat            what every session is doing"
echo "    brain-claim --help    record what you are about to work on"
echo "    brain-emit --help     publish an event"
