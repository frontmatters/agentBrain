---
name: rename-symbol
description: Rename a function, method, variable or key across a codebase without breaking the things that are not code. Use when a name has to change everywhere - a language convention, a clearer word, a corrected term - and the symbol appears in more than one file. Not for agentBrain's own files; that is refactor-brain.
argument-hint: The symbol to rename, and what it should become
user-invocable: true
related:
  - refactor-brain
resources:
  - sweep.sh
---

# rename-symbol

A rename looks like find-and-replace and is not. The symbol lives in code, but the
same letters also live in sentences a person reads, in records of what something
*used* to be called, and in CSS class names that no compiler checks. Replace all of
them and the build still passes, the tests still pass, the diff still looks correct,
and something is quietly broken.

**The rule: a rename follows the symbol, not the file.**

## When to use

- A name has to change everywhere: a language convention, a clearer word, a term
  the domain corrected.
- The symbol crosses files: a port declaration, its implementations, every import,
  every call site, and the fakes in the tests.

## When not to use

- Renaming agentBrain's own files or paths: that is `refactor-brain`.
- A symbol that lives in exactly one function and is never exported. Rename it in
  place; this procedure is overhead.
- Anything an IDE's "rename symbol" can do end to end AND you can verify. Use the
  tool; then still run step 5.

## The three categories

Every hit falls into one, and only the first may change:

| | What it is | Rename? |
|---|---|---|
| **Code** | declarations, imports, call sites, test fakes, type members | **yes** |
| **Copy** | i18n catalogues, page prose, labels, placeholders, alt text | **no** - a person reads this |
| **Evidence** | changelogs, decision records, handovers, fixtures, a `bewijs` field | **no** - it records what the thing *was* called |

Evidence is the one people miss. A file that says "the judgement was made on
`telOngelezen`" becomes a lie when you rename it there: the judgement was not made
on `countUnread`, because that name did not exist yet.

## Steps

### 1. Sweep, and read the categories

```bash
bash sweep.sh <symbol> [roots...]
```

It splits every hit into code, copy and evidence, and warns when the symbol is under
five characters. Read the copy and evidence lists before you touch anything: those
are the files your replacement must not reach.

### 2. Choose the scope by how short the name is

- **Five characters or more, distinctive**: a word-boundary replace across the code
  roots is safe.
- **Under five characters**: by hand, one at a time. A three-letter name sits inside
  other words and inside running text, and no boundary match saves you from a
  `tel` that is a count in one place and an abbreviation in another.

Word boundaries: BSD `sed` (macOS) does **not** support `\b`. It fails silently,
reporting success while changing nothing. Use `perl -pi`, GNU `sed`, or a small
Python/Node script.

### 3. Rename the code, and only the code

Restrict the walk to the code roots the sweep listed. Never run the replacement over
the repository root "and then fix the damage" - the damage is the part you cannot see.

### 4. Check that nothing is left behind

```bash
grep -rnw -- "<old>" <roots> | grep -v <the evidence files you decided to keep>
```

An empty result here plus a green type check means the code half is done.

### 5. Verify by running, never by reading the diff

This is the step that catches what the others miss, and the reason is worth stating:
**a leak into copy looks correct in a diff.** `names` where `namen` belonged is a
well-formed word in a well-formed sentence. The diff cannot tell you it is wrong.

- Type check and the **full** test suite, not the tests you think are affected.
- A test run that reports skipped tests has not verified those. Say so, or run them.
- If the symbol touched anything rendered, **look at every screen that shows it**:
  - Render the page and read the prose for words from the other language:
    ```bash
    python3 - <<'EOF'
    import re, html
    s = open('page.html').read()
    prose = re.sub(r'<table.*?</table>|<code[^>]*>.*?</code>', ' ', s, flags=re.S)
    text = html.unescape(re.sub(r'<[^>]+>', ' ', prose))
    print(re.findall(r'\b(name|names|row|rows|count|list)\b', text, re.I) or 'clean')
    EOF
    ```
  - Check the rendered values, not just that the page loads: an empty string, `NaN`
    or `undefined` where a number belonged is what a broken rename looks like.
  - Walk shadow roots if the app uses them. `document.body.innerText` stops at a
    shadow boundary and returns an empty page, which reads as "the thing is gone"
    when it means "I could not see".
  - Always include a **positive control**: assert something you know is on the page.
    Without it, "the bad string is absent" and "I measured nothing" are the same
    result.
  - A screen you could not reach is **not verified**. Name it as a gap. Tests
    covering it is worth saying; it is not the same claim.

## Traps

- **A blanket regex over one file hits its own prose.** Renaming a generator's
  identifiers rewrote the page it generates: "dan passeren die *names* stil".
- **CSS class names are not type-checked.** The same sweep renamed `.namen` to
  `.names` in the markup but not the stylesheet, and 245 rows lost their styling
  with no error anywhere.
- **Order matters inside one edit.** Replacing the symbol first and then trying to
  fix a comment that mentioned it leaves the comment mangled, because the text you
  were matching on is already gone.
- **A short name means different things in different places.** One `tel` was a
  count, another was a regex match holding a counter token. Renaming both to
  `count` would have made the second name a lie.
- **The rename is only half the job when a gate is involved.** If a naming gate was
  letting the old name through, fix the gate too, or the next one arrives unnoticed.

## Related

- [[refactor-brain]] - the same care, for agentBrain's own files and paths
- [[forward:self-review]] - the honesty ledger, for what you changed but did not verify
