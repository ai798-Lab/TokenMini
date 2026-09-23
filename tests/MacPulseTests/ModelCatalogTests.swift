import XCTest
import CryptoKit
@testable import MacPulse

final class ModelCatalogTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private func fixture(_ revision: Int, input: Double = 2) -> ModelCatalog {
        ModelCatalog(schema: 1, revision: revision, publishedAt: epoch, models: [
            .init(id: "test-new-model", aliases: ["test-alias"], validFrom: epoch, source: URL(string: "https://example.com/pricing")!,
                  pricing: ModelPricing(inputPerMTok: input, outputPerMTok: 10, cacheWritePerMTok: 2.5, cacheReadPerMTok: 0.2), fastMultiplier: 2)
        ])
    }
    private func sign(_ catalog: ModelCatalog) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        return try encoder.encode(ModelCatalog.Envelope(payload: data, signature: key.signature(for: data)))
    }
    func testSignatureRollbackAndInvalidRatesAreRejected() throws {
        let valid = try sign(fixture(2))
        let publicKey = key.publicKey.rawRepresentation
        XCTAssertEqual(try ModelCatalog.decode(valid, publicKey: publicKey, minimumRevision: 1).revision, 2)
        XCTAssertThrowsError(try ModelCatalog.decode(valid, publicKey: publicKey, minimumRevision: 3))
        XCTAssertThrowsError(try ModelCatalog.decode(valid, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation, minimumRevision: 0))
        XCTAssertThrowsError(try ModelCatalog.decode(sign(fixture(3, input: -1)), publicKey: publicKey, minimumRevision: 0))
        var duplicate = fixture(3); duplicate.models.append(duplicate.models[0])
        XCTAssertThrowsError(try ModelCatalog.decode(sign(duplicate), publicKey: publicKey, minimumRevision: 0))
        var future = fixture(3); future.publishedAt = Date().addingTimeInterval(3600)
        XCTAssertThrowsError(try ModelCatalog.decode(sign(future), publicKey: publicKey, minimumRevision: 0))
        XCTAssertThrowsError(try ModelCatalog.decode(Data(repeating: 0, count: 2_000_001), publicKey: publicKey, minimumRevision: 0))
    }
    func testSnapshotPrecedenceEffectiveDatesAndUnknownModels() {
        let catalog = fixture(1)
        let original = PricingSnapshot(catalog: catalog, overrides: [:])
        let newer = PricingSnapshot(catalog: fixture(2, input: 4), overrides: [:])
        XCTAssertEqual(original.pricing(for: "test-alias", at: epoch)?.inputPerMTok, 2)
        XCTAssertEqual(newer.pricing(for: "test-alias", at: epoch)?.inputPerMTok, 4)
        XCTAssertEqual(original.pricing(for: "test-alias", at: epoch)?.inputPerMTok, 2, "Old scan must retain its own prices")
        XCTAssertNil(original.pricing(for: "test-alias", at: epoch.addingTimeInterval(-1)))
        XCTAssertNil(original.pricing(for: "test-new-model-unknown", at: epoch))
        let override = ModelPricing(inputPerMTok: 9, outputPerMTok: 9, cacheWritePerMTok: 9, cacheReadPerMTok: 9)
        XCTAssertEqual(PricingSnapshot(catalog: catalog, overrides: ["test-new-model": override]).pricing(for: "test-new-model", at: epoch)?.inputPerMTok, 9)
    }
    @MainActor
    func testAutomaticTimerAppliesNewCatalogRepricesAndSurvivesOfflineRestart() async throws {
        let first = try sign(fixture(1)), second = try sign(fixture(2, input: 4))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("catalog.json")
        var requests = 0
        let store = ModelCatalogStore(publicKey: key.publicKey.rawRepresentation, cache: cache,
            refreshInterval: 0.01, pollInterval: 0.02, fetch: { _ in requests += 1; return requests == 1 ? first : second })
        defer { store.stop() }
        let applied = expectation(description: "A and B arrive automatically without manual refresh")
        applied.expectedFulfillmentCount = 2
        var prices: [Double] = []
        store.onChange = {
            let snapshot = PricingSnapshot(catalog: store.catalog, overrides: [:])
            prices.append(snapshot.pricing(for: "test-new-model", at: Date())!.inputPerMTok)
            applied.fulfill()
        }
        store.start()
        await fulfillment(of: [applied], timeout: 3)
        store.stop()
        XCTAssertEqual(prices, [2, 4])
        let restored = ModelCatalogStore(publicKey: key.publicKey.rawRepresentation, cache: cache, fetch: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(restored.catalog?.revision, 2)
        await restored.refresh()
        XCTAssertEqual(restored.catalog?.revision, 2)
        XCTAssertNil(restored.lastSuccess)
        XCTAssertTrue(restored.status.contains("保留目录"))
        let rollback = ModelCatalogStore(publicKey: key.publicKey.rawRepresentation, cache: cache, fetch: { _ in first })
        await rollback.refresh()
        XCTAssertEqual(rollback.catalog?.revision, 2)
    }
    func testPreparedCatalogUsesBundledPublicKey() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent("site/models/catalog.json"))
        XCTAssertEqual(try ModelCatalog.decode(bytes, publicKey: Data(base64Encoded: CatalogPublicKey.value)!, minimumRevision: 0).models.count, 3)
    }
    @MainActor
    func testPassiveUpdateSkipOnlySuppressesExactBuildAndNotesArePlain() {
        let update = AvailableUpdate(build: "16", version: "0.13.0", notes: "")
        XCTAssertFalse(update.isVisible(skippedBuild: "16"))
        XCTAssertTrue(update.isVisible(skippedBuild: "15"))
        XCTAssertEqual(UpdateController.plainNotes("<ul><li>新模型</li><li>多选 &amp; 筛选</li></ul>"), "新模型\n多选 & 筛选")
    }
}

