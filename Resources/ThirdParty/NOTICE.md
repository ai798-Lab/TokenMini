# Open-source attribution

TokenMini adapts selected metering algorithms into its native Swift pipeline.

- ccusage — https://github.com/ccusage/ccusage — MIT, Copyright (c) 2025 ryoppippi.
  Revision: 31dd24e (2026-09-22). `rust/adapters/kimi/src/parser.rs`, `paths.rs`, `loader.rs`.
  Adapted: legacy/new wire records, turn-only metering, session/message/time/token deduplication.
  Differences: missing historical model/time stays unknown/skipped; no current-config model inference;
  read-only native Swift scanner; no external process, upload, hooks or third-party account.
- TokenTracker — https://github.com/xiufengsun/TokenTracker — MIT, Copyright (c) 2026 xiufengsun.
  Revision: a726cd540607516a05b2f705e33a57751e845fb6.
  `src/lib/cursor-config.js`: header-based CSV mapping; cache-write = inclusive input minus uncached input.
  `src/lib/trae-cn-config.js`, `test/trae-cn-parser.test.js`: opt-in official Trae Work CN usage API,
  credential format, pagination validation and cache-inclusive input normalization.

Full license texts accompany this notice. TokenMini modifications are maintained separately.
The upstream applications themselves are not bundled, launched, rebranded or uploaded.

- models.dev — https://github.com/anomalyco/models.dev — MIT, Copyright (c) 2025 models.dev.
  Offline pricing data derived from ccusage revision 31dd24e's models-dev-pricing.json.
  2,595 flat-price entries retained; 254 context/tier entries excluded rather than mispriced.
  Exact raw ID matching only, after TokenMini's custom and official prices. Cache rate absent:
  use standard input rate. Snapshot fetched 2026-09-22; community reference, not historical billing.
