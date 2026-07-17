# MacPulse 隐私说明

更新日期：2026-07-17

MacPulse 是本地运行的开源 macOS 菜单栏应用。我们不运营用户账户、数据后台、广告系统、统计分析或自动崩溃上报服务。

## 本地读取的数据

- 系统指标：CPU、内存、网络、磁盘、电池、温度、风扇与进程信息。
- AI 会话统计：只读扫描 `~/.claude` 与 `~/.codex/sessions` 中的 JSONL，提取时间、模型、token 数、项目标识和额度字段用于本地聚合。
- Skills：在用户主动使用管理功能时读取或修改 Claude/Codex Skills 目录。

会话正文不会被上传。项目名只在本机显示；启用“隐私模式”后会替换成稳定别名。

## Claude 额度（实验功能）

该功能默认关闭。用户主动开启后，MacPulse 才会通过 macOS Security.framework 读取钥匙串中服务名为 `Claude Code-credentials` 的现有凭证，并用 OAuth access token 请求 Anthropic 的用量端点。

- token 只在请求期间存在于内存，不写入文件、UserDefaults 或日志。
- MacPulse 不保存凭证副本，也不要求用户把 token 粘贴进应用。
- 该端点并非稳定公开 API；请求失败只会让 Claude 额度显示不可用，不影响其他功能。

## 会发生的网络请求

- 用户开启 Claude 额度时：请求 `api.anthropic.com`。
- 用户主动安装 Skill 时：从用户指定的 GitHub 仓库下载内容。
- 检查或安装 MacPulse 更新时：读取官方 HTTPS appcast，并从 GitHub Releases 下载签名安装包。

除以上用户可感知功能外，MacPulse 不发送遥测、设备指纹、会话内容或使用统计。

## 删除与进程操作

- 缓存清理只处理界面列出的可再生缓存候选项，并在每次删除前再次执行路径安全检查。
- Skill 卸载默认移入废纸篓，可恢复。
- 结束进程使用 SIGTERM，并在操作前展示目标和确认对话框。

## 权限与控制

- 通知默认关闭；用户主动开启时才请求 macOS 通知权限。
- Claude 额度可随时关闭；关闭后不会继续访问钥匙串或 Anthropic 端点。
- 卸载应用不会自动删除 `~/.claude`、`~/.codex` 或用户的任何会话文件。

问题或隐私反馈请通过项目 GitHub Issues 提交；如内容包含凭证或安全漏洞，请按 `SECURITY.md` 使用私密渠道。
