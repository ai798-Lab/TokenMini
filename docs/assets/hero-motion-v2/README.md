> Current status (2026-09-21): the user rejected the animation. The live page component now renders only `poster.webp`; no frame sequence is decoded or played. The four source frames and old interpolation script remain as archived design assets. The lower mechanical image is also static.

# TokenMini kinetic hero

Four generated, transparent RGBA keyframes are kept in `keyframes/`; the generation prompts are in `prompts.md`. The selected reference is the original circular, exploded optical-engine concept, with a green beam for TokenMini. These are image-based animation assets; fine mechanical details are not rigid 3D geometry.

The website plays 32 WebP frames at 18 fps, forwards then backwards (about 3.44 seconds per cycle). There are 28 distinct frames and a short held end pose. Optical-flow interpolation is applied to color; alpha is blended independently and restored to full range to avoid a rectangular haze over the white masthead.

- Desktop: 1152 × 648, 4,690,586 bytes for the sequence.
- Mobile: 640 × 360, 2,024,072 bytes for the sequence.
- Static fallback: transparent WebP poster, about 312 KB. Visible before decoding, with JavaScript disabled, on image-load failure, and for reduced-motion preferences.
- A shared pause button stops the frame sequence, marquee and lower mechanical visual. The canvas stops while offscreen or while the tab is hidden.

To rebuild with the repository's Node dependencies and FFmpeg installed:

```sh
cd website
node scripts/build-hero-sequence.mjs
```

Generated browser assets are in `website/public/brand/motion-v2/`. Original reference screenshots and browser QA evidence stay in ignored `docs/private/brand-qa/kinetic-v2/`.
