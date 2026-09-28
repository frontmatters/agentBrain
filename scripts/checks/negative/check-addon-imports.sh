#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-addon-imports.sh: an import that climbs out of the
# addon is rejected; one inside the addon or via @agentbrain/lib passes.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-addon-imports.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks" "$TMP/system/addons/a/src" "$TMP/system/addons/b/src" "$TMP/system/lib"
cp "$CHECK" "$TMP/scripts/checks/"
cd "$TMP" || exit 1
printf 'export const x = 1;\n' > system/addons/b/src/index.ts
printf 'import { x } from "../../b/src/index";\n' > system/addons/a/src/main.ts
if bash scripts/checks/check-addon-imports.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-addon-imports accepted an import into another addon" >&2; exit 1
fi
printf 'import { x } from "../../../lib/x";\n' > system/addons/a/src/main.ts
if bash scripts/checks/check-addon-imports.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-addon-imports accepted ../../../lib" >&2; exit 1
fi
printf 'import { x } from "./util";\nimport { y } from "@agentbrain/lib/model-call";\n' > system/addons/a/src/main.ts
if ! bash scripts/checks/check-addon-imports.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-addon-imports rejected an import inside the addon or via @agentbrain/lib" >&2; exit 1
fi
echo "negative case holds: check-addon-imports rejects imports that leave the addon"
