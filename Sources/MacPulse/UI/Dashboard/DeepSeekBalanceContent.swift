import SwiftUI

struct DeepSeekBalanceContent: View {
    @EnvironmentObject var quota: QuotaStore
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if quota.deepSeekAccessEnabled {
                HStack {
                    if let balance = quota.deepSeekBalance {
                        Text(balance.amounts.map(\.display).joined(separator: " · "))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        Text(balance.available ? L10n.text("可用") : L10n.text("账号当前不可用"))
                            .font(.caption).foregroundStyle(balance.available ? .green : .orange)
                        Spacer()
                        Text(balance.asOf, style: .time).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(quota.deepSeekRefreshing ? L10n.text("正在查询 DeepSeek…") : L10n.text("尚未取得官方余额"))
                        Spacer()
                    }
                    Button(L10n.text("更新余额")) { quota.refreshDeepSeek() }.disabled(quota.deepSeekRefreshing)
                }
                if let error = quota.deepSeekError { Text(error).font(.caption).foregroundStyle(.orange) }
                if !quota.deepSeekModels.isEmpty {
                    Text(L10n.text("官方可用模型：") + quota.deepSeekModels.joined(separator: "、"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
