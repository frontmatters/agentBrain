#!/usr/bin/env bash

###############################################################################
# Lightpanda Installer Wrapper for Pi Agent
#
# Entry point for /skill:lightpanda-setup install
# Delegates to scripts/lightpanda-install.sh in the agentBrain repo.
###############################################################################

set -euo pipefail

# Resolve agentBrain dir: env var > sibling of this script (scripts/../)
AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
INSTALL_SCRIPT="${AGENTBRAIN_DIR}/scripts/lightpanda-install.sh"

if [ ! -f "$INSTALL_SCRIPT" ]; then
	echo "Installer script not found at $INSTALL_SCRIPT" >&2
	exit 1
fi

bash "$INSTALL_SCRIPT"
