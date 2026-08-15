---
name: component-motion
description: >-
  Add scroll-driven, staggered, magnetic, and physics motion to web UIs — GSAP
  ScrollTrigger, smooth scroll (Lenis/Locomotive), scroll-reveal (AOS), anime.js,
  Motion (Framer), Lottie, Rive. Use whenever the user wants to animate a page or
  component, add scroll animations / parallax / pinning / reveals / a magnetic or
  hover effect, "make it feel alive", bring award-site (Awwwards) motion, or asks
  which animation library to use — even if they don't name one. Animates web
  components through their clean seams (host, CSS-variable tokens, ::part) and
  keeps prefers-reduced-motion. Standalone; pairs with technique-transplant.
---

<!-- PROVENANCE: the per-library recipes in references/ are vendored + sanitized
     2026-07-27 from freshtechbro/claudedesignskills (audited: recipe markdown, no
     scripts carried over). The orchestrator, the seams contract, and the a11y
     guardrails below are agentBrain-authored. Owned + maintained here, not a live
     dependency on the upstream repo. -->

# component-motion

Motion is a **layer over** structure, not a rewrite of it. Your components are
the content; a motion library (GSAP, Lenis, anime.js, …) choreographs them.
The two don't fight — if you animate through the right seams.

## Animate through the seams (not the shadow internals)

Web components (custom elements) hide their guts behind a shadow-DOM boundary.
Animate them **through the clean seams**, never by reaching inside:

| Seam | Use it for |
|---|---|
| **host** — `transform` / `opacity` / `filter` / `clip-path` on the element | position, float, parallax, reveal, magnetic — always works |
| **CSS custom properties / design tokens** (`--vnr-*`, `--brand-*`) | colour, radius, spacing the component reads. A motion lib can **tween a CSS variable**, animating the component's *look* through the shadow boundary without touching its DOM. The cleanest animation interface a component DS gives you. |
| **`::part(...)`** | animate a part the component deliberately exposes |

This is the same seams contract as [[technique-transplant]] — read that when the
motion is being *borrowed from a reference site*.

## First decide the motion, then the library

Before matching a job to a library, decide **what the motion should feel like** —
emotional intent, personality, timing, easing, choreography. That layer is
library-agnostic and lives in `references/motion-design/` (the "director" layer):

| You need… | Read |
|---|---|
| Emotional target, personality archetype, the 8-step checklist | `references/motion-design/README.md` |
| Disney's 12 principles UI-adapted, choreography, emotion→motion mapping | `references/motion-design/director/` |
| Duration/easing lookup tables, property-selection, quality checklist | `references/motion-design/reference/` |
| Entrance/exit, state-feedback, ambient, multi-element stagger recipes | `references/motion-design/patterns/` |

Read `references/motion-design/README.md` first for any non-trivial motion work;
it tells you *how it should feel* independent of the tool you implement it with.

## Pick the library, then read its recipe

Once the motion intent is clear, match the job to a library and read the deep
recipe in `references/`:

| The user wants… | Library | Read |
|---|---|---|
| Scroll-scrub, pinning, timelines, the Awwwards standard | GSAP + ScrollTrigger | `references/gsap-scrolltrigger.md` |
| Simple "fade/slide in on scroll", minimal setup | AOS / scroll-reveal | `references/scroll-reveal.md` |
| Buttery smooth scrolling / scroll-linked feel | Lenis / Locomotive | `references/smooth-scroll.md` |
| Component animation in a React app, gestures, layout | Motion (Framer) | `references/motion-for-react.md` |
| Lightweight DOM/SVG/CSS tweening, no big dep | anime.js | `references/animejs.md` |
| Play a designed After-Effects animation | Lottie | `references/lottie.md` |
| Interactive, state-machine vector animation | Rive | `references/rive.md` |

Default to **GSAP + ScrollTrigger** when unsure — it's the most capable and the
one award sites reach for.

## Accessibility is not optional (motion honesty)

Award motion that ignores accessibility is a downgrade. Every recipe here runs
under these rules:

- **`prefers-reduced-motion: reduce` must disable the choreography** — gate every
  entrance/scroll effect behind it, or provide a static end-state. This is a
  legal/UX requirement, not a nicety.
- **Never animate layout properties** (width/height/top/left) — animate
  `transform` / `opacity`; layout animation janks and reflows.
- **Ease out** with exponential curves (quart/quint/expo); no bounce/elastic on
  UI. Durations 150–300ms for micro-interactions.
- **Don't let motion move focus or hide content from AT.** Decorative motion
  layers get `aria-hidden`; never trap or reorder tab order.
- Prove it if it matters: run axe / [[uxray]] on the animated page — motion must
  not introduce contrast or focus regressions.

## Output

Working motion on the user's real components, through the seams, degrading
cleanly under reduced-motion. Name which library and technique you used, and why
that one fit the job.
