# Contributing to MacPulse

感谢你帮助改进 MacPulse。

## 开发要求

- macOS 14+，Swift 5 语言模式，Xcode 26 系列。
- 构建只使用 `./scripts/build.sh`，不要直接把裸 `swift build` 当作可分发 App。
- 提交前运行 `./scripts/test.sh`。

## 代码约定

- 共享数据类型统一放在 `Sources/MacPulse/Models.swift`。
- `SystemMonitor` 与 `UsageStore` 的跨 tick 状态只能在各自串行队列访问。
- 修改 `CleanupScanner` 必须覆盖危险路径、路径穿越与符号链接安全测试。
- 不记录 OAuth token、会话正文或真实项目路径。

## 公开仓库边界

只提交用户或贡献者实际需要的文档。内部产品规划、未发布路线图、账号与部署标识、维护者发布手册和协作纪要应保存在仓库之外，或放入已忽略的 `docs/private/`；任何凭证与私钥都不得进入 Git 历史。

## Pull Request

请保持 PR 单一目的，并说明用户可见变化、验证方式和兼容性影响。涉及 UI 时附截图；涉及清理、钥匙串、签名或更新时，明确列出安全边界。
