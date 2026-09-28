---
date: 2026-07-28
type: reference
tags: [skill, motion, references, vendored]
id: bd4e772e-e8aa-5ad3-8dea-991c572967e2
---

# component-motion — references

Motion knowledge used by the [[component-motion]] skill, loaded on demand by the orchestrator in `../SKILL.md`. Two layers:

**Director layer (library-agnostic — decide the motion first):**

- `motion-design/` — emotional intent, motion personality, Disney principles UI-adapted, timing/easing lookup tables, choreography, and pattern recipes. Start at `motion-design/README.md`.

**Per-library recipes (implement the motion):** each doc carries its own `name`/`description` header.

- `animejs` — anime.js timelines, stagger, SVG morphing
- `gsap-scrolltrigger` — GSAP ScrollTrigger pinning, scrub, parallax
- `lottie` — Lottie/Bodymovin JSON animations
- `motion-for-react` — Motion (Framer Motion) for React
- `rive` — Rive interactive state-machine animations
- `scroll-reveal` — lightweight scroll-reveal (AOS-style)
- `smooth-scroll` — Lenis / Locomotive smooth scrolling

**Provenance:**
- Per-library recipes: vendored + sanitized (2026-07-27) from `freshtechbro/claudedesignskills`.
- `motion-design/` director layer: vendored (2026-08-04) from `lottiefiles/motion-design-skill` (MIT, © LottieFiles).

Both are recipe markdown only — no scripts, eval, network, or install-hooks carried over. Owned and maintained here, not live upstream dependencies.
