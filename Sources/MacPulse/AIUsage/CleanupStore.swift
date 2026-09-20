import Foundation
import Combine

private final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

/// 清理状态与确认快照。扫描、删除、重扫在同一队列串行执行。
@MainActor
final class CleanupStore: ObservableObject {
    enum Page: String, CaseIterable { case cleanup = "磁盘清理", memory = "内存管理" }
    @Published var page: Page = .cleanup
    @Published private(set) var results: [CleanupScanResult] = []
    @Published var selected: Set<CleanupCategory> = Set(CleanupCategory.allCases.filter { $0.defaultOn })
    @Published private(set) var scanning = false
    @Published private(set) var cleaning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var lastReport: CleanupReport?
    @Published private(set) var scanStatus = "尚未扫描"
    @Published private(set) var lastScan: Date?
    @Published var excludedPaths: Set<String> = []
    @Published private(set) var pendingPlan: [CleanupScanResult]?

    private let scanner: CleanupScanner
    private let queue = DispatchQueue(label: "macpulse.cleanup", qos: .utility)
    private var cancellation: ScanCancellation?

    init(scanner: CleanupScanner = CleanupScanner()) { self.scanner = scanner }

    var selectedItems: [CleanupItem] {
        results.filter { selected.contains($0.category) }.flatMap(\.items)
            .filter { !excludedPaths.contains($0.path) }
    }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var canClean: Bool { hasScanned && !scanning && !cleaning && !selectedItems.isEmpty }
    var issues: [CleanupIssue] { results.flatMap(\.issues) }
    var selectionSummary: String {
        if scanning { return scanStatus }
        if !hasScanned { return "请先扫描" }
        if selectedItems.isEmpty { return issues.isEmpty ? "请选择要清理的项目" : "部分目录不可读，请查看详情" }
        return "已选 \(selectedItems.count) 项 · \(ByteFormat.memory(UInt64(max(0, selectedBytes))))"
    }

    func toggle(_ category: CleanupCategory) {
        guard !scanning, !cleaning, pendingPlan == nil else { return }
        if selected.contains(category) { selected.remove(category) }
        else { selected.insert(category) }
    }

    func setItemSelected(_ item: CleanupItem, category: CleanupCategory, selected checked: Bool) {
        guard !scanning, !cleaning, pendingPlan == nil else { return }
        if checked {
            if !selected.contains(category) {
                // 从未选择的分类里选单项，不应顺便选中整类。
                selected.insert(category)
                excludedPaths.formUnion(results.first { $0.category == category }?.items.map(\.path) ?? [])
            }
            excludedPaths.remove(item.path)
        } else {
            excludedPaths.insert(item.path)
        }
    }

    func scan(resetReport: Bool = true) {
        guard !scanning, !cleaning, pendingPlan == nil else { return }
        scanning = true
        scanStatus = "准备扫描…"
        if resetReport { lastReport = nil }
        let flag = ScanCancellation()
        cancellation = flag
        let scanner = self.scanner
        queue.async { [weak self] in
            let r = scanner.scan(cancelled: { flag.cancelled }, progress: { category in
                Task { @MainActor [weak self] in
                    guard let self, self.scanning, !flag.cancelled else { return }
                    self.scanStatus = "正在扫描\(category.title)…"
                }
            })
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                self.cancellation = nil
                if flag.cancelled { self.scanStatus = "已取消扫描，保留上次结果"; return }
                self.results = r
                self.excludedPaths = []
                self.hasScanned = true
                self.lastScan = Date()
                self.scanStatus = self.issues.isEmpty ? "扫描完成" : "扫描完成，\(self.issues.count) 项无法读取"
            }
        }
    }

    func cancelScan() { cancellation?.cancel(); scanStatus = "正在取消…" }

    /// 确认时展示并冻结同一份具体文件列表，避免确认后再读取变化的勾选状态。
    func prepareCleanup() {
        guard canClean else { return }
        pendingPlan = results.filter { selected.contains($0.category) }.map {
            let items = $0.items.filter { !excludedPaths.contains($0.path) }
            return CleanupScanResult(category: $0.category, totalBytes: items.reduce(0) { $0 + $1.bytes }, items: items)
        }
    }
    func cancelCleanup() { pendingPlan = nil }

    func confirmCleanup() {
        guard let plan = pendingPlan, !cleaning, !scanning else { return }
        pendingPlan = nil
        cleaning = true
        lastReport = nil
        let scanner = self.scanner
        queue.async { [weak self] in
            let report = scanner.clean(categories: Set(plan.map(\.category)), scan: plan)
            Task { @MainActor in
                guard let self else { return }
                self.cleaning = false
                self.lastReport = report
                self.scan(resetReport: false)
            }
        }
    }
}
