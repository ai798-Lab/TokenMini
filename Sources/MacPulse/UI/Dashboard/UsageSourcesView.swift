import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct UsageSourcesView: View {
    @EnvironmentObject var usage: UsageStore
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("工具与模型接入").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("本地记录每 60 秒自动更新；导入数据截至文件所覆盖时间。以下为近 90 天的记录数。").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(usage.sourceStatuses) { source in
                        HStack(alignment: .top) {
                            Image(systemName: source.count > 0 ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(source.count > 0 ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.tool.label).font(.headline)
                                Text(source.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(source.count) 条").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Text("Trae Work 官方同步").font(.headline)
                    Toggle("允许读取本机 Trae Work CN 登录状态并查询官方用量", isOn: $traeEnabled)
                    Text("仅向 api.trae.cn 查询近 30 天 Token 用量，凭证不落盘，不传输聊天正文。同步结果只保存在本机；关闭后保留已同步用量。").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(syncingTrae ? "正在同步…" : "同步 Trae Work 用量") { syncTrae() }
                            .disabled(!traeEnabled || syncingTrae)
                        Text(traeStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("导入工具用量").font(.headline)
                    Text("Cursor 可导入官网用量 CSV。其他工具需按模板提供 CSV / JSONL / JSON；仅导入 Token 与费用字段，不保存聊天正文。重复导入会去重。").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Picker("工具", selection: $selectedTool) {
                            ForEach(ToolKind.allCases.filter { !$0.localScanner }) { Text($0.label).tag($0) }
                        }.frame(width: 250)
                        Button(busy ? "正在导入…" : "选择用量文件") { importFile() }.disabled(busy)
                        Button("保存模板") { saveTemplate() }
                    }
                    if selectedTool == .cursor {
                        Link("打开 Cursor 用量页面", destination: URL(string: "https://cursor.com/dashboard?tab=usage")!)
                            .font(.caption)
                    }
                    Divider()
                    Text("模型价格").font(.headline)
                    Text("官方核价 \(PricingTable.table.count) 项 + 社区参考目录 \(PricingTable.communityPrices.count) 项（含渠道与版本，可能重叠），快照 \(PricingTable.snapshotVersion)。优先自定义价格，其次官方，最后社区参考。任何模型都可记录用量；未匹配或未适配的阶梯价格显示“待定价”。").font(.caption).foregroundStyle(.secondary)
                    Text("金额优先采用导入文件的费用；其余按当前标准 API 价格估算，包含社区参考价格，不代表订阅套餐扣款或历史账单。DeepSeek 采用高峰基准价，未计低谷优惠。").font(.caption).foregroundStyle(.secondary)
                    if !usage.dashboard.quality.unknownModels.isEmpty {
                        Text("当前待定价：" + usage.dashboard.quality.unknownModels.joined(separator: "、"))
                            .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    TextField("完整模型 ID（与用量记录一致）", text: $model)
                    HStack {
                        rateField("输入", text: $input)
                        rateField("输出", text: $output)
                        rateField("缓存读", text: $read)
                        rateField("缓存写", text: $write)
                    }
                    HStack {
                        Text("单位：美元 / 百万 Token；保存后优先使用自定义价格。")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("保存价格") { savePrice() }
                    }
                    if !status.isEmpty { Text(status).font(.callout).textSelection(.enabled).accessibilityIdentifier("source-result") }
                }.padding(.trailing, 8)
            }
        }
        .padding(24).frame(width: 720, height: 680)
    }
    private func rateField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("0.00", text: text)
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
