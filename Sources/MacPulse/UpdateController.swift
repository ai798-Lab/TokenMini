import AppKit
import Combine
import Sparkle

/// Sparkle 生命周期由单例持有，避免菜单弹窗关闭后 updater 被释放。
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    @Published private(set) var canCheckForUpdates = false
    let controller: SPUStandardUpdaterController
    private var observation: AnyCancellable?
    private let configured: Bool

    private init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        configured = feed.hasPrefix("https://") && !key.isEmpty
        controller = SPUStandardUpdaterController(
            startingUpdater: configured,
            updaterDelegate: nil,
            userDriverDelegate: nil)
        if configured {
            observation = controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.canCheckForUpdates = $0 }
        }
    }

    func checkForUpdates() {
        guard configured else {
            NSWorkspace.shared.open(AppInfo.releases)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
