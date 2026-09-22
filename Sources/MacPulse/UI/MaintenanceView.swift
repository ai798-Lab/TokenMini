import SwiftUI
import AppKit

/// 独立窗口让文件预览、权限说明和确认对话框不受菜单栏弹窗失焦影响。
struct MaintenanceView: View {
    @EnvironmentObject var cleanup: CleanupStore
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var actions: ProcessActionStore
    @ObservedObject private var settings = DisplaySettings.shared
    @State private var processToQuit: TopProcess?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if settings.isPrism {
                HStack {
                    ThemedSegmented(items: CleanupStore.Page.allCases.map { ($0, $0.rawValue) }, selection: $cleanup.page)
                    Spacer()
                    Text("TOKENMINI").font(.system(size: 13, weight: .black)).foregroundStyle(Prism.secondary)
                }
            } else {
                Picker("管理项目", selection: $cleanup.page) {
                    ForEach(CleanupStore.Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            if cleanup.page == .cleanup { cleanupContent } else { memoryContent }
        }
        .padding(20)
        .background(settings.isPrism ? Prism.bg : Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.isDarkSkin ? .dark : nil)
        .tint(settings.isPrism ? Prism.mint : .accentColor)
        .frame(minWidth: 600, minHeight: 500)
        .onAppear { if !cleanup.hasScanned { cleanup.scan() }; system.refresh() }
        .alert("永久删除所选文件？", isPresented: Binding(
            get: { cleanup.pendingPlan != nil }, set: { if !$0 { cleanup.cancelCleanup() } })) {
            Button("取消", role: .cancel) { cleanup.cancelCleanup() }
            Button("永久删除", role: .destructive) { cleanup.confirmCleanup() }
        } message: {
            let plan = cleanup.pendingPlan ?? []
            let count = plan.flatMap(\.items).count
            Text("将删除 \(count) 个所选顶层项目（文件夹包含其内容）。此操作不能撤销，也不会再次放入废纸篓。建议先退出相关应用。")
        }
        .alert("退出应用或进程？", isPresented: Binding(
            get: { processToQuit != nil }, set: { if !$0 { processToQuit = nil } })) {
            Button("取消", role: .cancel) { processToQuit = nil }
            Button("请求退出", role: .destructive) {
                if let processToQuit { actions.terminate(processToQuit, system: system) }
                processToQuit = nil
            }
        } message: {
            Text("将请求「\(processToQuit?.name ?? "")」退出。请先保存工作；后台进程可能立即结束，不能保证自动保存。")
        }
    }

    private var cleanupContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cleanup.scanStatus).font(.headline)
                    if let time = cleanup.lastScan {
                        Text("上次完成 \(time.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if cleanup.scanning {
                    ProgressView().controlSize(.small)
                    Button("取消扫描") { cleanup.cancelScan() }
                } else {
                    Button("重新扫描") { cleanup.scan() }.disabled(cleanup.cleaning)
                }
            }
            if !cleanup.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("部分目录未能完整读取，具体原因见各分类。0 字节不代表目录为空。")
                    Text("可在系统设置 → 隐私与安全性 → 完全磁盘访问权限中允许 TokenMini，然后退出并重新打开应用，再扫描。文件本身的权限或锁定也可能阻止清理。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("打开完全磁盘访问设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }.padding(10).background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button("取消全选") { cleanup.selected = []; cleanup.excludedPaths = [] }
                Button("恢复默认选择") {
                    cleanup.selected = Set(CleanupCategory.allCases.filter { $0.defaultOn })
                    cleanup.excludedPaths = []
                }
                Spacer()
                Text("展开分类可逐项选择").font(.caption).foregroundStyle(.secondary)
            }.disabled(cleanup.scanning || cleanup.cleaning)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(cleanup.results) { result in
                        VStack(alignment: .leading, spacing: 7) {
                            Toggle(isOn: Binding(get: { cleanup.selected.contains(result.category) },
                                                 set: { _ in cleanup.toggle(result.category) })) {
                                HStack {
                                    Text(result.category.title).font(.headline)
                                    Spacer()
                                    Text(result.sizeLabel).monospacedDigit()
                                }
                            }
                            .disabled(cleanup.scanning || cleanup.cleaning)
                            Text(result.category.subtitle).font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("查看 \(result.items.count) 项" + (result.issues.isEmpty ? "" : " · \(result.issues.count) 项未能读取")) {
                            if result.items.isEmpty && result.issues.isEmpty {
                                Text("没有可清理项目").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(result.items) { item in
                                HStack(alignment: .top) {
                                    Toggle(isOn: Binding(
                                        get: { cleanup.selected.contains(result.category) && !cleanup.excludedPaths.contains(item.path) },
                                        set: { checked in
                                            cleanup.setItemSelected(item, category: result.category, selected: checked)
                                        })) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(URL(fileURLWithPath: item.path).lastPathComponent).lineLimit(1)
                                            Text(displayPath(item.path)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    .disabled(cleanup.scanning || cleanup.cleaning)
                                    Text(ByteFormat.memory(UInt64(max(0, item.bytes))))
                                        .font(.caption).monospacedDigit().frame(width: 80, alignment: .trailing)
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: {
                                        Image(systemName: "folder")
                                    }.help("在访达显示")
                                }
                            }
                            ForEach(result.issues) { issue in issueRow(issue) }
                            }
                        }
                        Divider()
                    }
                    if let report = cleanup.lastReport {
                        Text(report.summary).font(.headline)
                        ForEach(report.issues) { issue in issueRow(issue) }
                    }
                }
            }
            Text("大小是已完整扫描项目的磁盘占用估计；快照、共享数据块或应用重建缓存可能影响实际腾出的空间。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(cleanup.selectionSummary).font(.callout)
                Spacer()
                if cleanup.cleaning { ProgressView().controlSize(.small) }
                Button(cleanup.cleaning ? "正在清理…" : "清理选中…") { cleanup.prepareCleanup() }
                    .buttonStyle(.borderedProminent).disabled(!cleanup.canClean)
            }
        }
    }

    private var memoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已用 \(ByteFormat.memory(system.memory.used)) / \(ByteFormat.memory(system.memory.total))").font(.title2)
                Spacer()
                Button("刷新") { system.refresh() }
            }
            ProgressView(value: system.memory.usageRatio)
            Text(system.memory.pressure >= 1 ? "内存压力：高" : system.memory.pressure > 0 ? "内存压力：偏高" : "内存压力：正常")
                .foregroundStyle(system.memory.pressure > 0 ? Color.orange : Color.green)
            Text("macOS 会自动管理缓存。需要腾出内存时，先保存工作，再退出不用的应用。以下按单个进程的常驻内存排序，浏览器等应用可能有多个进程。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView { LazyVStack(spacing: 8) { ForEach(system.topProcessesByMemory) { process in
                HStack {
                    VStack(alignment: .leading) {
                        Text(process.name)
                        Text("PID \(process.pid)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ByteFormat.memory(process.memoryBytes)).monospacedDigit()
                    Button(actions.pendingPID == process.pid ? "等待退出…" : "退出…") { processToQuit = process }
                        .disabled(actions.pendingPID != nil || ProcessKiller.isProtected(pid: process.pid, name: process.name))
                }.padding(.vertical, 5)
                Divider()
            } } }
            if let message = actions.message { Text(message).font(.callout).textSelection(.enabled) }
            Button("打开活动监视器，查看全部进程") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
        }
    }

    private func issueRow(_ issue: CleanupIssue) -> some View {
        Text("\(displayPath(issue.path))：\(issue.message)")
            .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
    }
    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// 三套主题共用权限与扫描反馈。
struct CleanupStatusView: View {
    @EnvironmentObject var cleanup: CleanupStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if !cleanup.issues.isEmpty {
            Button("\(cleanup.issues.count) 项未能读取 · 查看原因与权限设置") {
                cleanup.page = .cleanup
                openWindow(id: "maintenance")
                NSApp.activate(ignoringOtherApps: true)
            }
            .font(.caption2).foregroundStyle(.orange).buttonStyle(.plain)
        }
    }
}
