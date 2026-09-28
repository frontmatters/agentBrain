---
name: decision-page
description: Turn open product or design decisions into one local HTML page the owner can decide on - per decision the current state (A), the advised proposal (B), the alternatives considered (C, D), wireframe mockups, pros and cons, a comparison table, what was rejected and why, evidence links, radio choices persisted in the browser and a "copy decisions as markdown" button that brings the answers back into the chat. Triggers - "show me the options", "what were the other options", "make a decision page", "I want to see what I am choosing", "put this on the page too", an open question with 2+ viable directions after a walkthrough or review.
---

# decision-page: options the owner can see, compare and answer

A decision the owner cannot see is a decision that stalls. This skill turns a
set of open decisions into one self-contained HTML file: every decision shows
what exists now, what you advise, what else you considered and what you
rejected, each with a wireframe, pros and cons, and evidence. The owner clicks
their choices; the page hands the answers back as markdown.

The skill exists because one-line questions in chat ("A or B?") get vague
answers, while a page with mockups next to each other gets decisions in one
pass, and the record of *why* survives the conversation.

## When to use

- After a walkthrough, review or audit produced findings that need an owner
  decision with two or more viable directions.
- When the owner asks "what were the other options?" or "what am I choosing?".
- When a decision has consequences the owner should see (a flow, a screen, a
  role), not just read.

Do **not** use it for a single yes/no, for decisions you can make yourself
under the project's conventions, or as a substitute for building the recipe.

## Hard rules

- **Local file, never published.** Write under the project's docs (for example
  `R&D/decisions/<date>-<topic>-decisions.html` when the repo has an `R&D/` folder, otherwise `docs/ux/<date>-<topic>-decisions.html`), open it with the OS opener, and
  never publish it to a hosted artifact: decision pages carry confidential
  product and client context.
- **Evidence over claims.** Every "now (A)" links to a real screenshot or
  measurement from the walkthrough; a claim without evidence is marked as such.
- **Advice is one option, visibly.** Exactly one option per decision is
  outlined as the advice; the others are equal cards, not straw men.
- **Rejected options are listed with the reason.** One line each, under the
  comparison table, so the owner does not ask "did you consider X?".
- **The page speaks the owner's language and the product's canonical terms**
  (roles, object names) from the glossary or spec; never invent names on the
  page that the product does not use.
- **Choices persist and travel back.** Radio per decision, optional remark,
  stored in `localStorage`, exported as a markdown table the owner pastes into
  the chat. Record the answers in the spec or decision log afterwards.

## Steps

1. **Collect the decisions.** From the findings (walkthrough table, review),
   list each decision as one sentence with the question mark at the end. Group
   sub-questions under the decision they belong to (a "3b" row rather than a
   new decision).
2. **Per decision, enumerate the option space** before writing: A = now, B =
   your advice, C and D = the other directions you weighed. If you only have A
   and B, you have not weighed enough; if you have five, merge or reject.
3. **Write each option as a card**: tag (Now / Proposal, advice / Option C),
   heading in one line, a wireframe in the page's mock idiom (rows, steppers,
   buttons, checks, a nav column), a plus-list and a min-list, and for "now"
   the evidence links (screenshots with step numbers).
4. **Add the comparison table**: one row per option, columns that matter for
   this decision (actions for the user, where a future feature lands, build
   size, risk). Highlight the advised row.
5. **Add the "also considered, rejected" line** with the reason.
6. **Add the choice block**: one radio per option plus a free text remark,
   `data-decision` set to the decision title so the markdown export is
   readable.
7. **Cross-decision dependencies**: when decisions interlock (a flow decision
   that changes where a later feature lands), add a short "coherence" note or
   a small table: what this decision needs from that one, and vice versa.
8. **Render-check before presenting**: open the file in a headless browser
   (see `check.mjs`), count the radios per decision, assert no horizontal
   scroll and no clipped card text, and look at a screenshot yourself.
9. **Present in one message**: the file path, the list of decisions with your
   advice in one line each, and how to answer (click, copy markdown, paste).
10. **When the answers come back**: record them in the spec or decision log
    with the date, then act. Update the page's title to mark it decided.

## Two shapes: the option page and the register page

The skill has two templates. Pick by *how many decisions* and *how much each one
needs*, not by taste.

**`template.html`, the option page.** Two to five decisions that each deserve
the full treatment: A/B/C/D cards, a wireframe per option, a comparison table,
what was rejected. Use it when the owner must *see* the consequence of a choice.

**`template-register.html` plus `register.js`, the register page.** Ten to twenty
decisions carried over from a gaplog, review or audit, where each is small but
none may be lost. Full option cards times sixteen is unreadable; here each
decision is one block: the problem, where it lives, the provenance of the
evidence, two or three options, and a note field. Grouped by theme, with a
running counter and a copy-out at the bottom.

What the register page adds beyond the option page:

- **Provenance per decision.** Every entry says `Measured today` (green) or
  `Quoted` (amber) with the date of the original measurement. This is the part
  that lets an owner stand behind a choice: a finding from three weeks ago that
  nobody re-ran is not the same as one you just watched fail. Never mark
  something measured that you did not run in this session.
