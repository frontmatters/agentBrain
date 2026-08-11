#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-prompt-cache-hygiene.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { echo "FAIL: $1" >&2; failed=$((failed + 1)); }

cat > "$TMP_DIR/clean.md" <<'EOF'
---
date: 2026-07-21
---
A literal date and the word timestamp are stable.
Inline code is documentation: `$(date) ${NOW} {{timestamp}}`.

```bash
echo "$(date) ${NOW} {{timestamp}}"
```
EOF
if bash "$CHECK" "$TMP_DIR/clean.md" >/dev/null 2>&1; then pass; else fail "static dates and fenced examples should pass"; fi

cat > "$TMP_DIR/multiple.md" <<'EOF'
Generated: $(date)
Request: ${REQUEST_ID}
At: {{timestamp}}
EOF
if output="$(bash "$CHECK" "$TMP_DIR/multiple.md" 2>&1)"; then
	fail "volatile placeholders should fail"
else
	count="$(printf '%s\n' "$output" | grep -c "$TMP_DIR/multiple.md:")"
	if [ "$count" -eq 3 ]; then pass; else fail "expected 3 findings, got $count"; fi
fi

cat > "$TMP_DIR/forms.md" <<'EOF'
$CURRENT_DATE
${NOW}
$TIMESTAMP
${RANDOM}
{{current_date}}
{{request_id}}
EOF
if output="$(bash "$CHECK" "$TMP_DIR/forms.md" 2>&1)"; then
	fail "all forbidden forms should fail"
else
	count="$(printf '%s\n' "$output" | grep -c "$TMP_DIR/forms.md:")"
	if [ "$count" -eq 6 ]; then pass; else fail "expected 6 forbidden-form findings, got $count"; fi
fi

printf 'test-prompt-cache-hygiene: passed=%d failed=%d\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
