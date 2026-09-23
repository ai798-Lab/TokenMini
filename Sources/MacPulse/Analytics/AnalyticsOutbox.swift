import Foundation

enum ProductEvent: String, Codable {
    case observationStarted = "observation_started"
    case appStart = "app_start"
    case engagement = "app_engagement"
    case menuViewed = "menu_viewed"
    case dashboardViewed = "dashboard_viewed"
    case maintenanceViewed = "maintenance_viewed"
    case rankingsViewed = "rankings_viewed"
}

struct AnalyticsEvent: Codable {
    let id: String
    let profileID: String
    let name: ProductEvent
    let occurredAt: Date
    let cohort: String
    let version: String
    let runtime: Double
    let interaction: Double

    func openPanelBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "track",
            "payload": ["name": name.rawValue, "profileId": profileID, "properties": [
                "product": "tokenmini", "platform": "macos", "version": version,
                "cohort": cohort, "event_id": id,
                "__timestamp": ISO8601DateFormatter().string(from: occurredAt),
                "runtime_seconds": runtime, "interaction_seconds": interaction
            ]] as [String: Any]
        ])
    }
}

/// Small disk outbox; analytics storage, exploration and cohorts belong to OpenPanel.
/// Use only on the main thread. No session content or free-form properties are accepted.
final class AnalyticsOutbox {
    private struct State: Codable {
        var enabled = false
        var profileID: String?
        var cohort: String
        var events: [AnalyticsEvent] = []
    }
    private let file: URL
    private let limit: Int
    private var state: State
    private(set) var storageFailed = false
    var enabled: Bool { state.enabled }
    var profileID: String? { state.profileID }
    var cohort: String { state.cohort }
    var events: [AnalyticsEvent] { state.events }

    init(file: URL, cohort: String, limit: Int = 2000) {
        self.file = file
        self.limit = max(2, limit)
        state = State(cohort: ["new", "upgrade", "unknown"].contains(cohort) ? cohort : "unknown")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
            if !state.enabled { state.events = []; state.profileID = nil }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != state.enabled else { return }
        state.enabled = enabled
        if enabled {
            state.profileID = UUID().uuidString
            record(.observationStarted)
        } else {
            state.events = []
            state.profileID = nil
            // A fresh explicit consent creates a new observation, never a new install claim.
            state.cohort = "unknown"
            save()
        }
    }

    func record(_ event: ProductEvent, at: Date = Date(), runtime: Double = 0, interaction: Double = 0) {
        guard enabled, let profileID else { return }
        let duration = runtime.isFinite ? min(300, max(0, runtime)) : 0
        let active = interaction.isFinite ? min(duration, max(0, interaction)) : 0
        state.events.append(AnalyticsEvent(id: UUID().uuidString, profileID: profileID, name: event,
            occurredAt: at, cohort: cohort,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            runtime: duration, interaction: active))
        // Keep the unsent cohort origin. Drop oldest routine events at the fixed disk limit.
        while state.events.count > limit {
            state.events.remove(at: state.events.first?.name == .observationStarted ? 1 : 0)
        }
        save()
    }

    func acknowledge(_ id: String) {
        state.events.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            storageFailed = false
        } catch { storageFailed = true }
    }
}

struct AnalyticsDuration: Equatable {
    var runtime: Double
    var interaction: Double
    static let zero = Self(runtime: 0, interaction: 0)
}

struct AnalyticsClock {
    private var last: Double?
    mutating func sample(uptime: Double, running: Bool, interacting: Bool) -> AnalyticsDuration {
        defer { last = uptime }
        guard let last, uptime >= last, uptime - last <= 15, running else { return .zero }
        return .init(runtime: uptime - last, interaction: interacting ? uptime - last : 0)
    }
    mutating func reset() { last = nil }
}