- **A correction block** at the top for when an earlier decision page carried a
  premise that has since been disproved. An owner who decides on a claim you
  have already retracted has made a decision you will have to undo. State the
  wrong claim, the right number, and how you got it.
- **A multi-line note per decision, not a one-line remark.** The option page's
  single-line field gets single-line answers. A textarea that grows gets the
  actual reason, the "yes but", and the counter-question, which is often more
  valuable than the radio itself. A note without a choice is kept and counted
  separately: "I want to know what this costs first" is an answer.
- **A three-state theme switch** (system / light / dark), which is a house
  requirement for anything with a UI, not a nicety.

## Theme: the client's, otherwise the house style

A decision page is the owner's document but it speaks about a product. So:

1. **The client has a brand**: use their tokens and faces. The page sits next
   to their product; matching it is what makes the mockups legible as *their*
   screens.
2. **No client brand, or an internal page**: fall back to the agentBrain house
   style, flat, thin borders, lime accent, Sentient for headings, Instrument
   Sans for text, Spline Sans Mono for code. Never Inter, Roboto, Poppins or
   Lato as a display face; the slop test fails on them.

   There are **two** house palettes and they are not interchangeable. agentBrain
   is lime `#bef264` on near-black `#17171a`, as in its own onboarding mocks and
   landing animations. Frontmatters flat is orange `#dd4b12` / `#ff6a2c`. A page
   about agentBrain takes lime; a Frontmatters page takes orange. Lime is the
   identity but fails as text on a light ground, so the light theme darkens it
   to `#4d6b16` and keeps the real lime on the dark ground where the brand
   actually lives.

Swap only the token block and the font link at the top of the template. The rest
of the sheet reads through the tokens, so a rebrand is one edit, not a sweep.

## Language follows the context, from one attribute

A decision page is read by one person in one language, and which language that is
depends on the context it belongs to: a Dutch client's page is Dutch, an
international project's page is English, an internal agentBrain page follows the
framework's own convention.

Set it in one place: `<html lang="nl">` or `<html lang="en">`. The controls
around the decisions (the counter, "not chosen yet", the copy confirmation, the
reset question, the labels in the exported text) come from the `TAAL` dictionary
at the top of `register.js` and follow that attribute. Add a language by adding a
key to that object; never by editing the code that reads it.

The decisions themselves are authored in that same language: they are your
writing, not interface chrome, so there is no second copy to keep in sync. That
also means the page has no language switch, and should not get one. A switch
would promise a translation of the content that nobody wrote.

The trap this replaces: the counter, the export labels and the confirm dialog
used to sit hardcoded in Dutch inside the script. An English page built from the
template rendered English decisions under a Dutch counter, and nothing failed to
warn about it.

## Traps that cost a rebuild

- **An unescaped quote in `data-titel` truncates the attribute** and the summary
  row silently goes blank. Escape the attribute, then check the summary table
  has as many filled rows as there are decisions.
- **A styling rule on a bare element inside a block hits every instance.** A
  `.let b { display:block; text-transform:uppercase }` meant for the label also
  caught a `<b>` used for emphasis mid-sentence and threw a heading into the
  middle of a paragraph. Scope to the direct child.
- **The stored shape will change.** Going from `{id: 'o1'}` to
  `{id: {keus, notitie}}` drops every earlier answer unless the reader accepts
  both. Read the old shape; do not migrate silently and do not lose the owner's
  work.
- **A theme defined only inside a media query** leaves the page painting one
  theme's text on the other's ground the moment someone toggles. Light on bare
  `:root`, dark twice: behind the preference and behind the stamp.

## Extending a page later

When the owner asks for more (another decision, the tenant-configurable
candidates, a "now in the app" measurement, a recipe screenshot instead of a
hand-drawn mock), add a numbered section in the same file and commit; keep the
`data-decision` titles stable so stored choices survive, or accept that they
reset and say so.

Prefer a real recipe screenshot from Storybook over a hand-drawn mock as soon
as the recipe exists: the mock is for the decision, the recipe is the truth.

## Files

- `template-register.html` + `register.js`: the register page (many small
  decisions): provenance markers, grouped blocks, multi-line notes, three-state
  theme switch, counter and copy-out. Replace the placeholders in caps.
- `template.html`: the page skeleton: styles for option cards, mock idiom,
  comparison table, choice blocks, sticky toolbar, and the script for
  persistence and markdown export. Copy it, replace the placeholder section,
  translate the UI strings to the owner's language.
- `check.mjs`: headless render check: radios per decision, horizontal
  scroll, clipped text, screenshot. Needs Playwright resolvable from the
  current directory or `PLAYWRIGHT_DIR`.

## Related

- Walkthrough findings feed this page; the page's answers feed the spec.
- For explaining a concept rather than deciding one, use `brain-explain`.
- For a deep, evidence-checked treatment of one option, use `deep-dive`.
