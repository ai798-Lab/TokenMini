# Production website publication — 2026-09-21

The user explicitly approved the static local website and requested production publication. The existing Sites project now serves that approved version at https://tokenmini.cc/. The deployment reported success. No native application release was made in this publication.

- Published only the five website implementation files and the canonical PNG/WebP images; backend, authentication, schema and appcast remain byte-identical to the previous deployed source.
- The exact publication build passed all 17 existing tests and lint.
- Actual production-browser verification showed the new circular mechanical artwork loaded, the preserved foreground overlap, zero sequence canvases, and no mechanical CSS animation.
- Public ranking page, metric selection, privacy page and return-home navigation work. The existing download link opens the TokenMini 0.11.0 public release page.
- Private deployment trace: `docs/private/brand-qa/static-prism/production-release.json`.

# Static artwork follow-up — 2026-09-21

The user requested that the mechanical artwork stop moving, and that the Prism skin reuse the website artwork. This supersedes animation acceptance below.

- Removed the canvas sequence player and frame preloading. The Hero now renders the canonical static poster.
- Removed the second mechanical section’s continuous rotation. Surrounding text-strip and section-entry motion remain.
- In the separate Prism checkout, replaced both `Resources/Prism/PrismCore.png` and `website/public/brand/prism-core.png` with the exact canonical `frame-00.png`. Removed Hero/statement drift and scroll-driven movement of those images. Corrected image dimensions in social metadata.
- Main website and Prism website both pass their existing 17 tests, builds and lint checks.
- Browser check confirms zero sequence canvases, `data-visual=static`, and no CSS animation on either mechanical image. Prism also reports fixed image transforms.
- Native replacement is prepared with the same Developer ID and verified signatures; installation awaits a confirmed exit of the running app because native UI controls returned stale-menu errors. Do not claim installation or native visual acceptance until the follow-up record is updated.

# TokenMini kinetic website — visual QA, 2026-09-21

This report supersedes the previous four-plate Hero acceptance. That earlier direction was rejected by the user. Current scope: a circular exploded-engine Hero and a more assertive visual system across the public website; monitoring only, with tokenmini.cc remaining the official domain.

## Reference and evidence

- Selected source: `docs/private/brand-qa/selected-reference.png`, 1499 × 1049.
- Implemented home: `docs/private/brand-qa/kinetic-v2/desktop-hero.png`.
- Mobile home: `docs/private/brand-qa/kinetic-v2/mobile-hero.png`.
- Sequence validation: `docs/private/brand-qa/kinetic-v2/sequence-check.json`.
- Four source frames and prompts: `docs/assets/hero-motion-v2/`.

The source and browser capture were opened together in the same comparison input, and inspected again after increasing the foreground overlap. Desktop viewport was 1499 × 1049 CSS px, DPR 1. Explicit document-coordinate screenshots were used; the browser's generic screenshot method scales the native window and is unsuitable for a pixel-sized comparison. The reference has no phone layout; the responsive design was separately inspected at 390 × 844 CSS px. The in-app browser also rendered the intermediate 931 px-wide layout.

## Findings fixed

1. P1 — Wrong visual language: replaced the previous planar plate assembly with a generated circular optical-engine assembly, dense black vanes, chrome lens rings, exploded depth and a green beam.
2. P1 — Foreground composition: the transparent foreground crosses the dark/light boundary and overlaps the large masthead letters. The downloaded/generated artwork has a real alpha channel.
3. P1 — Animation compositing haze: FFmpeg converted alpha to limited-range luma (16–235), producing a gray rectangle on the white masthead. Explicitly restored 0–255 before compositing; checked all 64 WebP files for full alpha range and inspected the rendered white region.
4. P2 — Whole-page visual strength: added large heavy headings, black/paper/fluorescent-green section changes, a continuously moving text strip, an oversized second mechanical crop, scroll entrances and a full green download panel. Rankings and privacy use the same color system and larger headings.
5. P2 — Phone download title: the arrow's grid column forced the final character onto a third line. The title now spans the width, its size scales with the viewport, and the arrow occupies the first line's open corner. Rechecked visually.
6. P2 — Intermediate 931 px panel: moved the mechanical layer right to keep floating parts out of the description. Desktop and mobile rules are independent.
7. P2 — Large artwork on white: strengthened the pale outline behind the overlapping black title in the second mechanical section. Removed the decorative masthead caption on the right where the foreground crossed it.

## Actual-browser checks

- Home renders and the canvas reaches `data-sequence=ready`; desktop canvas is 1152 × 648 and phone canvas is 640 × 360.
- Frame indices advance during playback. Clicking Pause sets the entire page to paused; the canvas held frame 5 across subsequent calls while the marquee and second mechanical visual both reported paused. Playback works after returning to the home page.
- After scrolling well beyond the Hero on mobile, its canvas held frame 24 across subsequent calls, confirming offscreen suspension.
- The floating circular assembly, moving text band, entry transitions, lower mechanical section and green download panel were inspected in the real browser. No major clipping or blocked primary actions was observed.
- Desktop and phone document widths stay within their viewport widths. Phone Hero, feature rows, menu-bar illustration, secondary mechanical section, privacy and download steps were visually inspected.
- Home → rankings → API-equivalent-cost metric works; explanatory estimate notice appears and table heading changes. Home → privacy → home works. Back-to-top reaches scrollY 0.
- A clean final home load produced no captured error/warning console entries.
- Existing build and 17 website tests pass; ESLint and git diff whitespace checks pass.

## Scope and limits

This is local visual/interaction acceptance, not user approval of the new art direction or a production deployment. The production domain is unchanged; this iteration is available at the local preview. No account login or public ranking data was modified.

The sequence uses four generated keyframes, 28 distinct interpolated images plus a short held pose, played as a 32-frame ping-pong cycle at 18 fps. Fine mechanical details vary slightly across generated frames; this is an image sequence, with no claim of rigid 3D geometry or exact mechanical rotation angles. Slow-network playback and hardware-level performance on real phones were not measured. Reduced-motion and document-visibility handling are implemented and source-reviewed; an OS preference toggle and hidden-tab stop were not separately exercised in this run. The static poster covers initial loading, reduced motion, no JavaScript and frame-load failure.

No remaining P0/P1/P2 visual findings were identified in the tested scope. Brand/design approval remains the user's judgment.

final result: passed
