#!/usr/bin/env bash
# test-validate.sh — tests for the /architect dossier form-checker.
# Builds fixture dossiers in a tmpdir and asserts validate.sh pass/fail.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
validate="$here/validate.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { echo "ok - $1"; pass=$((pass+1)); }
bad() { echo "NOT OK - $1"; fail=$((fail+1)); }

# --- fixture repo with real files for evidence checks ---
mkdir -p "$tmp/repo/apps/daemon/src"
touch "$tmp/repo/apps/daemon/src/server.ts" "$tmp/repo/package.json"

# --- valid dossier ---
# NOTE: unquoted EOF — $tmp expands; escape backticks and $ in fixture content
cat > "$tmp/valid.md" <<EOF
---
title: Architecture — Fixture
repo: $tmp/repo
---

## Recon

| Concern | File / location | How found |
|---|---|---|
| API server | \`apps/daemon/src/server.ts\` | grep |

evidence: \`apps/daemon/src/server.ts\`

## Building Blocks

\`\`\`mermaid
flowchart LR
  A[Web] --> B[Daemon]
\`\`\`

| Component | Where | Role | Trust level |
|---|---|---|---|
| Daemon | \`apps/daemon/src/server.ts\` | API owner | privileged |

evidence: \`apps/daemon/src/server.ts\`

## Constraints

\`\`\`mermaid
flowchart TD
  B[Daemon] --> X[External API]
\`\`\`

### Egress
One outbound call to the model provider.
evidence: \`package.json\`

### Data & Storage
State lives in a local data dir.
⚠ Open: encryption at rest unconfirmed.

### Secrets
Keys in a config file today.
⚠ Open: vault integration missing.

### Identity & Access
No auth layer exists yet.
⚠ Open: SSO provider unknown.

### Compliance
GDPR applies to any personal data in prompts.
⚠ Open: data-classification ceiling unknown.

### Operations
No structured logging yet.
⚠ Open: SIEM target unknown.

## Decisions

### Decision: where should auth live?

**Context:** the tool has no login; upstream updates must stay mergeable.

**Option 1:** modify the core — fast, but causes fork rot.

**Option 2:** host-shell in front — slower, upgrade-safe.

**Recommendation:** Option 2, host-shell.

abort-condition: chosen IdP protocol unsupported by the shell.

## Open Questions

| # | ⚠ Open | Who/what can answer |
|---|---|---|
| 1 | IdP protocol | customer IT |
EOF

# --- invalid fixtures, one defect each ---

# missing a required section (Decisions removed; end-exclusive so Open Questions survives)
sed '/^## Decisions/,/^## Open Questions/{/^## Open Questions/!d;}' "$tmp/valid.md" > "$tmp/no-decisions.md"

# missing a required section (isolated: nothing else depends on Open Questions)
sed '/^## Open Questions/,$d' "$tmp/valid.md" > "$tmp/no-section.md"

# placeholder text
sed 's/One outbound call to the model provider./TBD/' "$tmp/valid.md" > "$tmp/has-tbd.md"

# only one mermaid block
awk 'BEGIN{skip=0} /^```mermaid/ && ++c==2 {skip=1} skip && /^```$/ {skip=0; next} !skip' "$tmp/valid.md" > "$tmp/one-mermaid.md"

# evidence path that does not exist
sed 's|evidence: `package.json`|evidence: `does/not/exist.ts`|' "$tmp/valid.md" > "$tmp/bad-evidence.md"

# decision with only one option
sed '/\*\*Option 2:\*\*/d' "$tmp/valid.md" > "$tmp/one-option.md"

# decision without abort-condition
sed '/^abort-condition:/d' "$tmp/valid.md" > "$tmp/no-abort.md"

# missing constraint lens (Compliance removed, Operations kept)
sed '/^### Compliance/,/^### Operations/{/^### Operations/!d;}' "$tmp/valid.md" > "$tmp/missing-lens.md"

# fewer than 3 evidence: markers (Egress evidence line removed)
sed '/^evidence: `package.json`/d' "$tmp/valid.md" > "$tmp/few-evidence.md"

# decision without a Recommendation line
sed '/^\*\*Recommendation:\*\*/d' "$tmp/valid.md" > "$tmp/no-recommendation.md"

# dossier without any ⚠ Open marker
sed 's/⚠ Open//g' "$tmp/valid.md" > "$tmp/no-open-marker.md"

# --- fixtures that must PASS (LLM-typical valid variants) ---

# code fence containing TODO must not trip the placeholder check
{ cat "$tmp/valid.md"; printf '\n```ts\n// TODO(auth): tighten egress allowlist\n```\n'; } > "$tmp/fence-todo.md"

# YAML-quoted repo: value must still resolve
awk -v r="$tmp/repo" '/^repo: /{print "repo: \"" r "\""; next} {print}' "$tmp/valid.md" > "$tmp/quoted-repo.md"

# indented mermaid fence (CommonMark-legal) must still count
awk 'BEGIN{c=0} /^```mermaid$/{c++; if(c==2){print "  " $0; f=1; next}} f && /^```$/{print "  " $0; f=0; next} {print}' "$tmp/valid.md" > "$tmp/indented-mermaid.md"

# --- more fixtures that must FAIL ---

# prose between evidence: and the backticked path must not skip the check
sed 's|evidence: `package.json`|evidence: see `does/not/exist.ts` for the handler|' "$tmp/valid.md" > "$tmp/prose-evidence.md"

# a section name inside a code fence must not satisfy the section check
{ sed '/^## Open Questions/,$d' "$tmp/valid.md"; printf '```md\n## Open Questions\n| # | x | y |\n| 1 | a | b |\n```\n'; } > "$tmp/fenced-section.md"

# --- assertions ---
[ -x "$validate" ] || { echo "NOT OK - validate.sh missing or not executable"; exit 1; }

if "$validate" "$tmp/valid.md" >/dev/null 2>&1; then ok "valid dossier passes"; else bad "valid dossier should pass"; "$validate" "$tmp/valid.md"; fi

for f in no-decisions no-section has-tbd one-mermaid bad-evidence one-option no-abort missing-lens few-evidence prose-evidence fenced-section no-recommendation no-open-marker; do
  if "$validate" "$tmp/$f.md" >/dev/null 2>&1; then bad "$f should fail"; else ok "$f fails as expected"; fi
done

for f in fence-todo quoted-repo indented-mermaid; do
  if "$validate" "$tmp/$f.md" >/dev/null 2>&1; then ok "$f passes"; else bad "$f should pass"; "$validate" "$tmp/$f.md"; fi
done

echo "---"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