extension ModelCatalogTests {
    func testPriceChangeRetainsHistoricalPeriodAndCanonicalOverride() throws {
        var catalog = fixture(2)
        let changeDate = epoch.addingTimeInterval(86400)
        catalog.models[0].validUntil = changeDate
        var newPrice = fixture(2, input: 4).models[0]; newPrice.validFrom = changeDate
        catalog.models.append(newPrice)
        let decoded = try ModelCatalog.decode(sign(catalog), publicKey: key.publicKey.rawRepresentation, minimumRevision: 0)
        let snapshot = PricingSnapshot(catalog: decoded, overrides: [:])
        XCTAssertEqual(snapshot.pricing(for: "test-alias", at: epoch)?.inputPerMTok, 2)
        XCTAssertEqual(snapshot.pricing(for: "test-alias", at: changeDate)?.inputPerMTok, 4)
        let custom = ModelPricing(inputPerMTok: 7, outputPerMTok: 7, cacheWritePerMTok: 7, cacheReadPerMTok: 7)
        XCTAssertEqual(PricingSnapshot(catalog: decoded, overrides: ["test-new-model": custom]).pricing(for: "test-alias", at: changeDate)?.inputPerMTok, 7)
        catalog.models[0].validUntil = changeDate.addingTimeInterval(1)
        XCTAssertThrowsError(try ModelCatalog.decode(sign(catalog), publicKey: key.publicKey.rawRepresentation, minimumRevision: 0))
    }
    @MainActor
    func testCatalogAutoChangePublishesRepricedUsageDashboardWithoutManualRefresh() async throws {
        let first = try sign(fixture(1)), second = try sign(fixture(2, input: 4))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var calls = 0
        let catalog = ModelCatalogStore(publicKey: key.publicKey.rawRepresentation, cache: directory.appendingPathComponent("catalog.json"), refreshInterval: 0.1, pollInterval: 0.02,
            fetch: { _ in calls += 1; return calls == 1 ? first : second })
        let usage = UsageStore(catalogStore: catalog, scanOverride: {
            [UsageEvent(timestamp: Date().addingTimeInterval(-1), model: "test-new-model", inputTokens: 100, outputTokens: 0, cacheCreationTokens: 0, cacheCreation1hTokens: 0, cacheReadTokens: 0, speed: nil, costUSD: nil, sourceApp: "claude", project: "synthetic", sessionID: "test")]
        })
        defer { usage.stop(); catalog.stop() }
        let repriced = expectation(description: "Signed server change reaches published dashboard")
        var fulfilled = false
        let observation = usage.$dashboard.sink { value in
            if !fulfilled && abs(value.overview.totalCostUSD - 0.0004) < 0.0000001 {
                fulfilled = true; repriced.fulfill()
            }
        }
        defer { observation.cancel() }
        usage.start()
        await fulfillment(of: [repriced], timeout: 3)
        XCTAssertEqual(usage.today.totalCostUSD, 0.0004, accuracy: 0.0000001)
        XCTAssertEqual(usage.rankingDailyAggregate().pricingVersion, "remote-2")
    }
}

private final class SyntheticScanFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    func events() -> [UsageEvent] {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        return [UsageEvent(timestamp: Date().addingTimeInterval(-1), model: "gpt-6-sol", inputTokens: 100, outputTokens: 0,
            cacheCreationTokens: 0, cacheCreation1hTokens: 0, cacheReadTokens: 0, speed: nil,
            costUSD: reads == 1 ? 0.0001 : 0.0002, sourceApp: "codex", project: "synthetic", sessionID: "race")]
    }
}
extension ModelCatalogTests {
    @MainActor
    func testDelayedFilterCannotOverwriteFreshScan() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = ModelCatalogStore(publicKey: key.publicKey.rawRepresentation, cache: directory.appendingPathComponent("catalog.json"), fetch: { _ in throw URLError(.notConnectedToInternet) })
        let feed = SyntheticScanFeed()
        let usage = UsageStore(catalogStore: catalog, scanOverride: { feed.events() })
        let initial = expectation(description: "Initial scan")
        var fulfilled = false
        let observation = usage.$dashboard.sink { value in
            if !fulfilled && value.overview.eventCount == 1 { fulfilled = true; initial.fulfill() }
        }
        defer { observation.cancel(); usage.stop(); catalog.stop() }
        usage.refresh()
        await fulfillment(of: [initial], timeout: 2)
        // Captures old priced data in a delayed job, then runs a new scan immediately.
        usage.filter.models = ["gpt-6-sol"]
        usage.refresh()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(usage.dashboard.overview.totalCostUSD, 0.0002, accuracy: 0.0000001)
        XCTAssertFalse(usage.isReaggregating)
    }
}
