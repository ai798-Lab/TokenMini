import SwiftUI

/// The same appearance panel is used by the menu bar and the full dashboard.
struct AppearanceSettingsPanel: View {
    @ObservedObject private var settings = DisplaySettings.shared
    @ObservedObject private var alerts = NotificationManager.shared
    @ObservedObject private var updates = UpdateController.shared
    @EnvironmentObject private var quota: QuotaStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("外观与显示").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(PrismButtonStyle())
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("主题") {
                        ForEach(AppTheme.allCases) { theme in
                            ThemedChoiceRow(title: theme.label, selected: settings.theme == theme) {
                                settings.theme = theme
                            }
                        }
                    }
                    section("计量显示") {
                        Text("Token 单位").font(.system(size: 11)).foregroundStyle(.secondary)
                        ThemedSegmented(items: TokenUnitMode.allCases.map { ($0, $0.label) },
                                        selection: $settings.tokenUnit, fillsWidth: true)
                        Text("货币").font(.system(size: 11)).foregroundStyle(.secondary)
                        ThemedSegmented(items: CurrencyMode.allCases.map { ($0, $0.label) },
                                        selection: $settings.currency, fillsWidth: true)
                        if settings.currency == .cny {
                            Text("1 USD = \(String(format: "%.2f", settings.usdToCny)) CNY")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            ThemedSegmented(items: [7.0, 7.2, 7.4].map { ($0, String(format: "%.1f", $0)) },
                                            selection: $settings.usdToCny, fillsWidth: true)
                        }
                    }
                    section("菜单栏显示") {
                        Text("默认只显示图标与今日 Token，可自行增加指标")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        setting("今日 Token", $settings.showTokensInMenuBar)
                        setting("CPU 使用率", $settings.showCPUInMenuBar)
                        setting("内存使用率", $settings.showMemoryInMenuBar)
                        setting("今日等价费用", $settings.showCostInMenuBar)
                        setting("菜单栏显示额度", $settings.showQuotaInMenuBar)
                    }
                    section("刘海与隐私") {
                        setting("刘海常驻油量表", Binding(get: { NotchDock.shared.enabled },
                                                       set: { NotchDock.shared.enabled = $0 }))
                        setting("隐私模式（隐藏项目名）", $settings.privacyMode)
                        setting("Claude 额度（实验）", Binding(get: { quota.claudeAccessEnabled },
                                                          set: { quota.setClaudeAccessEnabled($0) }))
                    }
                    section("提醒") {
                        setting("额度重置提醒", Binding(get: { alerts.enabled }, set: { alerts.setAlertsEnabled($0) }))
                        setting("等价成本提醒", Binding(get: { alerts.costAlertsEnabled }, set: { alerts.setCostAlertsEnabled($0) }))
                        if alerts.costAlertsEnabled {
                            Text("每小时提醒线").font(.system(size: 11)).foregroundStyle(.secondary)
                            ThemedSegmented(items: [10.0, 20.0, 50.0, 100.0].map { ($0, settings.currencyStr($0)) },
                                            selection: $alerts.hourlyThresholdUSD, fillsWidth: true)
                            Text("每日提醒线").font(.system(size: 11)).foregroundStyle(.secondary)
                            ThemedSegmented(items: [50.0, 100.0, 250.0, 500.0].map { ($0, settings.currencyStr($0)) },
                                            selection: $alerts.dailyThresholdUSD, fillsWidth: true)
                            Text("阈值按美元保存，显示随货币换算").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Button("预览刘海提醒") {
                            NotchController.shared.flash(NotchAlert(icon: "checkmark.circle.fill",
                                title: "Claude · 5 小时额度已重置", subtitle: "满血复活,可以继续了 🎉", tint: .green),
                                duration: 6, sound: true)
                        }.buttonStyle(PrismButtonStyle())
                    }
                    section("产品统计与隐私") { ProductAnalyticsSettings() }
                    section("关于 TokenMini") {
                        Text(AppInfo.displayVersion).font(.system(size: 12, weight: .medium))
                        HStack {
                            Button("检查更新") { updates.checkForUpdates() }.disabled(!updates.canCheckForUpdates)
                            Button("社区排行榜") { openWindow(id: "leaderboard"); dismiss() }
                        }.buttonStyle(PrismButtonStyle())
                        HStack {
                            Button("官网") { NSWorkspace.shared.open(AppInfo.homepage) }
                            Button("隐私说明") { NSWorkspace.shared.open(AppInfo.privacy) }
                            Button("开源代码") { NSWorkspace.shared.open(AppInfo.source) }
                        }.buttonStyle(PrismButtonStyle())
                        Button("退出 TokenMini") { NSApp.terminate(nil) }.buttonStyle(PrismButtonStyle())
                    }
                }.padding(16)
            }.frame(maxHeight: 470)
        }
        .frame(width: 350)
        .foregroundStyle(Prism.silver).background(Prism.panel)
        .tint(Prism.mint).preferredColorScheme(.dark)
    }

    private func setting(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value).toggleStyle(ThemedCheckToggleStyle())
            .font(.system(size: 12)).padding(.vertical, 5)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(Prism.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
