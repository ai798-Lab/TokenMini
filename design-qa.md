# TokenMini website visual acceptance

Source visual truth: `docs/private/brand-qa/selected-reference.png` (user-selected website reference, kept local).
Implementation: `docs/assets/github/website-home.png`.
Focused evidence: `docs/private/brand-qa/hero-comparison.png`.
Mobile evidence: `docs/private/brand-qa/tokenmini-mobile-final.png`.

Viewport and state: home, 1499 × 1049 CSS px at devicePixelRatio 1. The source is 1499 × 1049 pixels; the browser capture is 1484 × 1039 pixels (browser capture excludes edge gutters). The comparison uses the same interior crop at x=45, y=210, width=1405, height=500 from both images, without scaling. An earlier screenshot clip disturbed capture dimensions and was discarded. Desktop screenshot shows the paused hero for reproducibility. The mobile layout was checked at 390 × 844 CSS px. The reference has no mobile layout; its desktop hierarchy informed the responsive version.

## Comparison history

1. P1: the first implementation confined the visual to the dark hero rectangle. It missed the selected composition's foreground overlap. Replaced it with a true transparent PNG on a separate foreground layer. Its stage now begins 110 px above the dark section; the mechanical top visibly overlaps the masthead letters. The background photograph remains a subtle depth layer.
2. P2: initial large-type tracking was too tight, and the masthead left unused space. Increased display size and relaxed tracking from -0.092em to -0.055em. The final masthead fills its column without clipping.
3. P2: the first mobile crop hid the last mechanical slice. Reduced the mobile artwork to 450 px and moved it right by 8 px, preserving all four slices in the visible composition while keeping the download action readable.
4. Scope correction: removed the Token supply teaser after the user confirmed monitoring-only positioning. There are no purchase, top-up or pre-sale controls.

## Final comparison

The source and final browser capture were opened together in one comparison input, followed by exact-pixel crops of both hero regions combined vertically. The key layout is retained: compact navigation, oversized black masthead, overlapping metal foreground, dark hero with large left-aligned Chinese text, download action, compatibility/privacy strip, menu bar example and three functional columns.

- Typography: Geist heavy uppercase display; readable Chinese system fallback. Custom outlined TokenMini wordmark remains a separate approved brand asset. The longer new name intentionally changes the letterforms and tracking.
- Spacing: desktop margins and major section proportions follow the reference. Hero is 390 px tall; actual section top is about 323 px at the reference viewport. Content continues naturally below the fold.
- Color: warm light background and graphite hero retained. Approved TokenMini green replaces the original red accent. Focus indicators remain visible.
- Imagery: high-resolution transparent mechanical art, no painted rectangle or checkerboard. Four progressively smaller modules and the second green layer echo the selected logo. It intentionally replaces the reference's circular lens with the approved brand geometry.
- Copy: focused on free Claude Code / Codex monitoring, quota awareness and Mac status. Example menu bar values are explicitly illustrative. API-equivalent estimates are distinguished from actual subscription charges. No token-sales claims.
- Interaction: home → rankings; metric switch changes the table to API-equivalent cost; return home → privacy → return home. No account sign-in or real-user data was submitted.
- Motion: rendered transform matrices change while running; Pause changes the computed play state to paused. Reduced-motion and mouse-only parallax are implemented; the OS preference and pointer interaction were not separately exercised in this check. No continuous scroll listener or video autoplay is used.
- Responsive: desktop and 390 px mobile show no horizontal overflow. Download, footer navigation and privacy text remain accessible.
- Console: no page errors observed in the final browser check. An earlier dev-server HEAD-probe error was transient and did not occur on the actual navigation flow.

No actionable P0/P1/P2 visual findings remain for the website. Exact source artwork is intentionally adapted to TokenMini; no claim of identical pixels is made. Native app visual acceptance and Sparkle upgrade acceptance are separate from this website report.

final result: passed
