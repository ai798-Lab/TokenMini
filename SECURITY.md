# Security Policy

## Supported versions

公开 Beta 阶段仅支持最新发布版本。安全修复会通过 GitHub Release 与 Sparkle appcast 发布。

## Reporting a vulnerability

请使用 GitHub 仓库的 **Security → Report a vulnerability** 私密报告功能。不要在公开 Issue 中提交 token、会话文件、真实项目路径或可复现凭证。

报告建议包含：MacPulse 版本与构建号、macOS 版本、Mac 芯片、影响范围、最小复现步骤，以及已脱敏的日志。我们会先确认收到，再评估影响和修复窗口。

## Release integrity

公开安装包必须同时具备：

- Developer ID Application 签名与 Hardened Runtime
- Apple 公证并 staple
- Sparkle EdDSA 更新签名
- Release 页面公布的 SHA-256

未公证或 `SKIP_NOTARIZE=1` 生成的产物不得公开分发。
