# Model catalog and passive app updates

The signed model catalog is distributed with the 0.13.0 release. Publish the verified envelope together with the website; keep signing keys private.

## Model data

The client fetches `https://tokenmini.cc/models/catalog.json` at startup and every six hours. Temporary failures retry with backoff. It verifies an Ed25519 signature with the bundled public key before atomically replacing the cached catalog. Offline clients retain the last verified copy or built-in prices. Model requests contain no session records, projects, credentials or token usage.

Precedence is: an event's reported actual cost; user-defined model prices; signed remote prices valid at the event time; bundled official prices; exact community references. Unknown models stay unpriced. One scan uses one immutable pricing snapshot. A catalog change triggers a new scan automatically, including when a scan is already running. Rankings carry the applied catalog revision.

The first client with this capability needs an app upgrade. Thereafter model IDs, explicit aliases, supported rate fields and effective date intervals can update through this file without another installation. New authentication methods, parsers or unsupported pricing formulas still need application code.

`Config/ModelCatalog.json` is the readable source. Each model has:

- Exact normalized ID and aliases; no prefix or approximate price matching.
- `validFrom` (inclusive) and optional `validUntil` (exclusive), in UTC ISO 8601.
- Official source URL, rates per million tokens, supported thresholds and fast-mode multiplier.

On a price change, retain the old entry, close its interval, and append a new entry. Retain all other model entries in the full snapshot. Intervals for the same model/alias must not overlap. Increment the catalog revision for every change; do not modify the payload of an existing revision.

Sign locally with `python3 scripts/model_catalog.py Config/ModelCatalog.json` (Python package `cryptography` required). This writes the envelope under `site/models/`; it does not upload it. The private key lives in ignored `.local-secrets/model-catalog.key` with owner-only permissions. Back it up securely before deleting the worktree. Do not commit, print or distribute it. A replacement private key will not match existing clients; the script deliberately refuses silent key rotation.

The candidate includes standard API pricing verified on 2026-09-23 for GPT-6 Sol, GPT-6 Luna and Claude Opus 5.5. Sources are recorded in the readable catalog. The public endpoint must serve the exact signed envelope from site/models/catalog.json. Verify signature, revision and automatic client adoption after deployment.

## Application updates

Sparkle's own scheduled presentation and automatic installation are disabled. The application schedules information-only checks. Finding an update only changes the observable state consumed inside the existing menu-bar popover; it does not create a window, activate the app or send an OS notification. All four themes include the entry. The user opens the icon, expands “查看更新”, reads the release's notes, and chooses “下载更新” or “跳过此版本”. Only an explicit update button hands off to Sparkle's native installation window.

Skipping persists the exact build number; a later build is eligible again. A deliberate “检查更新…” remains available in settings. The appcast must be generated and signed through the existing release scripts; never hand-edit it or point it at an unpublished package.

## Integration and verification

The changes in `PrismTheme.swift` only add `UpdateNoticeView` to the scroll content. Preserve the branding owner's header edits. `scripts/build.sh` only adds three Sparkle policy keys; preserve branding/resource edits. `DashboardRoot.swift` changes the filter bar and hero scope, not the trend chart. The trend/date-axis work is owned by the other task.

Automated tests cover signed catalog A → timer → B → published UsageStore dashboard, restart/offline fallback, signature and rollback rejection, effective price intervals, alias overrides, snapshot isolation, filter facets, and delayed aggregation invalidation. These tests use synthetic records. They are not proof of acceptance through the installed menu-bar UI. The integrating task owns final local installation and visual/interaction acceptance; no other task should overwrite `/Applications/TokenMini.app` concurrently.
