#!/usr/bin/env bash
# fix.sh — auto-repair for the MECHANICAL class of doctor findings.
# Invoked via `doctor.sh --fix` or standalone. Everything here is idempotent,
# loses no data, and only touches state that is derivable from the repo itself:
#
#   1. regenerate system/addons/clients.md when it drifted from the manifests
#   2. .github/skills/ symlinks: recreate missing ones, remove dangling ones
#   3. restore lost exec bits on scripts/, .githooks/ and addon entrypoints
#   4. namespace backup into local/
#   5. ~/agentBrain alias repair
#   6. re-sync brain skills into agent dirs (setup-skills.sh) on drift
#   7. create expected local/ working dirs
#
# Anything requiring judgement (content, manifests, privacy) stays manual —
# fix.sh repairs plumbing, never knowledge.
#
# Exit 0 always (a repair pass never blocks); each repair prints one line.

set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

fixed=0

# ── 1. clients.md drift ──
if [ -x scripts/addons.sh ] && [ -f system/addons/clients.md ]; then
	before="$(cksum system/addons/clients.md)"
	bash scripts/addons.sh clients --write >/dev/null 2>&1 || true
	after="$(cksum system/addons/clients.md)"
	if [ "$before" != "$after" ]; then
		echo "fix: regenerated system/addons/clients.md (was out of sync with manifests)"
		fixed=$((fixed + 1))
	fi
fi

# ── 2. .github/skills symlinks ──
if [ -d system/skills ] && [ -d .github/skills ]; then
	# Remove dangling links (target gone).
	for link in .github/skills/*; do
		[ -L "$link" ] || continue
		if [ ! -e "$link" ]; then
			rm "$link"
			echo "fix: removed dangling symlink $link"
			fixed=$((fixed + 1))
		fi
	done
	# Recreate missing links for every canonical skill.
	for skill in system/skills/*/; do
		name="$(basename "$skill")"
		dest=".github/skills/$name"
		if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
			ln -s "../../system/skills/$name" "$dest"
			echo "fix: created symlink $dest -> ../../system/skills/$name"
			fixed=$((fixed + 1))
		fi
	done
fi

# ── 3. exec bits ──
while IFS= read -r -d '' f; do
	chmod +x "$f"
	echo "fix: restored exec bit on $f"
	fixed=$((fixed + 1))
done < <(find scripts .githooks system/addons/*/bin -maxdepth 1 -type f \
	\( -name '*.sh' -o -path '*/bin/*' -o -path '.githooks/*' \) ! -perm -u+x -print0 2>/dev/null)

# ── 4. namespace backup into local/ (rides the private repo) ──
# Only the namespace is backed up: brain.json's path/created fields differ per
# checkout (dev vs live share local/), so a full-file backup would flap.
if [ -f brain.json ] && [ -d local ]; then
	ns="$(python3 -c 'import json;print(json.load(open("brain.json")).get("namespace",""))' 2>/dev/null || true)"
	if [ -n "$ns" ]; then
		if [ "$(cat local/brain-namespace.backup 2>/dev/null)" != "$ns" ]; then
			printf '%s\n' "$ns" > local/brain-namespace.backup
			echo "fix: refreshed local/brain-namespace.backup (UUID5 namespace backed up in the private repo)"
			fixed=$((fixed + 1))
		fi
	else
		echo "fix: SKIPPED namespace backup — brain.json unreadable or namespace empty; NOT touching the last good backup" >&2
	fi
fi

# ── 5. ~/agentBrain alias repair ──
ALIAS="${AGENTBRAIN_ALIAS:-$HOME/agentBrain}"
if [ -L "$ALIAS" ] && [ ! -e "$ALIAS" ]; then
	ln -sfn "$ROOT_DIR" "$ALIAS"
	echo "fix: relinked dangling alias $ALIAS -> $ROOT_DIR (was: broken)"
	fixed=$((fixed + 1))
fi

# ── 6. agent skill symlinks (re-sync brain skills into agent dirs) ──
# setup-skills.sh is idempotent and only touches brain-owned symlinks, so a
# re-run is safe. Catches skills added to the vault after the initial install.
if [ -x scripts/setup-skills.sh ] || [ -f scripts/setup-skills.sh ]; then
	if bash scripts/check-skill-links.sh >/dev/null 2>&1; then
		: # in sync — nothing to do
	else
		bash scripts/setup-skills.sh >/dev/null 2>&1 || true
		echo "fix: re-ran setup-skills.sh (agent skill symlinks were out of sync)"
		fixed=$((fixed + 1))
	fi
fi

# ── 7. expected local working dirs ──
for d in local/findings local/sessions local/logs local/backlog local/reviews local/addons; do
	if [ ! -d "$d" ]; then
		mkdir -p "$d"
		echo "fix: created missing dir $d/"
		fixed=$((fixed + 1))
	fi
done

if [ "$fixed" -eq 0 ]; then
	echo "fix: nothing to repair — plumbing healthy"
else
	echo "fix: $fixed repair(s) applied"
fi
exit 0
