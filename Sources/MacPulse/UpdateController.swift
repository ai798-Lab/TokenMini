import AppKit
import Combine
import Sparkle

struct AvailableUpdate: Equatable, Codable {
    let build: String
    let version: String
    let notes: String
    func isVisible(skippedBuild: String?) -> Bool { build != skippedBuild }

    /// Use actual release text so a future feed never inherits stale, hard-coded promises.
    var highlights: [String] {
        let lines = notes.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let bullets = lines.filter { $0.range(of: "^([-*•]|[0-9]+[.)])\\s+", options: .regularExpression) != nil }
        let entries = (bullets.isEmpty ? lines : bullets)
            .map { $0.replacingOccurrences(of: "^([-*•]|[0-9]+[.)])\\s+", with: "", options: .regularExpression) }
        return entries.prefix(3).map { entry in
            entry.count > 72 ? String(entry.prefix(71)) + "…" : entry
        }
    }
}

/// Background work is an information probe only. Only an explicit user action
/// may hand control to Sparkle's installer UI.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var skippedUpdate: AvailableUpdate?
    private(set) var controller: SPUStandardUpdaterController!
    private var observation: AnyCancellable?
    private var timer: Timer?
    private let configured: Bool
    private let skipKey = "tokenmini.skippedUpdateBuild"
    private let skippedDetailsKey = "tokenmini.skippedUpdateDetails"
    // Our own marker, not Sparkle's private preferences. Native skips need a
    // user-initiated check to be undone through Sparkle's public API.
    private let nativeSkipKey = "tokenmini.nativeSkippedUpdateBuild"
    private var pendingNativeSkipRestore: String?

    private override init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        configured = feed.hasPrefix("https://") && !key.isEmpty
        super.init()
        if let data = UserDefaults.standard.data(forKey: skippedDetailsKey),
           let cached = try? JSONDecoder().decode(AvailableUpdate.self, from: data),
           cached.build == UserDefaults.standard.string(forKey: skipKey),
           cached.build.compare(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0", options: .numeric) == .orderedDescending {
            skippedUpdate = cached
        }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        guard configured else { return }
        // Also overrides the preference left behind by older installed versions.
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
        do { try controller.updater.start() } catch { return }
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
                self?.performPendingNativeSkipRestore()
            }
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
        if update.isVisible(skippedBuild: UserDefaults.standard.string(forKey: skipKey)) {
            available = update
            skippedUpdate = nil
            UserDefaults.standard.removeObject(forKey: skippedDetailsKey)
            UserDefaults.standard.removeObject(forKey: nativeSkipKey)
            pendingNativeSkipRestore = nil
        } else {
            available = nil
            skippedUpdate = update
            persistSkippedDetails(update)
        }
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        guard choice == .skip else { return }
        let update = AvailableUpdate(build: item.versionString, version: item.displayVersionString,
                                     notes: Self.plainNotes(item.itemDescription))
        rememberSkipped(update, native: true)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // Defense in depth if an older preference or a future call re-enables Sparkle's scheduler.
        if updateCheck == .updatesInBackground { throw CocoaError(.userCancelled) }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        available = nil
        // Informational probes intentionally omit Sparkle-skipped versions.
        // "No update" therefore must not erase the native skip's undo action.
        if let skippedUpdate,
           UserDefaults.standard.string(forKey: nativeSkipKey) == skippedUpdate.build {
            return
        }
        skippedUpdate = nil
        UserDefaults.standard.removeObject(forKey: skippedDetailsKey)
        UserDefaults.standard.removeObject(forKey: nativeSkipKey)
    }

    func skipVersion() {
        guard let available else { return }
        rememberSkipped(available, native: false)
    }

    private func rememberSkipped(_ update: AvailableUpdate, native: Bool) {
        pendingNativeSkipRestore = nil
        UserDefaults.standard.set(update.build, forKey: skipKey)
        if native {
            UserDefaults.standard.set(update.build, forKey: nativeSkipKey)
        } else {
            UserDefaults.standard.removeObject(forKey: nativeSkipKey)
        }
        skippedUpdate = update
        persistSkippedDetails(update)
        self.available = nil
    }

    func restoreSkippedVersion() {
        guard let skippedUpdate else { return }
        if UserDefaults.standard.string(forKey: nativeSkipKey) == skippedUpdate.build {
            // SPUUpdater.checkForUpdates finds previously skipped updates and
            // clears Sparkle's skip state. There is no public silent-reset API.
            // This explicit Undo opens Sparkle's UI, without starting a download.
            pendingNativeSkipRestore = skippedUpdate.build
            performPendingNativeSkipRestore()
            return
        }
        restoreLocalNotice(skippedUpdate)
    }

    private func restoreLocalNotice(_ update: AvailableUpdate) {
        UserDefaults.standard.removeObject(forKey: skipKey)
        UserDefaults.standard.removeObject(forKey: skippedDetailsKey)
        available = update
        self.skippedUpdate = nil
    }

    private func performPendingNativeSkipRestore() {
        guard let build = pendingNativeSkipRestore,
              let skippedUpdate, skippedUpdate.build == build,
              configured, canCheckForUpdates, !controller.updater.sessionInProgress else { return }
        pendingNativeSkipRestore = nil
        restoreLocalNotice(skippedUpdate)
        checkForUpdates()
    }

    private func persistSkippedDetails(_ update: AvailableUpdate) {
        if let data = try? JSONEncoder().encode(update) {
            UserDefaults.standard.set(data, forKey: skippedDetailsKey)
        }
    }

    func checkForUpdates() {
        guard configured else { NSWorkspace.shared.open(AppInfo.releases); return }
        guard canCheckForUpdates else { return }
        // Sparkle's public, user-initiated check clears its own skipped state.
        UserDefaults.standard.removeObject(forKey: nativeSkipKey)
        // Called exclusively by the user's update buttons, never by a timer/delegate.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    static func plainNotes(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return L10n.text("此版本包含功能改进和问题修复。完整说明将在更新窗口中展示。") }
        return String(html.replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
