#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-addon-distribution.sh — an addon goes out on purpose, or not at all.
#
# Two rules, one check, because they answer the same question: may this leave?
#
#   1. The private directory stays private. system/addons-private/ is where an
#      addon lives that must never be published. The gitignore does the work;
#      this check is what notices when it stops doing it.
#
#   2. Someone else's work names its licence. An addon whose `author:` is not
#      the maintainer must carry `license:`. A licence in README prose is one
#      nothing can read, so nothing would notice an addon that omits it.
#
# Deliberately fails closed. A new addon with no author is treated as the
# maintainer's own (the common case); a new addon with someone else's name and
# no licence stops the run until a human answers.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

OWNER="${AGENTBRAIN_ADDON_OWNER:-frontmatters}"
PRIVATE_DIR="system/addons-private"
REG="scripts/lib/exemptions.tsv"
errors=0
checked=0
exempt=0
exempt_names=""

# ── 1. the private directory must be unpublishable ──────────────────────────
if [ -d "$PRIVATE_DIR" ]; then
	# Tracked files here would ship: release.sh builds from git ls-files.
	tracked="$(git ls-files "$PRIVATE_DIR" 2>/dev/null | head -5)"
	if [ -n "$tracked" ]; then
		echo "FAIL $PRIVATE_DIR is tracked, so it ships. Files:" >&2
		printf '  %s\n' $tracked >&2
		echo "  -> git rm --cached them, and check .gitignore covers the directory" >&2
		errors=$((errors + 1))
	fi
	# An ignored directory that git does not actually ignore is the same trap
	# one layer up: the rule exists, nothing enforces it.
	if ! git check-ignore -q "$PRIVATE_DIR/." 2>/dev/null; then
		echo "FAIL $PRIVATE_DIR exists but .gitignore does not cover it" >&2
		echo "  -> add '/$PRIVATE_DIR/' to .gitignore before putting anything there" >&2
		errors=$((errors + 1))
	fi
fi

# ── 2. third-party addons name their licence ────────────────────────────────
is_exempt() { # <addon-name>
	[ -f "$REG" ] || return 1
	# Field 1 is the check, field 2 the pattern. Matching on the whole field
	# rather than a substring: "hallmark" must not exempt "hallmark-extra".
	awk -F'\t' -v n="$1" '$1 == "check-addon-license" && $2 == n { found = 1 }
	                      END { exit found ? 0 : 1 }' "$REG"
}

for m in system/addons/*/manifest.md; do
	[ -f "$m" ] || continue
	addon="$(basename "$(dirname "$m")")"
	author="$(awk '/^author:/{sub(/^author:[[:space:]]*/,""); print; exit}' "$m")"
	license="$(awk '/^license:/{sub(/^license:[[:space:]]*/,""); print; exit}' "$m")"

	# No author, or the maintainer's own: nothing to attribute.
	[ -n "$author" ] || continue
	[ "$author" = "$OWNER" ] && continue
	# The template ships a placeholder author on purpose; it is not an addon.
	[ "$addon" = "_template" ] && continue

	checked=$((checked + 1))
	[ -n "$license" ] && continue

	if is_exempt "$addon"; then
		exempt=$((exempt + 1))
		exempt_names="$exempt_names $addon"
		continue
	fi
	echo "FAIL system/addons/$addon: author '$author' is not $OWNER and no license: field" >&2
	echo "  -> add 'license: <SPDX-id>' to manifest.md (NONE when upstream publishes none)," >&2
	echo "     or register a dated exemption in $REG with the reason" >&2
	errors=$((errors + 1))
done

# ── 3. a private addon never reaches a public release ─────────────────────────
# `distribution: private` in a manifest means the add-on must never be
# included in a public release.
# Its own licence says so too, so a copy that leaks is not free to use. And the
# public files must not name it: a changelog line or a skill that offers it
# advertises what outsiders cannot get. A file that has to name one (a test
# list) takes a dated or structural exemption in the registry, check
# "private-addon-name", pattern = the file.
PRIVATE_LICENSE="LicenseRef-PolyForm-Internal-Use-1.0.0"
private=""
for m in system/addons/*/manifest.md; do
	[ -f "$m" ] || continue
	grep -Eq '^distribution:[[:space:]]*private([[:space:]]|$)' "$m" || continue
	addon="$(basename "$(dirname "$m")")"
	private="$private $addon"
	if grep -qx "$addon" scripts/lib/essential-addons.txt 2>/dev/null; then
		echo "FAIL system/addons/$addon: distribution: private, yet listed in scripts/lib/essential-addons.txt (it would ship in the public release)" >&2
		errors=$((errors + 1))
	fi
	license="$(awk '/^license:/{sub(/^license:[[:space:]]*/,""); print; exit}' "$m")"
	if [ "$license" != "$PRIVATE_LICENSE" ]; then
		echo "FAIL system/addons/$addon: distribution: private needs license: $PRIVATE_LICENSE (has '${license:-none}')" >&2
		errors=$((errors + 1))
	fi
	[ -f "system/addons/$addon/LICENSE" ] || { echo "FAIL system/addons/$addon: private addon without its LICENSE file" >&2; errors=$((errors + 1)); }
	while IFS= read -r f; do
		echo "FAIL $f: SPDX header is not $PRIVATE_LICENSE in a private addon" >&2
		errors=$((errors + 1))
	done < <(git ls-files "system/addons/$addon" | xargs grep -l 'SPDX-License-Identifier:' 2>/dev/null | xargs grep -L "SPDX-License-Identifier: $PRIVATE_LICENSE" 2>/dev/null)
done
if [ -n "$private" ]; then
	# What a public release ships: tracked files, minus the vault and minus
	# every addon that is not essential (the same cut framework-release makes).
	ess="$(grep -v '^#' scripts/lib/essential-addons.txt 2>/dev/null | grep . | paste -sd'|' -)"
	names="$(printf '%s\n' $private | paste -sd'|' -)"
	while IFS= read -r f; do
		case "$f" in vault/*) continue ;; esac
		[ -L "$f" ] && continue
		if [[ "$f" == system/addons/* ]]; then
			a="${f#system/addons/}"; a="${a%%/*}"
			[[ "$a" == *.md ]] || [[ "|$ess|" == *"|$a|"* ]] || continue
		fi
		awk -F'\t' -v n="$f" '$1 == "private-addon-name" && $2 == n { found = 1 } END { exit found ? 0 : 1 }' "$REG" 2>/dev/null && continue
		# A reference to the addon, not the word: its path, its name as code, or
		# "<name> addon". The public event-bus has event types that share a word.
		ref="addons/($names)\\b|\\| *($names) *\\||\`($names)\`|\\b($names)[ -]add-?ons?\\b"
		grep -Eq "$ref" "$f" 2>/dev/null || continue
		echo "FAIL $f: names a private addon ($(grep -Eo "$ref" "$f" | sort -u | paste -sd, -)); a public release would advertise it" >&2
		errors=$((errors + 1))
	done < <(git ls-files)
fi

if [ "$errors" -gt 0 ]; then
	echo "check-addon-distribution: $errors problem(s)" >&2
	exit 1
fi
# The exemptions are printed by name, not counted. A count is a number nobody
# revisits: "3 exempt" reads as handled, while three names read as three open
# questions with an owner. The register carries the reason and the end date;
# this line is what puts them in front of someone.
printf 'check-addon-distribution: ok (%d third-party addon(s), %d licensed)\n' \
	"$checked" "$((checked - exempt))"
if [ -n "$exempt_names" ]; then
	printf '  awaiting an answer, see %s:%s\n' "$REG" "$exempt_names"
fi
