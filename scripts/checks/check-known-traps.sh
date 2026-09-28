#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-known-traps.sh — recorded shell traps, guarded mechanically.
#
# Each arm is a recorded trap that can return or still sits in the tree. A note
# alone stops nothing; these are mechanical, so they get a guard.
#
#   brace     `${VAR:-...}` whose default contains `{`. Bash cuts the default at
#             the FIRST `}`, so a URL template loses a placeholder silently.
#             Example: `${URL_TEMPLATE:-https://host/{tag}/{file}}` arrives as
#             `https://host/{tag/{file}}`. Fix: assign the default separately.
#
#   root      ROOT computed from `dirname "$0"` without realpath. Real scripts
#             live in scripts/<sub>/ with compat symlinks at scripts/ root, so
#             the same expression climbs one level too far through the symlink
#             and ROOT becomes the parent of the repo. Fix: the house idiom,
#             `$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)`.
#
#   heredoc   `ssh host 'cat > f <<EOS ... EOS'`. The outer single quotes end at
#             the first quote in the payload, so every `'...'` inside is eaten.
#             The result is valid bash and fails hours later. Fix: write locally,
#             check with `bash -n`, then scp.
#
#   walk      `find` over the vault without -L. `vault/` is a symlink to the
#             private vault, so an unfollowed walk skips the entire thing and
#             reports success over the public half only.
#
#   exit      `$?` read after a pipeline, in a file without pipefail. It is the
#             status of the LAST stage (tail, head, grep), not of the command
#             the line asks about.
#
#   tar       `--exclude=*.sh` (a bare source extension). tar applies it to
#             every path it walks, so nested files of that type vanish from the
#             archive too. Fix: anchor the pattern with ./.
#
# Comment lines never count. WARN-first with a ratchet, like check-decisions:
# an existing tree with hits must not break doctor on day one.
set -uo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
cd "$ROOT" || exit 1

EXEMPT='^(scripts/checks/check-known-traps\.sh|scripts/checks/negative/check-known-traps\.sh)$'
RATCHET="scripts/checks/.known-traps-ratchet.json"

LIST=false
[ "${1:-}" = "--list" ] && LIST=true

# Compat symlinks in scripts/ are what makes the root arm real, so resolve them
# once instead of per file.
SYMLINKED_TARGETS=""
while IFS= read -r l; do
	t="$(realpath "$l" 2>/dev/null)" || continue
	t="${t#$ROOT/}"
	SYMLINKED_TARGETS="$SYMLINKED_TARGETS $t"
done < <(find scripts system -type l 2>/dev/null)

