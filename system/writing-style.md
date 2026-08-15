---
date: 2026-08-08
type: system
tags: [writing, style, policy]
id: c03f2f46-a1c0-5366-b63b-77e305bbe185
---

# Writing style

The standard for every sentence a human reads: *The Elements of Style*
(Strunk). It applies to UI strings in scripts, questions in wizards, docs,
READMEs, changelog entries, error messages, and commit messages.

## The rules that earn their keep here

1. **Name the subject.** "How eagerly do you want updates?" fails — updates of
   what? "How eagerly do you want agentBrain updates?" passes. Every prompt,
   flag description, and error names the thing it acts on.
2. **Omit needless words.** One idea per sentence. Cut "please note that",
   "in order to", "simply", "just".
3. **Concrete over vague.** "2 minutes" beats "quick". "asks before updating"
   beats "safe behaviour". Never promise what you cannot verify.
4. **Active voice, parallel structure.** Options in a list share one grammatical
   shape ("finished releases only" / "new features earlier" / "every change
   immediately").
5. **Honest claims only.** A time estimate, a count, or a capability in user
   text must be true today — update the text when the code changes
   (see the "5 min" → "2 minutes" fix, 2026-08-08).

## Tooling

- **Claude Code**: the `elements-of-style` plugin ships the
  `writing-clearly-and-concisely` skill — invoke it when writing or editing
  prose. Its full reference costs ~12k tokens; load it only while writing.
- **Other agents**: this document is the standard; the rules above are the
  working set.
- **Doctor**: `scripts/check-writing-style.sh` guards this policy — the doc
  must exist, and user-facing strings are scanned for the needless-word
  denylist (warn-only: style is judgement, drift is the failure).

## Language

Source comments, system/ docs, and commit messages are English
(`check-english-sources.sh` enforces the comment half). User-facing runtime
text follows the user's chosen language via the locale mechanism.
