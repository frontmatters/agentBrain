#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Claude PreToolUse matcher '*': refuse recognizable secrets before tool execution.

Only tool_input is scanned; diagnostics never contain excerpts from it.
Malformed payloads are allowed (not a license to guess at arbitrary text).
"""
import json
import re
import sys

# Narrow shapes; a bare SHA, ordinary prose and variable references are not secrets.
PATTERNS = (
    ("Authorization token", re.compile(r"(?i)\b(?:authorization\s*[:=]\s*|['\"]authorization['\"]\s*[:=]\s*)(?:['\"])?(?:token\s+[a-f0-9]{40}|bearer\s+[a-z0-9._~+/-]{20,}|basic\s+[a-z0-9+/]{16,}={0,2})(?![\w+/=])")),
    ("HTTP Basic credential", re.compile(r"(?:^|\s)(?:-u|--user)(?:\s+|=)['\"]?[^\s:'\"]+:([A-Za-z0-9._~+!@#%^-]{8,})(?![\w])")),
    ("URL userinfo credential", re.compile(r"(?i)https?://[^\s'\"/?:@]+:(?P<password>[A-Za-z0-9._~+%!-]{8,})@[^\s'\"/@]+")),
    ("secret assignment", re.compile(r"(?i)\b(?:[a-z][a-z0-9]*_)*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY)\s*[:=]\s*['\"]?([A-Za-z0-9_.~-]{16,})(?![\w/])")),
    ("token value", re.compile(r"(?i)\btoken\s+[a-f0-9]{40}\b")),
    ("GitHub token", re.compile(r"(?<![\w])(?:gh[posu]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59})(?![\w])")),
    ("API key", re.compile(r"(?<![\w])(?:sk-" + r"ant-[A-Za-z0-9_-]{40,}|sk-proj-[A-Za-z0-9_-]{40,}|sk-[A-Za-z0-9]{48,})(?![\w])")),
    ("Slack token", re.compile(r"(?<![\w])xox[baprs]-[A-Za-z0-9-]{30,}(?![\w])")),
    ("AWS access key", re.compile(r"(?<![\w])AKIA[0-9A-Z]{16}(?![\w])")),
    ("private key", re.compile(r"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE" + r" KEY-----")),
    ("URL credential", re.compile(r"(?i)https?://[^\s'\"<>?#]+\?[^\s'\"<>#]*?\b(?:password|token)=[A-Za-z0-9._~+%/-]{20,}(?:[&#\s'\"]|$)")),
)


def is_placeholder(candidate):
    """Discard obvious filler without weakening the other secret-shape rules."""
    value = candidate.rsplit("-", 1)[-1].rsplit("_", 1)[-1]
    return bool(value) and max(value.count(ch) for ch in set(value)) / len(value) >= 0.75


def scan(value):
    if isinstance(value, str):
        for kind, pattern in PATTERNS:
            for match in pattern.finditer(value):
                if kind in ("GitHub token", "API key") and is_placeholder(match.group()):
                    continue
                if kind == "URL userinfo credential" and match.group("password").lower() == "password":
                    continue
                if kind == "secret assignment":
                    candidate = match.group(1)
                    # Identifier-like values are names in code, not literal secrets:
                    # letters joined by _ . or - (self.access_token, session-name),
                    # no digit. A real secret of this length nearly always has one.
                    if any(c in "_.-" for c in candidate) and all(c.isalpha() or c in "_.-" for c in candidate):
                        continue
                    if candidate.isalpha() and (len(candidate) < 24 or is_placeholder(candidate)):
                        continue
                return kind
    elif isinstance(value, dict):
        for key, item in value.items():
            if isinstance(key, str) and key.lower() == "authorization" and isinstance(item, str):
                if re.search(r"(?i)\b(?:bearer\s+[a-z0-9._~+/-]{20,}|basic\s+[a-z0-9+/]{16,}={0,2})(?![\w+/=])", item):
                    return "Authorization token"
            found = scan(item)
            if found:
                return found
    elif isinstance(value, list):
        for item in value:
            found = scan(item)
            if found:
                return found
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        tool_input = payload.get("tool_input", {}) if isinstance(payload, dict) else {}
    except (ValueError, UnicodeError):
        return 0
    kind = scan(tool_input)
    if kind:
        print(f"Blocked: {kind} detected in tool input. Use a secret reference instead.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
