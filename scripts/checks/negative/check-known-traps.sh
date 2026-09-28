#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-known-traps.sh. Each arm has a twin: the shape that
# bites, and the shape that does not. An arm that fires on both is noise, an arm
# that fires on neither is decoration.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts/checks"
cp "$ROOT_DIR/scripts/checks/check-known-traps.sh" "$TMP/scripts/checks/"
printf '{ "unguarded": 0 }\n' > "$TMP/scripts/checks/.known-traps-ratchet.json"

cat > "$TMP/bad.sh" <<'SH'
#!/usr/bin/env bash
URL="${URL_TEMPLATE:-https://host/{tag}/{file}}"
ssh host 'cat > s.sh << "EOS"
x
EOS'
find "$HOME/agentBrain/vault" -name '*.md'
git push origin main | tail -20; echo "EXIT=$?"
tar --exclude='*.sh' -cf - . | tar -C "$OUT" -xf -
SH

cat > "$TMP/good.sh" <<'SH'
#!/usr/bin/env bash
URL="${URL_TEMPLATE:-}"
[ -n "$URL" ] || URL="https://host/{tag}/{file}"
NEST="${A:-${B:-$C}}"
scp local.sh host:/tmp/s.sh
find -L "$HOME/agentBrain/vault" -name '*.md'
find "$HOME/agentBrain/vault/preferences" -name '*.md'
out="$(git push origin main 2>&1)"; rc=$?
if out2="$(thing)"; then rc2=0; else rc2=$?; fi
tar --exclude='./*.sh' --exclude=.git -cf - . | tar -C "$OUT" -xf -
tar --exclude='*.log' -cf - . | tar -C "$OUT" -xf -
SH

# A file that asked for pipefail gets the pipeline status it wanted. Flagging it
# would make the exit arm noise in exactly the scripts that got this right.
cat > "$TMP/pipefail.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
git push origin main | tail -20; echo "EXIT=$?"
SH

cd "$TMP" || exit 1
git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm t

out="$(bash scripts/checks/check-known-traps.sh --list 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
	echo "NEGATIVE CASE FAILED: the ratchet accepted new known-trap occurrences" >&2
	exit 1
fi
for arm in brace heredoc walk exit tar; do
	printf '%s' "$out" | grep -q "$arm:" || {
		echo "NEGATIVE CASE FAILED: the $arm arm did not fire on its own example" >&2; exit 1; }
done
# pipefail.sh asked for the pipeline status, so the exit arm must stay silent
# there. An arm that cannot tell the two apart is noise dressed as a finding.
if printf '%s' "$out" | grep 'pipefail\.sh' | grep -q ' exit:'; then
	echo "NEGATIVE CASE FAILED: exit arm fired on a file that sets pipefail" >&2
	printf '%s\n' "$out" | grep 'pipefail\.sh' >&2
	exit 1
fi
if printf '%s' "$out" | grep -q 'good\.sh'; then
	echo "NEGATIVE CASE FAILED: flagged a shape that is not the trap" >&2
	printf '%s\n' "$out" | grep 'good\.sh' >&2
	exit 1
fi
echo "negative case holds: each arm fires on its trap and stays silent on the fix"
