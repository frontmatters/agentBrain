---
date: 2026-06-04
type: system
tags: [skill, brain-unhide]
id: 1b94f3a3-cfed-5fde-a434-96ecdf95fbb3
---

# brain-unhide

Bring a hidden note back into listings.

## Purpose

Removes the `hidden:` and `hidden-at:` frontmatter lines so `/list-parks`, `/list-learnings`, and `/list-projects` find the note again.

## Usage

```
/brain-unhide <type>/<slug>
/brain-unhide <N>
```

`<N>` is the row number from `/list-hidden`.

## Related

- [[brain-hide]] — counterpart that hides notes
- [[list-hidden]] — discover hidden notes by number
