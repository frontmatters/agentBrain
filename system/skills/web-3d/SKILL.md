---
name: web-3d
description: >-
  Build 3D / WebGL / WebGPU / WebXR experiences on the web — Three.js, React
  Three Fiber, Babylon.js, PlayCanvas, PixiJS (2D-GPU), Spline (no-code), A-Frame
  (VR/AR), plus lightweight decorative 3D. Use whenever the user wants a 3D scene,
  a product viewer/configurator, particles, a WebGL background, an immersive or
  VR/AR experience, "add depth / a 3D element", or asks which 3D engine to pick.
  Heavy, opt-in: prefer lightweight effects for decoration and always ship a
  non-3D fallback. Pairs with component-motion and technique-transplant.
---

<!-- PROVENANCE: the per-engine recipes in references/ are vendored + sanitized
     2026-07-27 from freshtechbro/claudedesignskills (recipe markdown only; the
     sources' scaffolding scripts were NOT carried over). Orchestrator, selection
     guidance and the performance/a11y guardrails are agentBrain-authored. Owned +
     maintained here, no upstream dependency. -->

# web-3d

3D on the web is powerful and **expensive** — in bytes, GPU, battery, and
accessibility. Reach for it deliberately. Most landing pages want a *hint* of
depth (see `lightweight-effects`), not a full engine. Full engines earn their
weight for product viewers/configurators, games, data-viz, and immersive scenes.

## Decide first: do you even need an engine?

| Need | Reach for |
|---|---|
| Subtle depth, a floating shape, a decorative WebGL background | `references/lightweight-effects.md` (Vanta/Zdog/CSS-3D) — no heavy engine |
| A designed 3D scene, fast, no-code, easy embed | `references/spline-nocode.md` |
| General-purpose 3D scene / product viewer (vanilla) | `references/three-js.md` |
| The same, inside a React app (declarative) | `references/react-three-fiber.md` |
| Rich scenes / games / physics, batteries-included | `references/babylon-js.md` |
| Game engine with editor, WebGL/WebGPU | `references/playcanvas.md` |
| High-performance **2D** GPU rendering (particles, sprites) | `references/pixi-2d.md` |
| VR / AR / WebXR | `references/aframe-webxr.md` |
| Combining a 3D scene with scroll choreography | `references/integration-patterns.md` (+ [[component-motion]]) |

When unsure and it's not React: **Three.js**. In React: **React Three Fiber**.
For decoration only: **don't use an engine at all** — lightweight effects.

## Performance guardrails (3D breaks pages if you don't)

- **Lazy-load the engine** — never in the critical path. Load on interaction or
  when the canvas scrolls near the viewport; a WebGL engine is 100s of KB.
- **Cap it for the device** — detect low-power/mobile and drop to a static image
  or a lighter effect. Don't ship a full scene to a phone that will thermal-throttle.
- **Respect `prefers-reduced-motion`** — pause/disable auto-rotation, drift, and
  scroll-driven camera moves; offer a still frame.
- **Budget draw calls / poly count**; dispose geometries, materials, textures on
  teardown (WebGL leaks are real). Pause the render loop when off-screen or the
  tab is hidden.

## Accessibility guardrails (3D is often invisible to AT)

- The `<canvas>` is opaque to screen readers. **Never put essential information or
  the only copy of an action inside the 3D scene.** Mirror it in real DOM.
- Mark a purely decorative canvas `aria-hidden="true"`; give a meaningful one a
  text alternative and a non-3D fallback (image/video/DOM).
- Keyboard: any interactive 3D control needs a DOM equivalent. Don't trap focus
  in the canvas.
- Prove it: run axe / [[uxray]] — a 3D hero must not become a content or focus
  black hole.

## Output

The right tool for the actual need (often *not* a full engine), lazy-loaded,
device-capped, reduced-motion-safe, with a real-DOM fallback for anything that
matters. Say which engine you chose and why it beat the lighter options.