hits=0
while IFS= read -r f; do
	[ -f "$f" ] || continue
	[[ "$f" =~ $EXEMPT ]] && continue
	# Is there a symlink anywhere in the tree resolving to this file?
	sym=0
	case " $SYMLINKED_TARGETS " in *" $f "*) sym=1 ;; esac
	# A file that sets pipefail has asked for the pipeline's status; the exit arm
	# must not fire there.
	pf=0; grep -qE '^[ \t]*set[ \t].*pipefail' "$f" && pf=1
	out="$(awk -v F="$f" -v SYMLINKED="$sym" -v PIPEFAIL="$pf" '
	{ line = $0 }
	line ~ /^[ \t]*#/ { next }

	# brace: a LITERAL { inside the default. A nested ${...} is fine and common
	# (`${A:-${B}-x}`), so strip those before looking, or every nested default
	# reads as a hit.
	{
		# Strip the INNERMOST ${...} repeatedly. A nested default is still a
		# nested expansion (`${A:-${B:-$C}}`), so matching only ${NAME} leaves
		# those behind and every one of them reads as a literal brace.
		probe = line
		while (match(probe, /\$\{[^{}]*\}/)) {
			probe = substr(probe, 1, RSTART - 1) "X" substr(probe, RSTART + RLENGTH)
		}
		if (probe ~ /\$\{[A-Za-z_][A-Za-z0-9_]*:-[^}]*\{/)
			printf "WARN %s:%d brace: `${VAR:-...}` default contains a literal `{`, bash cuts it at the first `}`\n", F, NR
	}

	# root: only where it can actually bite. Every dirname-without-realpath is
	# theoretically fragile, but the climb only goes wrong when the script is
	# ALSO reachable through a compat symlink. Without that condition this arm
	# points at no specific risk.
	SYMLINKED == 1 && line ~ /dirname[ \t]+"?\$(0|\{BASH_SOURCE\[0\]\})"?/ && line ~ /\/\.\./ && line !~ /realpath/ {
		printf "WARN %s:%d root: ROOT from dirname without realpath, and a compat symlink points here\n", F, NR
	}

	# heredoc: a remote heredoc through ssh quoting
	line ~ /ssh[ \t]/ && line ~ /cat[ \t]*>/ && line ~ /<</ {
		printf "WARN %s:%d heredoc: remote heredoc through ssh quoting eats quotes, scp a checked file instead\n", F, NR
	}

	# walk: only a walk over the vault ROOT can miss the vault/ symlink. A find into a
	# specific subdirectory (vault/preferences, vault/sessions/archive) never
	# passes the symlink, and counting those would only add noise.
	line ~ /find[ \t]+(-[a-zA-Z]+[ \t]+)*"?\$?[A-Za-z_{}$\/.]*vault"?[ \t]/ && line !~ /vault\// && line !~ /find[ \t]+-L/ {
		printf "WARN %s:%d walk: find over the vault root without -L skips the vault/ symlink\n", F, NR
	}

	# exit: `$?` after a pipeline is the status of the LAST stage. tail and head
	# almost always succeed, so the command meant to establish whether something
	# worked cannot report that it did not.
	#
	# PIPEFAIL is read from the whole file before this runs: with `set -o
	# pipefail` the status IS that of the whole pipeline, and flagging those
	# would make the arm noise in exactly the scripts that got it right.
	PIPEFAIL == 0 && line ~ /\|[ \t]*(tail|head|grep|sed|awk|cut)[^|]*$/ && line ~ /\$\?/ {
		printf "WARN %s:%d exit: `$?` after a pipe is the last stage, not the command you asked about\n", F, NR
	}

	# tar: --exclude applies to every path tar walks, not just the directory it
	# starts in. An exclude meant for the root therefore also removes anything
	# deeper that matches: --exclude=*.sh meant for the root also drops every
	# nested plugin.sh, the archive is still valid, and the step reports success.
	#
	# Only source extensions are flagged, and that distinction is the whole arm.
	# Artefacts (*.log, *.tmp, *.bak, *.swp, *.pyc) are meant tree-wide: nobody
	# wants a log file at any depth in a release, so --exclude=*.log is correct
	# unanchored and must not be flagged. Source (*.sh, *.py, *.ts, *.js,
	# *.json, *.md) is almost never meant tree-wide, because it is usually what
	# the archive is FOR.
	line ~ /--exclude=.?\*\.(sh|py|ts|js|mjs|json|md|yml|yaml)[^A-Za-z0-9]/ {
		printf "WARN %s:%d tar: --exclude with a bare *.ext matches every path tar walks, anchor it with ./\n", F, NR
	}
	' "$f")"
	if [ -n "$out" ]; then
		[ "$LIST" = true ] && printf '%s\n' "$out"
		hits=$((hits + $(printf '%s\n' "$out" | grep -c '^WARN ')))
	fi
done < <(git ls-files '*.sh' 2>/dev/null)

ceiling="$(sed -n 's/.*"unguarded" *: *\([0-9]*\).*/\1/p' "$RATCHET" 2>/dev/null || true)"
ceiling="${ceiling:-$hits}"

if [ "$hits" -gt "$ceiling" ]; then
	printf 'FAIL known traps present: %d -> %d (may only fall).\n' "$ceiling" "$hits" >&2
	printf '  -> fix the new one, or lower the ratchet. Run with --list to see which.\n' >&2
	exit 1
fi
if [ "$hits" -lt "$ceiling" ]; then
	printf 'check-known-traps: ok (%d, below the ceiling of %d — lower %s)\n' "$hits" "$ceiling" "$RATCHET"
	exit 0
fi
printf 'check-known-traps: ok (%d known-trap occurrence(s), ceiling %d)\n' "$hits" "$ceiling"
