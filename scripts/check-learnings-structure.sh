#!/usr/bin/env bash
# check-learnings-structure.sh — Enforce flat learnings.
# Rule: learnings are flat `<category>.md` files organized by frontmatter `tags` (+ UUID +
# `[[wiki-links]]`), NOT by folders. Subfolders are the convention for *projects*
# (local/projects/<name>/), not learnings. The only sanctioned learnings subfolder is
# `extracted/` (machine-generated auto-extraction output, distinct provenance — not a topic).
# Runs against both the public template layer (learnings/) and the private layer
# (local/learnings/); local/ is absent in CI, so it is skipped there.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SANCTIONED="extracted"
errors=0

for base in learnings local/learnings; do
	[ -d "$base" ] || continue
	# (a) no topic subfolders (only sanctioned ones)
	for d in "$base"/*/; do
		[ -d "$d" ] || continue
		name="$(basename "$d")"
		case " $SANCTIONED " in *" $name "*) continue ;; esac
		echo "FAIL $base/$name/ is a topic subfolder — learnings are flat <category>.md + tags." >&2
		echo "  -> flatten the notes (rely on frontmatter tags), or move project content to local/projects/$name/." >&2
		errors=$((errors + 1))
	done
	# (b) every flat learning note has frontmatter (closes the gap that check-frontmatter
	#     leaves open by exempting local/). The /save-learning schema fields go inside it.
	for f in "$base"/*.md; do
		[ -f "$f" ] || continue
		case "$(basename "$f")" in README.md | _example.md) continue ;; esac
		[ "$(head -n 1 "$f")" = "---" ] || {
			echo "FAIL $f has no frontmatter — learnings need frontmatter (date/type/tags/id)." >&2
			errors=$((errors + 1))
		}
	done
done

if [ "$errors" -gt 0 ]; then
	echo "check-learnings-structure: $errors disallowed learnings subfolder(s) — see rule in system/skills/save-learning/SKILL.md" >&2
	exit 1
fi
echo "check-learnings-structure: learnings are flat (sanctioned subfolder: $SANCTIONED)"
