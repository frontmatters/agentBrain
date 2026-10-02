#!/usr/bin/env bash
# List opt-in add-on suites for the full doctor. Only tests inside the declaring
# add-on can be executed; an invalid declaration fails static manifest validation.
set -euo pipefail
registry="${ADDONS_CHECK_REGISTRY:-system/addons}"
for manifest in "$registry"/*/manifest.md; do
  [ -f "$manifest" ] || continue
  dir="${manifest%/manifest.md}"
  [ "${dir##*/}" = _template ] && continue
  [ -f "$dir/doctor-tests.txt" ] || continue
  while IFS= read -r test || [ -n "$test" ]; do
    [ -z "$test" ] && continue
    case "$test" in
      tests/test-*.sh)
        case "${test#tests/}" in
          *[!a-zA-Z0-9_.-]*|*..*) echo "invalid doctor test: $dir/$test" >&2; exit 1 ;;
        esac
        [ -f "$dir/$test" ] || { echo "missing doctor test: $dir/$test" >&2; exit 1; } ;;
      *) echo "invalid doctor test: $dir/$test" >&2; exit 1 ;;
    esac
    printf 'bash %s/%s\n' "$dir" "$test"
  done < "$dir/doctor-tests.txt"
done
