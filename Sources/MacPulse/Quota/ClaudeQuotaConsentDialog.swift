import AppKit

/// 从菜单或首次启动页开启时使用同一个原生确认弹窗。
@MainActor
enum ClaudeQuotaConsentDialog {
    static func confirm() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "允许读取 Claude Code 账号凭证？"
        alert.informativeText = """
        开启后，TokenMini 将读取 macOS 钥匙串中 Claude Code 已保存的账号登录凭证（授权令牌），并使用它向 Anthropic 查询 5 小时和每周的剩余额度及重置时间，约每 5 分钟更新一次。

        凭证仅在内存中用于向 Anthropic 认证，不另行保存；此查询不会上传聊天正文。不需要重新输入账号密码，但仍会使用你的账号授权。实验性接口可能失效。

        你可以随时在设置中关闭。不启用也能使用本地 Token 统计和费用估算。
        """
        // 回车默认选择取消，防止无意中同意凭证访问。
        alert.addButton(withTitle: "取消").keyEquivalent = "\r"
        alert.addButton(withTitle: "同意并开启").keyEquivalent = ""
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
