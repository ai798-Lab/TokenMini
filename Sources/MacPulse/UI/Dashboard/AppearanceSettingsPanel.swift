import SwiftUI

/// The same appearance panel is used by the menu bar and the full dashboard.
struct AppearanceSettingsPanel: View {
    @ObservedObject private var settings = DisplaySettings.shared
    @ObservedObject private var alerts = NotificationManager.shared
    @ObservedObject private var updates = UpdateController.shared
    @ObservedObject private var language = AppLanguageStore.shared
    @EnvironmentObject private var quota: QuotaStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("外观与显示")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(L10n.text("完成")) { dismiss() }.buttonStyle(PrismButtonStyle())
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(L10n.text("语言")) {
                        Picker(L10n.text("语言"), selection: $language.selection) {
                            ForEach(AppLanguage.allCases) { choice in
                                Text(verbatim: choice.nativeName).tag(choice)
                            }
                        }.pickerStyle(.menu)
                        .environment(\.layoutDirection, .leftToRight)
                        Text(L10n.text("语言独立于货币；更改语言不会换算金额。"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(L10n.text("软件更新窗口的语言将在下次启动后同步。"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    section(L10n.text("主题")) {
                        ForEach(AppTheme.allCases) { theme in
                            ThemedChoiceRow(title: theme.label, selected: settings.theme == theme) {
                                settings.theme = theme
                            }
                        }
                    }
                    section(L10n.text("计量显示")) {
                        Text(L10n.text("Token 单位")).font(.system(size: 11)).foregroundStyle(.secondary)
                        ThemedSegmented(items: TokenUnitMode.allCases.map { ($0, $0.label) },
                                        selection: $settings.tokenUnit, fillsWidth: true)
                        Text(L10n.text("货币")).font(.system(size: 11)).foregroundStyle(.secondary)
                        ThemedSegmented(items: CurrencyMode.allCases.map { ($0, $0.label) },
                                        selection: $settings.currency, fillsWidth: true)
                        if settings.currency == .cny {
                            Text("1 USD = \(String(format: "%.2f", settings.usdToCny)) CNY")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            ThemedSegmented(items: [7.0, 7.2, 7.4].map { ($0, String(format: "%.1f", $0)) },
                                            selection: $settings.usdToCny, fillsWidth: true)
                        }
                    }
                    section(L10n.text("菜单栏显示")) {
                        Text(L10n.text("默认只显示图标与今日 Token，可自行增加指标"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        setting(L10n.text("今日 Token"), $settings.showTokensInMenuBar)
                        setting(L10n.text("CPU 使用率"), $settings.showCPUInMenuBar)
                        setting(L10n.text("内存使用率"), $settings.showMemoryInMenuBar)
                        setting(L10n.text("今日等价费用"), $settings.showCostInMenuBar)
                        setting(L10n.text("菜单栏显示额度"), $settings.showQuotaInMenuBar)
                    }
                    section(L10n.text("刘海与隐私")) {
                        setting(L10n.text("刘海常驻油量表"), Binding(get: { NotchDock.shared.enabled },
                                                       set: { NotchDock.shared.enabled = $0 }))
                        setting(L10n.text("隐私模式（隐藏项目名）"), $settings.privacyMode)
                        setting(L10n.text("Claude 额度（实验）"), Binding(get: { quota.claudeAccessEnabled },
                                                          set: { quota.setClaudeAccessEnabled($0) }))
                    }
                    section(L10n.text("提醒")) {
                        setting(L10n.text("额度重置提醒"), Binding(get: { alerts.enabled }, set: { alerts.setAlertsEnabled($0) }))
                        setting(L10n.text("等价成本提醒"), Binding(get: { alerts.costAlertsEnabled }, set: { alerts.setCostAlertsEnabled($0) }))
                        if alerts.costAlertsEnabled {
                            Text(L10n.text("每小时提醒线")).font(.system(size: 11)).foregroundStyle(.secondary)
                            ThemedSegmented(items: [10.0, 20.0, 50.0, 100.0].map { ($0, settings.currencyStr($0)) },
                                            selection: $alerts.hourlyThresholdUSD, fillsWidth: true)
                            Text(L10n.text("每日提醒线")).font(.system(size: 11)).foregroundStyle(.secondary)
                            ThemedSegmented(items: [50.0, 100.0, 250.0, 500.0].map { ($0, settings.currencyStr($0)) },
                                            selection: $alerts.dailyThresholdUSD, fillsWidth: true)
                            Text(L10n.text("阈值按美元保存，显示随货币换算")).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Button(L10n.text("预览刘海提醒")) {
                            NotchController.shared.flash(NotchAlert(icon: "checkmark.circle.fill",
                                title: L10n.text("Claude · 5 小时额度已重置"), subtitle: L10n.text("满血复活,可以继续了 🎉"), tint: .green),
                                duration: 6, sound: true)
                        }.buttonStyle(PrismButtonStyle())
                    }
                    section(L10n.text("产品统计与隐私")) { ProductAnalyticsSettings() }
                    section(L10n.text("关于 TokenMini")) {
                        Text(AppInfo.displayVersion).font(.system(size: 12, weight: .medium))
                        HStack {
                            Button(L10n.text("检查更新")) { updates.checkForUpdates() }.disabled(!updates.canCheckForUpdates)
                            Button(L10n.text("社区排行榜")) { openWindow(id: "leaderboard"); dismiss() }
                        }.buttonStyle(PrismButtonStyle())
                        HStack {
                            Button(L10n.text("官网")) { NSWorkspace.shared.open(AppInfo.homepage) }
                            Button(L10n.text("隐私说明")) { NSWorkspace.shared.open(AppInfo.privacy) }
                            Button(L10n.text("开源代码")) { NSWorkspace.shared.open(AppInfo.source) }
                        }.buttonStyle(PrismButtonStyle())
                        Button(L10n.text("退出 TokenMini")) { NSApp.terminate(nil) }.buttonStyle(PrismButtonStyle())
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
