import Foundation
import CryptoKit
import Combine

struct ModelCatalog: Codable, Sendable {
    var schema: Int
    var revision: Int
    var publishedAt: Date
    var models: [Entry]

    struct Entry: Codable, Sendable {
        var id: String
        var aliases: [String]
        var validFrom: Date
        var validUntil: Date?
        var source: URL
        var pricing: ModelPricing
        var fastMultiplier: Double
    }
    struct Envelope: Codable { var payload: Data; var signature: Data }
    enum Failure: Error { case invalid, signature, rollback }

    static func decode(_ bytes: Data, publicKey: Data, minimumRevision: Int, now: Date = Date()) throws -> ModelCatalog {
        guard bytes.count <= 2_000_000 else { throw Failure.invalid }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: bytes)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard key.isValidSignature(envelope.signature, for: envelope.payload) else { throw Failure.signature }
        let catalog = try decoder.decode(Self.self, from: envelope.payload)
        guard catalog.schema == 1, catalog.revision > 0, catalog.models.count <= 10_000,
              catalog.publishedAt <= now.addingTimeInterval(300), !catalog.models.isEmpty else { throw Failure.invalid }
        guard catalog.revision >= minimumRevision else { throw Failure.rollback }
        var periods: [String: [Entry]] = [:]
        for e in catalog.models {
            let p = e.pricing
            let rates = [p.inputPerMTok, p.outputPerMTok, p.cacheWritePerMTok, p.cacheReadPerMTok,
                         p.cacheWrite1hPerMTok, p.above200kInputPerMTok, p.above200kOutputPerMTok,
                         p.above200kCacheReadPerMTok].compactMap { $0 }
            guard !e.id.isEmpty, e.id.count <= 160, e.aliases.count <= 20,
                  e.source.scheme == "https", e.source.host != nil,
                  rates.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1_000_000 }),
                  [e.fastMultiplier, p.fullRequestInputMultiplier, p.fullRequestOutputMultiplier]
                    .allSatisfy({ $0.isFinite && $0 >= 1 && $0 <= 100 }),
                  p.fullRequestThreshold.map({ $0 > 0 && $0 <= 10_000_000 }) ?? true,
                  e.validUntil.map({ $0 > e.validFrom }) ?? true else { throw Failure.invalid }
            for key in [e.id] + e.aliases {
                guard key.count <= 160, !key.isEmpty, PricingTable.normalize(key) == key,
                      ([e.id] + e.aliases).filter({ $0 == key }).count == 1 else { throw Failure.invalid }
                periods[key, default: []].append(e)
            }
        }
        for entries in periods.values {
            let sorted = entries.sorted { $0.validFrom < $1.validFrom }
            guard Set(entries.map(\.id)).count == 1 else { throw Failure.invalid }
            for (left, right) in zip(sorted, sorted.dropFirst()) {
                guard let end = left.validUntil, end <= right.validFrom else { throw Failure.invalid }
            }
        }
        return catalog
    }
}

