import SwiftUI

struct ModelCatalogStatusView: View {
    @ObservedObject private var catalog = ModelCatalogStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("模型目录自动同步", systemImage: "arrow.triangle.2.circlepath").font(.headline)
            Text(catalog.status).font(.caption).foregroundStyle(.secondary)
            Text("新模型和价格可独立同步，无需重复安装应用。网络不可用时继续使用已验证的本地目录；自定义价格始终优先。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(catalog.checking ? "正在检查…" : "检查模型目录") { Task { await catalog.refresh() } }
                    .buttonStyle(ThemedToolbarButtonStyle()).disabled(catalog.checking)
                if let date = catalog.lastSuccess {
                    Text("同步于 " + date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
