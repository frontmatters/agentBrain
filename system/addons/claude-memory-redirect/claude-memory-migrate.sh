#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Migrate existing Claude per-project memory files into agentBrain with normalized frontmatter.
# Idempotent: safe to re-run; files already in agentBrain shape get a no-op.
# Usage:
#   claude-memory-migrate.sh                # current project only (derived from $PWD)
#   claude-memory-migrate.sh --all          # all ~/.claude/projects/*/memory/
#   claude-memory-migrate.sh <project-dir>  # specific project dir
#   claude-memory-migrate.sh --dry-run
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
LOCAL_CONFIG="$BRAIN_ROOT/vault/memories/claude-redirect-config.json"
DEFAULT_CONFIG="$HERE/config.default.json"
config_path="$DEFAULT_CONFIG"
[[ -f "$LOCAL_CONFIG" ]] && config_path="$LOCAL_CONFIG"

target_rel="$(python3 -c "
import json
c = json.load(open('$config_path'))
print(c.get('target_root','vault/memories/projects'))
" 2>/dev/null || echo "vault/memories/projects")"

default_type="$(python3 -c "
import json
c = json.load(open('$config_path'))
print(c.get('normalize',{}).get('default_type','feedback'))
" 2>/dev/null || echo feedback)"

dry_run=0
specific=""
all_projects=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) dry_run=1; shift ;;
		--all) all_projects=1; shift ;;
		--*) echo "unknown flag: $1" >&2; exit 2 ;;
		*) specific="$1"; shift ;;
	esac
done

projects_root="$HOME/.claude/projects"

# Derive Claude Code's encoded-cwd dir for the current $PWD.
# Encoding rule: /, _, and space → -
derive_current_project_dir() {
	local pwd_encoded
	pwd_encoded="$(printf '%s' "$PWD" | tr '/_ ' '---')"
	if [[ -d "$projects_root/$pwd_encoded" ]]; then
		printf '%s' "$projects_root/$pwd_encoded"
	fi
}

dirs=()
if [[ -n "$specific" ]]; then
	dirs+=("$specific")
