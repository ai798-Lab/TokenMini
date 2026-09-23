import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct UsageSourcesView: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTool: ToolKind = .cursor
    @State private var status = ""
    @State private var busy = false
    @State private var model = ""
    @State private var input = ""
    @State private var output = ""
    @State private var read = ""
    @State private var write = ""
    @AppStorage("traeUsageSyncEnabled") private var traeEnabled = false
    @State private var syncingTrae = false
    @State private var traeStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.plus").foregroundStyle(themeAccent())
                    Text("工具与模型接入").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button("完成") { dismiss() }
                        .modifier(SourceActionChrome()).keyboardShortcut(.cancelAction)
                }
                Text("本地记录每 60 秒自动更新；导入数据截至文件所覆盖时间。以下为近 90 天的记录数。")
                    .font(.system(size: 11)).foregroundStyle(secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            Rectangle().fill(themeAccent().opacity(0.35)).frame(height: 1)
            Group {
                if settings.isDarkSkin {
                    HUDScrollView(accent: themeAccent()) { sections }
                } else {
                    ScrollView { sections }
                }
            }
        }
        .frame(width: 720, height: 680)
        .foregroundStyle(primaryColor)
        .background(backgroundColor)
        .tint(themeAccent())
        .preferredColorScheme(settings.isDarkSkin ? .dark : nil)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 16) {
            sourceSection("用量来源", icon: "externaldrive") {
                ForEach(usage.sourceStatuses) { source in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: source.count > 0 ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(source.count > 0 ? themeAccent() : secondaryColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.tool.label).font(.system(size: 12, weight: .semibold))
                            Text(source.detail).font(.system(size: 10)).foregroundStyle(secondaryColor)
                        }
                        Spacer()
                        Text("\(source.count) 条").font(.system(size: 11, weight: .medium))
                            .monospacedDigit().foregroundStyle(secondaryColor)
                    }
                    .padding(.vertical, 3)
                }
            }
            sourceSection("Trae Work 官方同步", icon: "arrow.triangle.2.circlepath") {
                Toggle("允许读取本机 Trae Work CN 登录状态并查询官方用量", isOn: $traeEnabled)
                    .toggleStyle(.switch).font(.system(size: 12))
                description("仅向 api.trae.cn 查询近 30 天 Token 用量，凭证不落盘，不传输聊天正文。同步结果只保存在本机；关闭后保留已同步用量。")
                HStack {
                    Button(syncingTrae ? "正在同步…" : "同步 Trae Work 用量") { syncTrae() }
                        .modifier(SourceActionChrome()).disabled(!traeEnabled || syncingTrae)
                    Text(traeStatus).font(.caption).foregroundStyle(secondaryColor)
                }
            }
            sourceSection("导入工具用量", icon: "square.and.arrow.down") {
                description("Cursor 可导入官网用量 CSV。其他工具需按模板提供 CSV / JSONL / JSON；仅导入 Token 与费用字段，不保存聊天正文。重复导入会去重。")
                HStack(spacing: 10) {
                    Picker("工具", selection: $selectedTool) {
                        ForEach(ToolKind.allCases.filter { !$0.localScanner }) { Text($0.label).tag($0) }
                    }
                    .modifier(ThemedMenuChrome()).frame(width: 230)
                    Button(busy ? "正在导入…" : "选择用量文件") { importFile() }
                        .modifier(SourceActionChrome()).disabled(busy)
                    Button("保存模板") { saveTemplate() }.modifier(SourceActionChrome())
                }
                if selectedTool == .cursor {
                    Link("打开 Cursor 用量页面", destination: URL(string: "https://cursor.com/dashboard?tab=usage")!)
                        .font(.system(size: 11)).foregroundStyle(themeAccent())
                }
            }
            sourceSection("模型价格", icon: "dollarsign.circle") {
                description("官方核价 \(PricingTable.table.count) 项 + 社区参考目录 \(PricingTable.communityPrices.count) 项（含渠道与版本，可能重叠），快照 \(PricingTable.snapshotVersion)。优先自定义价格，其次官方，最后社区参考。任何模型都可记录用量；未匹配或未适配的阶梯价格显示“待定价”。")
                description("金额优先采用导入文件的费用；其余按当前标准 API 价格估算，包含社区参考价格，不代表订阅套餐扣款或历史账单。DeepSeek 采用高峰基准价，未计低谷优惠。")
                if !usage.dashboard.quality.unknownModels.isEmpty {
                    Text("当前待定价：" + usage.dashboard.quality.unknownModels.joined(separator: "、"))
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                sourceTextField("完整模型 ID（与用量记录一致）", text: $model)
                HStack(spacing: 12) {
                    rateField("输入", text: $input)
                    rateField("输出", text: $output)
                    rateField("缓存读", text: $read)
                    rateField("缓存写", text: $write)
                }
                HStack {
                    description("单位：美元 / 百万 Token；保存后优先使用自定义价格。")
                    Spacer()
                    Button("保存价格") { savePrice() }.modifier(SourceActionChrome())
                }
            }
            if !status.isEmpty {
                Text(status).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("source-result")
            }
        }
        .padding(24)
    }

    private func sourceSection<Content: View>(_ title: String, icon: String,
                                              @ViewBuilder content: @escaping () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(themeAccent())
                content()
            }
        }
    }

    private func description(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(secondaryColor)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private var primaryColor: Color {
        settings.isPrism ? Prism.silver : settings.isHUD ? HUD.text : settings.isLED ? LED.text : .primary
    }
    private var secondaryColor: Color {
        settings.isPrism ? Prism.secondary : settings.isHUD ? HUD.dim : settings.isLED ? LED.dim : .secondary
    }
    private var backgroundColor: Color {
        settings.isPrism ? Prism.bg : settings.isHUD ? HUD.bg : settings.isLED ? LED.bg : Color(nsColor: .windowBackgroundColor)
    }

    @ViewBuilder
    private func sourceTextField(_ placeholder: String, text: Binding<String>) -> some View {
        if settings.isPrism {
            TextField(placeholder, text: text, prompt: Text(placeholder).foregroundColor(Prism.faint))
                .textFieldStyle(.plain).font(Prism.label(12)).foregroundStyle(Prism.silver)
                .padding(9).background(Prism.bg, in: RoundedRectangle(cornerRadius: Prism.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Prism.controlRadius).strokeBorder(Prism.line))
                .accessibilityLabel(placeholder)
        } else {
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func rateField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(secondaryColor)
            sourceTextField("0.00", text: text).accessibilityLabel(label + "价格")
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json, .plainText, .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; status = "正在校验文件…"
        let tool = selectedTool
        Task {
            do {
                let count = try await Task.detached(priority: .utility) {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 32 * 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
                    let data = try Data(contentsOf: url)
                    let rows = try UsageImport.parse(data, format: url.pathExtension, tool: tool)
                    return try UsageImport.save(rows)
                }.value
                status = "已导入 \(count) 条新记录，重复记录自动跳过。"
                usage.refresh()
            } catch { status = "导入失败：" + error.localizedDescription }
            busy = false
        }
    }
    private func syncTrae() {
        syncingTrae = true; traeStatus = "正在查询官方用量…"
        Task {
            do {
                let count = try await TraeUsageClient.fetchAndSave()
                traeStatus = "已同步近 30 天 \(count) 个会话"
                usage.refresh()
            } catch { traeStatus = error.localizedDescription }
            syncingTrae = false
        }
    }
    private func saveTemplate() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TokenMini-usage-template.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let date = ISO8601DateFormatter().string(from: Date())
        let template = "timestamp,model,input,output,cacheRead,cacheWrite,costUSD,id,project,session\n\(date),your-model-id,100,20,0,0,,replace-with-request-id,Example,session-1\n"
        do { try template.write(to: url, atomically: true, encoding: .utf8); status = "模板已保存。请用真实用量替换示例行再导入。" }
        catch { status = error.localizedDescription }
    }
    private func savePrice() {
        guard let i = Double(input), let o = Double(output), let r = Double(read), let w = Double(write),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "请填写完整模型 ID 和四项非负价格；免费项填 0。"; return
        }
        do {
            try PricingTable.saveCustomPrice(model: model, rate: .init(input: i, output: o, cacheWrite: w, cacheRead: r))
            status = "已保存自定义价格，正在重新计算。"
            usage.refresh()
        } catch { status = "价格无效：请填写有限的非负数字。" }
    }
}

/// Reuse the same Prism controls as the dashboard; keep native controls in Classic.
private struct SourceActionChrome: ViewModifier {
    @ObservedObject private var settings = DisplaySettings.shared
    func body(content: Content) -> some View {
        if settings.isPrism {
            content.buttonStyle(PrismButtonStyle())
        } else if settings.isHUD {
            content.buttonStyle(HUDButtonStyle(accent: HUD.cyan, size: 11))
        } else {
            content.buttonStyle(.bordered).tint(themeAccent())
        }
    }
}
