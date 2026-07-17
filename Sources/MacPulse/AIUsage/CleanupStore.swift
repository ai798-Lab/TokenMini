import Foundation
import Combine

/// 清理与内存回收的状态中心。扫描/删除/回收都在后台队列执行,发布结果给 UI。
@MainActor
final class CleanupStore: ObservableObject {
    @Published var results: [CleanupScanResult] = []
    @Published var selected: Set<CleanupCategory> = Set(CleanupCategory.allCases.filter { $0.defaultOn })
    @Published var scanning = false
    @Published var cleaning = false
    @Published var hasScanned = false
    @Published var lastReport: CleanupReport?

    @Published var releasingMemory = false
    @Published var lastFreedMemory: Int64?      // nil = 本次会话未执行过

    private let scanner = CleanupScanner()
    private let queue = DispatchQueue(label: "macpulse.cleanup", qos: .utility)

    /// 当前勾选类目的合计可清理体积
    var selectedBytes: Int64 {
        results.filter { selected.contains($0.category) }
            .reduce(0) { $0 + $1.totalBytes }
    }

    func toggle(_ category: CleanupCategory) {
        if selected.contains(category) { selected.remove(category) }
        else { selected.insert(category) }
    }

    func scan(resetReport: Bool = true) {
        guard !scanning, !cleaning else { return }
        scanning = true
        if resetReport { lastReport = nil }
        let scanner = self.scanner
        queue.async { [weak self] in
            let r = scanner.scan()
            Task { @MainActor in
                guard let self else { return }
                self.results = r
                self.scanning = false
                self.hasScanned = true
            }
        }
    }

    func clean() {
        guard !cleaning, !scanning, !selected.isEmpty else { return }
        cleaning = true
        let scanner = self.scanner
        let cats = selected
        let res = results
        queue.async { [weak self] in
            let report = scanner.clean(categories: cats, scan: res)
            Task { @MainActor in
                guard let self else { return }
                self.cleaning = false
                self.lastReport = report
                self.scan(resetReport: false) // 清完重扫,但保留本次清理结果
            }
        }
    }

    func releaseMemory() {
        guard !releasingMemory else { return }
        releasingMemory = true
        queue.async { [weak self] in
            let freed = MemoryReleaser.release()
            Task { @MainActor in
                guard let self else { return }
                self.releasingMemory = false
                self.lastFreedMemory = freed
            }
        }
    }
}
