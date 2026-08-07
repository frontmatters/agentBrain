---
name: technique-transplant
description: >-
  Harvest a reference website's design + motion TECHNIQUE (composition, section
  rhythm, hero, card/mockup anatomy, scroll choreography) and re-apply it onto
  the user's OWN components — without cloning the site's content. Use this
  whenever the user wants to "make it look/feel like <site>", borrow a
  competitor's or award-site (Awwwards, Revolut, Stripe, Linear, GSAP-heavy)
  layout or motion, "apply that technique to our components", redesign in the
  style of X, or transplant a top site's UX pattern — even if they don't say
  "harvest" or "technique". Standalone: works with zero other skills; opportunistically
  uses harvest / sitescope / uxray / frontend-design when they are installed.
related: [hallmark, uxray]
---

# technique-transplant

> Related: **hallmark**'s `study <screenshot|URL>` verb (`local/skills/hallmark/`)
> does an adjacent job — DNA extraction (macrostructure, type-pairing, colour
> anchor) rather than technique/motion harvesting — and can emit a portable
> `design.md`. Prefer technique-transplant when the goal is composition/motion
> grammar; prefer hallmark's study verb for a fast palette-and-type diagnosis.

Take the **technique** of a great website — how it composes space, scales type,
choreographs motion, builds its hero and product mockups — and apply it to the
user's **own component set** and **own brand**. The reference is a teacher, not
a template. You are stealing the *grammar*, never the *sentences*.

This is standalone: every step below has an inline fallback, so it runs on a
bare project. Where the richer skills exist, prefer them (see *Enhancement*).

## The one rule that governs everything

**Transplant the technique, not the skin.** A top site's transferable value is
its *composition and motion* — those are brand-agnostic and portable. Its
*palette / skin is brand-specific* and usually **fights** the target: a dark
cinematic skin dropped onto a light, accessible brand breaks that brand's own
text tokens (real failure this session: light-theme components on a dark
section → body text at 1.32:1). Keep the target's brand and accessibility;
borrow only the arrangement and behaviour.

## Step 1 — Capture the reference

Goal: enough of the *rendered* page to read its technique. You need pixels
(what it looks like) and structure (how it's built).

- **Use a real browser**, not `curl`. Production marketing sites sit behind bot
  checks (Cloudflare "just a quick security check") that block `curl`/HTTP
  fetchers but pass a real headless browser. Drive Playwright/CDP.
- Capture: **full-page screenshot** + a **couple of section-level screenshots**
  (scroll to trigger lazy/scroll-animated bands — full-page shots often render
  them black). Then read a few **computed styles** (section backgrounds, radii,
  the hero/nav) and the **DOM outline** (how sections nest).
- Scroll-animated hero/feature bands are frequently `<canvas>`/video and won't
  screenshot statically — that's fine, you're after the *pattern*, not a frame.

> **Enhancement:** if the `harvest` or `sitescope` skill is installed, use it
> for capture instead — it gives rate-safe, structured page shells. This skill
> only reimplements the minimum inline.

## Step 2 — Deconstruct into a recipe (not content)

Write down the **technique as a recipe**. Name the mechanisms; ignore the words
and pictures. Cover:

- **Layout & rhythm** — grid columns, alternating full-bleed sections, negative
  space, where things break the grid.
- **Type** — the scale (how many sizes, the ratio between steps ≥1.25), display
  vs body pairing, weight contrast.
- **Colour strategy** — restrained (tinted neutrals + one accent), committed
  (one saturated colour 30–60%), full-palette, or drenched. Note it, don't copy
  the hues.
- **Signature moves** — floating 3D product/card mockups with depth, phone
  frames, segmented pill toggles, social-proof strips, plan-card grids, big
  metrics.
- **Motion** — scroll-scrub, pin, stagger/clip reveal, magnetic, parallax; note
  triggers and easing, not durations to the millisecond.

The recipe is the deliverable of this step. If you can't state the technique in
a short list, you haven't deconstructed it yet.

## Step 3 — Transplant onto the components, via the seams

Rebuild the recipe using the user's **own components** and **own brand tokens**.
Web components (custom elements) have a shadow-DOM boundary — animate and style
them **through the clean seams**, never by reaching into shadow internals:

| Seam | Use it for |
|---|---|
| **host** — `transform` / `opacity` / `filter` on the element | position, float, parallax, reveal — always works |
| **CSS custom properties / design tokens** (`--vnr-*`, `--brand-*`) | colour, radius, spacing that the component reads. GSAP can *tween a CSS variable*, so this animates the component's look **through the shadow boundary** without touching its guts. The cleanest animation interface a component DS gives you. |
| **`::part(...)`** | style a part the component deliberately exposes |

Keep the target's brand: its accent, fonts, radii, its light/dark scheme. You
are dressing the user's components in the reference's *choreography*, not the
reference's colours.

> **Enhancement:** if `frontend-design` is installed, use it for the actual
> visual-craft pass so the result avoids generic AI aesthetics.

## Step 4 — Verify with evidence (this is not optional)

Award motion that fails accessibility is a downgrade, especially on an
a11y-conscious brand. Prove it; don't eyeball it.

- **Run axe** on the built page and read the violations. Inline snippet
  (`axe-core` + a browser): load the page, inject axe, `axe.run`, list
  `color-contrast` etc. "It looks good" is not a finding.
- **Contrast guardrails learned the hard way:**
  - If the brand is light/high-contrast, **stay light** — don't go dark
    cinematic. A dark skin re-breaks the brand's light text tokens.
  - **Measure the accent colour as *text* separately.** A punchy accent
    (`#ff6200`) is fine as a *fill* (large/bold white on it clears AA-large at
    3:1) but fails as small text. Keep a **darker text-variant** of the accent
    for small text; reserve the bright one for fills/large.
  - Stronger CTAs are often a **CRO and an a11y win at once** — a timid "link"
    CTA is both a conversion leak and a contrast fail; filling it fixes both.
- **Fonts: set display faces explicitly and verify.** Don't trust a
  `var(--font-heading)` token to cross the shadow/scope boundary — it may be
  unset in the render context, and your heading silently falls back to the body
  font (real failure this session). Set `font-family: 'Display Face', …`
  explicitly and confirm with `getComputedStyle(el).fontFamily` +
  `document.fonts.check("700 40px 'Display Face'")`.
- **Motion honesty:** `prefers-reduced-motion` must disable the choreography;
  never animate layout properties (animate `transform`/`opacity`); ease-out.

> **Enhancement:** if `uxray` is installed, run it in `polish` mode for the full
> 12-axis audit + fix-loop instead of the inline axe check.

## Earned rules (each cost a real mistake)

- Dark cinematic skin ≠ portable. The composition is; the darkness isn't.
- Full-page screenshots of scroll-animated sites render bands black — scroll
  and shoot sections to see them.
- The heading token didn't reach shadow-scoped content → explicit display font.
- Accent-as-small-text failed AA at ~3.2:1 → separate darker text-accent.
- The residual contrast hits were inside the *brand's own components* (their
  white-on-orange button), not the transplant — report that boundary honestly
  rather than "fixing" someone else's component silently.

## Output

A working page/section built from the user's components + brand, carrying the
reference's technique, with an axe pass proving AA. Say plainly which technique
was borrowed, and flag any residual a11y issues that live in the brand's
components (outside your layout) rather than hiding them.