/// A scan holds one immutable catalog and one copy of user overrides throughout.
/// Per-model memoization belongs to that scan, never to a changing global table.
final class PricingSnapshot: @unchecked Sendable {
    let revision: String
    private let overrides: [String: ModelPricing]
    private let remote: [String: [ModelCatalog.Entry]]
    private let memoLock = NSLock()
    private var normalized: [String: String] = [:]
    init(catalog: ModelCatalog?, overrides: [String: ModelPricing]) {
        revision = catalog.map { "remote-\($0.revision)" } ?? PricingTable.snapshotVersion
        self.overrides = overrides
        var entries: [String: [ModelCatalog.Entry]] = [:]
        for entry in catalog?.models ?? [] { for key in [entry.id] + entry.aliases { entries[key, default: []].append(entry) } }
        remote = entries
    }
    private func key(_ model: String) -> String {
        memoLock.lock(); defer { memoLock.unlock() }
        if let key = normalized[model] { return key }
        let key = PricingTable.normalize(model); normalized[model] = key; return key
    }
    private func entry(_ model: String, at date: Date) -> ModelCatalog.Entry? {
        remote[key(model)]?.first { date >= $0.validFrom && ($0.validUntil.map { date < $0 } ?? true) }
    }
    func pricing(for model: String, at date: Date) -> ModelPricing? {
        let e = entry(model, at: date)
        return overrides[key(model)] ?? e.flatMap { overrides[$0.id] } ?? e?.pricing ?? PricingTable.table[key(model)]
            ?? PricingTable.communityPrices[model.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
    func fastMultiplier(for model: String, at date: Date) -> Double {
        entry(model, at: date)?.fastMultiplier ?? PricingTable.fastMultiplier(for: model)
    }
}

@MainActor
final class ModelCatalogStore: ObservableObject {
    static let shared = ModelCatalogStore()
    @Published private(set) var status = "使用内置模型目录"
    @Published private(set) var checking = false
    @Published private(set) var lastSuccess: Date?
    private(set) var catalog: ModelCatalog?
    private var timer: Timer?
    private var nextAttempt = Date.distantPast
    private var failures = 0
    var onChange: (() -> Void)?
    private let endpoint: URL
    private let publicKey: Data
    private let cache: URL
    private let refreshInterval: TimeInterval
    private let pollInterval: TimeInterval
    private let fetch: (URL) async throws -> Data

    init(endpoint: URL = URL(string: "https://tokenmini.cc/models/catalog.json")!,
         publicKey: Data = Data(base64Encoded: CatalogPublicKey.value)!,
         cache: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenMini/model-catalog.json"),
         refreshInterval: TimeInterval = 6 * 3600, pollInterval: TimeInterval = 60,
         fetch: @escaping (URL) async throws -> Data = ModelCatalogStore.download) {
        self.refreshInterval = refreshInterval; self.pollInterval = pollInterval
        self.endpoint = endpoint; self.publicKey = publicKey; self.cache = cache; self.fetch = fetch
        if let bytes = try? Data(contentsOf: cache),
           let loaded = try? ModelCatalog.decode(bytes, publicKey: publicKey, minimumRevision: 0) {
            catalog = loaded; status = "远程目录 v\(loaded.revision) · 已缓存"
        }
    }

    nonisolated static func download(_ url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw ModelCatalog.Failure.invalid }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", http.expectedContentLength <= 2_000_000 else { throw ModelCatalog.Failure.invalid }
        var result = Data()
        for try await byte in bytes {
            guard result.count < 2_000_000 else { throw ModelCatalog.Failure.invalid }
            result.append(byte)
        }
        return result
    }

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        // Short timer also catches wake-from-sleep and retries; requests are rate limited.
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date() >= self.nextAttempt else { return }
                await self.refresh()
            }
        }
        t.tolerance = min(15, pollInterval / 4); RunLoop.main.add(t, forMode: .common); timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() async {
        guard !checking else { return }
        checking = true; defer { checking = false }
        do {
            let data = try await fetch(endpoint)
            let value = try ModelCatalog.decode(data, publicKey: publicKey, minimumRevision: catalog?.revision ?? 0)
            // Same revision with a different payload must never silently rewrite history.
            if let catalog, value.revision == catalog.revision {
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                guard try encoder.encode(value) == encoder.encode(catalog) else { throw ModelCatalog.Failure.rollback }
            }
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cache, options: .atomic)
            let changed = value.revision != catalog?.revision
            catalog = value; lastSuccess = Date(); failures = 0
            nextAttempt = Date().addingTimeInterval(refreshInterval)
            status = "远程目录 v\(value.revision) · 已自动同步"
            if changed { onChange?() }
        } catch {
            failures = min(failures + 1, 7)
            nextAttempt = Date().addingTimeInterval(min(6 * 3600, 60 * pow(2, Double(failures))))
            status = catalog.map { "同步暂不可用 · 保留目录 v\($0.revision)" } ?? "远程目录暂不可用 · 使用内置价格"
        }
    }
}
