import AppKit
import Combine
import Sparkle

struct AvailableUpdate: Equatable {
    let build: String
    let version: String
    let notes: String
    func isVisible(skippedBuild: String?) -> Bool { build != skippedBuild }
}

/// Background work is an information probe only. Only an explicit user action
/// may hand control to Sparkle's installer UI.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var available: AvailableUpdate?
    private(set) var controller: SPUStandardUpdaterController!
    private var observation: AnyCancellable?
    private var timer: Timer?
    private let configured: Bool
    private let skipKey = "tokenmini.skippedUpdateBuild"

    private override init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        configured = feed.hasPrefix("https://") && !key.isEmpty
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        guard configured else { return }
        // Also overrides the preference left behind by older installed versions.
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
        do { try controller.updater.start() } catch { return }
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    func start() {
        guard configured, timer == nil else { return }
        probe()
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probe() }
        }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func probe() {
        guard !controller.updater.sessionInProgress else { return }
        controller.updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let update = AvailableUpdate(build: item.versionString, version: item.displayVersionString,
                                     notes: Self.plainNotes(item.itemDescription))
        available = update.isVisible(skippedBuild: UserDefaults.standard.string(forKey: skipKey)) ? update : nil
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // Defense in depth if an older preference or a future call re-enables Sparkle's scheduler.
        if updateCheck == .updatesInBackground { throw CocoaError(.userCancelled) }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { available = nil }

    func skipVersion() {
        guard let available else { return }
        UserDefaults.standard.set(available.build, forKey: skipKey)
        self.available = nil
    }

    func checkForUpdates() {
        guard configured else { NSWorkspace.shared.open(AppInfo.releases); return }
        guard canCheckForUpdates else { return }
        // Called exclusively by the user's update buttons, never by a timer/delegate.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    static func plainNotes(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "此版本包含功能改进和问题修复。完整说明将在更新窗口中展示。" }
        return String(html.replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500))
    }
}
