#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/factory-doctor.sh" --factory "${FACTORY_PATH:-$PWD}" --strict "$@"
