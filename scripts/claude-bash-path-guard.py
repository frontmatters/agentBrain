#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""PreToolUse hook for Claude Code, matcher "Bash".

Blocks a READ command that was handed a relative path which does not exist from the
current working directory.

Why this exists. The Bash tool keeps its working directory between calls, so a single
`cd elsewhere && ...` silently changes what every later relative path means. It fails
misleadingly: `grep packages/client/src/app.ts` reports "No such file or directory",
which reads as "that file is missing" rather than "you are standing somewhere else".
On 2026-09-15 one session walked into this four times — twice after writing a learning
about it, which is the whole point. A document cannot intervene at the moment a path is
typed. This can.

Deliberately narrow, because a hook that cries wolf gets switched off and is then worse
than no hook at all:

  - only read commands, never anything that creates or changes something;
  - the first positional of grep/rg/sed/awk is skipped: that is a PATTERN, and patterns
    contain slashes all the time (`grep "packages/client" .`) without being paths;
  - flags, variables, globs, URLs and absolute paths are all left alone;
  - a `cd X &&` prefix is honoured and the rest is resolved against X — which is exactly
    the self-contained form this guard is trying to encourage.

Python rather than bash: the job is tokenising a command line, and `shlex` does that
correctly where a shell one-liner would not.

Exit codes (Claude Code contract): 0 allow, 2 block with stderr as the reason.
"""
import json
import os
import shlex
import sys

READ_ONLY = {"grep", "rg", "cat", "sed", "head", "tail", "wc", "ls", "awk", "diff", "file", "stat", "du"}
# Commands whose first positional argument is a pattern or a script, not a path.
FIRST_ARG_IS_NOT_A_PATH = {"grep", "rg", "sed", "awk"}


REDIRECT_START = tuple("><|&;()`")


def is_redirect(token: str) -> bool:
    """`>/dev/null`, `2>&1`, `<in.txt` — a filename for the shell, not an argument we read."""
    if token.startswith(REDIRECT_START):
        return True
    return len(token) > 1 and token[0].isdigit() and token[1] in "<>"


def looks_like_a_relative_path(token: str) -> bool:
    if "/" not in token:
        return False
    if token.startswith(("/", "~", "$", "-")) or is_redirect(token):
        return False
    if "://" in token or "$" in token:
        return False
    return not any(ch in token for ch in "*?[")


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    command = (payload.get("tool_input") or {}).get("command", "")
    cwd = payload.get("cwd") or os.getcwd()
    if not command.strip():
        return 0

    # Judge each segment on its own, carrying the working directory across `cd`.
    for segment in command.replace("||", "&&").replace(";", "&&").split("&&"):
        segment = segment.strip()
        if not segment:
            continue
        try:
            tokens = shlex.split(segment, comments=True)
        except ValueError:
            continue  # unbalanced quotes: not ours to judge
        if not tokens:
            continue

        if tokens[0] == "cd":
            target = os.path.expanduser(tokens[1] if len(tokens) > 1 else "~")
            cwd = target if os.path.isabs(target) else os.path.join(cwd, target)
            continue

        if tokens[0] not in READ_ONLY:
            continue

        rest = tokens[1:]
        for i, t in enumerate(rest):          # everything from the first redirect on is the
            if is_redirect(t):                # shell's business, not an argument being read
                rest = rest[:i]
                break
        positionals = [t for t in rest if not t.startswith("-")]
        if tokens[0] in FIRST_ARG_IS_NOT_A_PATH and positionals:
            positionals = positionals[1:]

        for token in positionals:
            if not looks_like_a_relative_path(token):
                continue
            if not os.path.exists(os.path.join(cwd, token)):
                print(
                    f"Blocked: '{token}' does not exist from the current working "
                    f"directory ({cwd}).\n"
                    "The Bash tool keeps its working directory between calls, so an "
                    "earlier `cd` may have moved you. This would have failed as 'No such "
                    "file or directory', which reads like the file is missing rather "
                    "than that you are standing somewhere else.\n"
                    "Use an absolute path, or make the call self-contained: "
                    "`cd /absolute/dir && <command>`.",
                    file=sys.stderr,
                )
                return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
