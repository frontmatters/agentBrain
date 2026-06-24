#!/usr/bin/env bash
# Privacy guardrail for agentBrain shared layer.
# Scans tracked files (or the staged diff with --staged) for personal identifiers,
# private infrastructure, and secret-like tokens that do not belong in GitHub.

set -euo pipefail

MODE="${1:-tracked}"
SCAN_DIR=""

# --git-identity <dir>: standalone guard for repos that get pushed publicly.
# Fails if any author/committer email in the whole history is not a noreply
# address. Catches a real personal/business email leaking into public git
# history — which the content scan (it skips .git) cannot see.
# Allowlist override: AGENTBRAIN_NOREPLY_PATTERN (default: matches "noreply").
if [ "$MODE" = "--git-identity" ]; then
	GIT_ID_DIR="${2:?usage: privacy-scan.sh --git-identity <repo>}"
	[ -d "$GIT_ID_DIR/.git" ] || { echo "Not a git repo: $GIT_ID_DIR" >&2; exit 2; }
	NOREPLY_PATTERN="${AGENTBRAIN_NOREPLY_PATTERN:-noreply}"
	bad="$(cd "$GIT_ID_DIR" && git log --format='%ae%n%ce' | sort -u \
		| grep -ivE "$NOREPLY_PATTERN" || true)"
	if [ -n "$bad" ]; then
		echo "Privacy scan failed: non-noreply email(s) in git history of $GIT_ID_DIR:" >&2
		printf '  %s\n' "$bad" >&2
		echo "Public repos must commit with a noreply identity (set GIT_COMMIT_EMAIL)." >&2
		exit 1
	fi
	echo "Git identity scan passed (all commits use a noreply email)."
	exit 0
fi

# Public/generic rules only. Do not hardcode personal project names here.
PATTERN='(/Users/|/home/[^[:space:]]+|192\.168\.|10\.[0-9]+\.|172\.(1[6-9]|2[0-9]|3[01])\.|[A-Za-z0-9_-]\.local(:[0-9]+)?|@gmail|@icloud|@outlook|(^|[^A-Za-z])ING([^A-Za-z]|$)|IBAN|bankrekening|rekeningnummer|gh[pousr]_[A-Za-z0-9_]{10,}|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{10,}|sk-ant|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN .*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+|xox[baprs]-[A-Za-z0-9-]{10,}|secret-value-here|real-token-here|your-password)'
LOCAL_DENYLIST="${AGENTBRAIN_PRIVACY_DENYLIST:-local/security/privacy-denylist.txt}"

case "$MODE" in
--staged | staged)
	if git diff --cached --name-only --quiet; then
		exit 0
	fi
	hits=$(git grep --cached -n -I -i -E "$PATTERN" -- . ':(exclude)local/**' || true)
	;;
tracked | --tracked)
	hits=$(git grep -n -I -i -E "$PATTERN" -- . ':(exclude)local/**' || true)
	;;
--dir)
	SCAN_DIR="${2:?usage: privacy-scan.sh --dir <path>}"
	[ -d "$SCAN_DIR" ] || { echo "Not a directory: $SCAN_DIR" >&2; exit 2; }
	# Skip .git: VCS internals (e.g. the remote URL in .git/config) are not
	# published content and legitimately reference private infrastructure.
	hits=$(grep -rn -I -i -E --exclude-dir=.git "$PATTERN" "$SCAN_DIR" 2>/dev/null || true)
	;;
*)
	echo "Usage: $0 [tracked|--staged|--dir <path>]" >&2
	exit 2
	;;
esac

# Optional local denylist: put private project/customer/user names in
# local/security/privacy-denylist.txt (gitignored), one grep -E pattern per line.
if [[ -f "$LOCAL_DENYLIST" ]]; then
	while IFS= read -r deny_pattern; do
		[[ -n "$deny_pattern" && ! "$deny_pattern" =~ ^[[:space:]]*# ]] || continue
		case "$MODE" in
		--staged | staged)
			extra_hits=$(git grep --cached -n -I -i -E "$deny_pattern" -- . ':(exclude)local/**' || true)
			;;
		--dir)
			extra_hits=$(grep -rn -I -i -E --exclude-dir=.git "$deny_pattern" "$SCAN_DIR" 2>/dev/null || true)
			;;
		*)
			extra_hits=$(git grep -n -I -i -E "$deny_pattern" -- . ':(exclude)local/**' || true)
			;;
		esac
		if [[ -n "$extra_hits" ]]; then
			hits="${hits}${hits:+$'\n'}${extra_hits}"
		fi
	done <"$LOCAL_DENYLIST"
fi

# Allow known-safe generic documentation examples.
hits=$(printf '%s\n' "$hits" |
	grep -v '^$' |
	grep -vE '(^|/)LICENSE:' |
	grep -v '^\.gitignore:' |
	grep -v '^scripts/privacy-scan\.sh:' |
	grep -v '^scripts/check-agentbrain-local\.sh:' |
	grep -v '^scripts/check-agentbrain-shared\.sh:' |
	grep -v '^tests/shared-vault/test-check-shared\.sh:' |
	grep -v '^tests/shared-vault/test-sync-shared\.sh:' |
	grep -v 'proxy\.example' |
	grep -v '192\.0\.2\.1' |
	grep -v '/home/linuxbrew' |
	grep -v 'localeCompare' |
	grep -v 'mymachine\.local' |
	grep -v 'system/Security-Guidance\.md' |
	grep -v '/bun\.lock:' ||
	true)

if [[ -n "$hits" ]]; then
	echo "Privacy scan failed. Move personal/project/security context to local/ or redact it:" >&2
	echo "$hits" >&2
	exit 1
fi

echo "Privacy scan passed."