elif [[ "$all_projects" -eq 1 ]]; then
	while IFS= read -r d; do
		dirs+=("$d")
	done < <(find "$projects_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
else
	current="$(derive_current_project_dir)"
	if [[ -z "$current" ]]; then
		echo "no Claude Code project dir found for current cwd ($PWD)" >&2
		echo "use --all to migrate every project, or pass a dir explicitly" >&2
		exit 0
	fi
	dirs+=("$current")
fi

migrated_count=0
skipped_count=0

for project_dir in "${dirs[@]}"; do
	memory_dir="$project_dir/memory"
	# Resolve symlinks so we don't loop on already-redirected projects.
	if [[ -L "$memory_dir" ]]; then
		echo "↪ $(basename "$project_dir") already symlinked — skipping migrate"
		((skipped_count++)) || true
		continue
	fi
	[[ ! -d "$memory_dir" ]] && continue

	slug="$(bash "$HERE/slug.sh" "$project_dir")"
	target_rel="vault/${target_rel#local/}"; target_rel="${target_rel#vault/vault/}"   # an older config still says local/
	target_dir="$BRAIN_ROOT/$target_rel/$slug"
	mkdir -p "$target_dir"

	# Migrate each .md file.
	while IFS= read -r -d '' file; do
		base="$(basename "$file")"
		dest="$target_dir/$base"

		# Normalize: add UUID5 + agentBrain frontmatter where missing.
		# The uuid5-gen fallback used to be silent (`|| echo ""`), so a broken
		# generator would migrate a file WITHOUT an id and corrupt the vault's
		# frontmatter invariant unnoticed. Make it loud: if generation fails AND the
		# source file has no usable id of its own, abort with a clear message instead
		# of writing an id-less note. (The PostToolUse validate-hook would reject such
		# a note anyway — better to fail here, at the source.)
		vault_rel_no_ext="$target_rel/$slug/${base%.md}"
		new_uuid=""
		if uuid_out="$(bash "$BRAIN_ROOT/scripts/uuid5-gen.sh" "$vault_rel_no_ext" 2>&1)"; then
			new_uuid="$uuid_out"
		else
			gen_err="$uuid_out"
		fi
		if [[ -z "$new_uuid" ]]; then
			# Does the source already carry an id we can keep? grep its frontmatter.
			existing_id="$(awk '/^---[[:space:]]*$/{fm++; next} fm==1 && /^id:[[:space:]]*/{sub(/^id:[[:space:]]*/,""); print; exit}' "$file" 2>/dev/null || true)"
			if [[ -z "$existing_id" ]]; then
				echo "claude-memory-migrate: FAILED to generate a UUID5 for '$vault_rel_no_ext'" >&2
				echo "  uuid5-gen.sh output: ${gen_err:-<empty>}" >&2
				echo "  source file '$file' also has no 'id:' to preserve." >&2
				echo "  Refusing to migrate an id-less note (would break the frontmatter invariant)." >&2
				echo "  Fix scripts/uuid5-gen.sh (needs python3 + a vault namespace) and re-run." >&2
				exit 1
			fi
			echo "claude-memory-migrate: uuid5-gen failed for '$base'; preserving its existing id '$existing_id'" >&2
		fi

		if [[ "$dry_run" -eq 1 ]]; then
			echo "DRY: $file → $dest (uuid=$new_uuid)"
			continue
		fi

		python3 - "$file" "$dest" "$new_uuid" "$default_type" "$slug" <<'PYEOF'
import sys, re, os
from datetime import datetime
src, dst, new_uuid, default_type, slug = sys.argv[1:6]
text = open(src, encoding="utf-8", errors="replace").read()

# Parse existing frontmatter (if any).
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
fm_data = {}
body = text
if m:
    fm_raw = m.group(1)
    body = text[m.end():]
    for line in fm_raw.splitlines():
        km = re.match(r"^([a-zA-Z0-9_-]+):\s*(.*)$", line)
        if km:
            fm_data[km.group(1).strip()] = km.group(2).strip()

# Apply agentBrain conventions, preserving existing values when present.
fm_data.setdefault("date", datetime.now().strftime("%Y-%m-%d"))
fm_data.setdefault("type", default_type)
existing_tags = fm_data.get("tags", "")
if "claude-memory" not in existing_tags:
    if not existing_tags or existing_tags in ("[]","null","~"):
        fm_data["tags"] = f"[claude-memory, {slug}]"
    else:
        # Try to inject into a list, else append; best-effort.
        if existing_tags.startswith("["):
            fm_data["tags"] = existing_tags.rstrip("]") + ", claude-memory, " + slug + "]"
        else:
            fm_data["tags"] = f"[{existing_tags}, claude-memory, {slug}]"
if new_uuid and not fm_data.get("id"):
    fm_data["id"] = new_uuid

# Render frontmatter in canonical order.
order = ["date","type","tags","name","description","metadata","id"]
seen = set()
out_fm = []
for k in order:
    if k in fm_data:
        out_fm.append(f"{k}: {fm_data[k]}")
        seen.add(k)
for k,v in fm_data.items():
    if k not in seen:
        out_fm.append(f"{k}: {v}")

out = "---\n" + "\n".join(out_fm) + "\n---\n" + body
os.makedirs(os.path.dirname(dst), exist_ok=True)
with open(dst,"w",encoding="utf-8") as f:
    f.write(out)
print(f"migrated → {dst}")
PYEOF
		((migrated_count++)) || true
	done < <(find "$memory_dir" -maxdepth 1 -type f -name "*.md" -print0 2>/dev/null)

	if [[ "$dry_run" -ne 1 ]]; then
		echo "✓ $slug: migrated $(find "$memory_dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ') file(s) to $target_dir"
	fi
done

echo ""
echo "Total: migrated=$migrated_count skipped=$skipped_count"
[[ "$dry_run" -eq 1 ]] && echo "(dry run — no files written)"
exit 0
