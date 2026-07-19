# MacPulse GitHub 装修调研与方案

> 调研日期：2026-07-18
> 目标：让第一次进入仓库的人在 30 秒内看懂“它是什么、为什么值得下载、是否可信、如何参与”，同时保持版本、隐私和分发信息真实。

## 一、结论先行

优秀项目的共同点不是“徽章越多越好”，而是把仓库首页当作产品落地页：首屏讲清定位与下一步，真实图片证明产品存在，结构化信息降低理解成本，社区文件让反馈可执行。MacPulse 应采用以下组合：

1. 英文 `README.md` 作为默认首页，`README.zh-CN.md` 提供完整中文镜像，首屏双向切换。
2. 只保留能回答事实问题的徽章：Release、CI、许可证、系统要求、芯片架构、技术栈、Beta 状态、本地优先。
3. 用真实构建截图组成 Hero 与图集；截图默认开启隐私模式，不展示凭证、路径、后台或失败状态。
4. 把下载、官网、隐私说明放在首屏，把维护细节折叠或链接到开发文档。
5. 用 Issue 表单、PR 模板、Topics 与标签建立可搜索、可分流的社区入口。
6. 明确区分 **v0.9.0 正式 Release** 与 `main` 上的 **v0.10 未发布预览**，不制造已经发布的错觉。

## 二、优秀案例与可复用模式

| 项目 | 首页做法 | 可复用模式 | MacPulse 的取舍 |
| --- | --- | --- | --- |
| [LocalSend](https://github.com/localsend/localsend) | 多语言入口、少量事实徽章、下载入口、跨平台截图 | 语言切换出现在首屏；“立即获取”比安装细节更靠前；截图承担产品解释 | 学习双语入口和下载层级，不照搬跨平台叙事 |
| [Ice](https://github.com/jordanbaird/Ice) | 图标、品牌横幅、系统要求与版本徽章、截图画廊 | 原生 macOS 项目适合以图标和宽屏视觉建立第一印象 | 学习原生感和画廊；MacPulse 不增加无事实依据的平台徽章 |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) | 清晰下载 CTA、状态徽章、主截图、多图网格 | 先证明“可以下载并运行”，再解释功能；多图覆盖关键任务 | 学习 CTA 与多图布局；不复制与显示器控制相关的技术信息 |
| [Stats](https://github.com/exelban/stats) | 大图优先、直接 Release 入口、语言列表 | 菜单栏工具需要尽快展示信息密度和原生界面 | 学习图片优先和直接下载；MacPulse 只维护两份高质量语言文档 |

这些案例的共同结构可以归纳为：

```text
品牌与一句话定位
  ├─ 语言 / 版本 / 平台事实
  ├─ 下载 / 官网 / 隐私主入口
  ├─ 一张宽屏产品证据图
  ├─ 核心价值与关键功能
  ├─ 多图画廊
  └─ 要求 / 隐私 / 开发 / 贡献
```

## 三、GitHub 官方规范

### README 与相对链接

GitHub 会自动呈现仓库根目录等位置的 README，并建议 README 说明项目用途、入门方式、帮助入口和维护者信息。文档内图片、文件与目录宜使用相对路径，保证分支和克隆环境中的链接仍然成立。

- [About READMEs — GitHub Docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)
- [Basic writing and formatting syntax / Relative links — GitHub Docs](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/basic-writing-and-formatting-syntax#relative-links)

### Topics

Topics 用于发现和分类仓库。名称只能包含小写字母、数字和连字符；每个仓库最多 20 个。应优先覆盖平台、技术栈、产品形态、核心能力与集成对象，不把营销口号拆成 Topics。

- [Classifying your repository with topics — GitHub Docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics)

### Social Preview

GitHub 建议自定义社交预览图采用 2:1 画幅，推荐至少 1280×640，文件小于 1 MB。预览图在分享链接时承担“品牌识别 + 一句话解释”，不应塞入小字号功能清单。

- [Customizing your repository's social media preview — GitHub Docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview)

### 社区健康文件与安全

Issue 表单通过结构化字段提高复现质量；PR 模板用于统一验证、隐私与变更说明。公开安全问题不应要求用户粘贴凭证，仓库应引导使用私密漏洞报告或安全策略中的私密渠道。

- [Configuring issue templates for your repository — GitHub Docs](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository)
- [Creating a pull request template for your repository — GitHub Docs](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository)
- [Adding a security policy to your repository — GitHub Docs](https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository)

## 四、MacPulse 当前问题

装修前的首页信息丰富，但存在以下阻力：

- 首屏缺少强定位、语言切换、下载与隐私入口，读者要滚动后才知道下一步。
- 文字很长，产品价值、用户功能、实现细节和本机维护历史混在同一层级。
- 缺少一组经过隐私处理的真实产品图，外部读者无法快速判断完成度与界面形态。
- Release 事实与开发分支状态容易混淆：正式 Sparkle feed 仍是 v0.9.0，而 `main` 已包含 v0.10 预览内容。
- Issue 分类较少，缺 PR 模板、Issue 配置与统一标签色板。
- 仓库 About、Topics 与 Social Preview 尚未形成完整的发现入口。

## 五、推荐信息架构

### 首屏

1. 图标、项目名和一句话定位。
2. `English · 简体中文` 双向切换。
3. 两行事实徽章。
4. 下载、官网、图集与隐私四个入口。
5. 一张 16:9 宽屏 Hero。
6. 紧随其后的版本事实提示：v0.9.0 已发布、v0.10 为未发布预览、App UI 仍以中文为主。

### 正文

- **核心价值**：系统脉搏、AI 用量、额度感知、本地优先工具。
- **图集**：主题差异、分析模式、公开官网；后续有稳定自动化后再补刘海与 Skills 独立截图。
- **功能矩阵**：系统、AI 用量、额度、体验与可选工具。
- **下载要求**：Apple Silicon、macOS 14+、签名与公证。
- **隐私边界**：本地数据、允许联网的可见功能、不采集的内容。
- **开发与贡献**：构建脚本、发布文档、Issue/PR 入口。

维护者专属内容（例如特定机器上的 CLT 历史残留、签名凭证配置、公证排障）不应占据用户首页主叙事，应放在开发或发布文档中。

## 六、徽章准则

### 保留

| 徽章 | 回答的问题 |
| --- | --- |
| Latest Release | 当前可下载版本是什么 |
| CI | 主线是否通过自动检查 |
| MIT | 使用与分发的许可是什么 |
| macOS 14+ | 最低系统要求是什么 |
| Apple Silicon | 支持什么硬件架构 |
| Swift / SwiftUI | 主要技术栈是什么 |
| Public Beta | 产品成熟度是什么 |
| Local-first | 隐私和数据处理的核心承诺是什么 |

### 不使用

- 访问量、Star 数、Fork 数等会制造热度但不提高理解的徽章。
- 没有自动验证来源的“100% privacy”“production ready”等宣称。
- Homebrew 徽章或 `brew install macpulse`：当前同名 cask 指向另一个产品，容易误装。
- 把 `main` 中的版本号做成已发布版本徽章；Release 徽章必须动态读取 GitHub Releases。

## 七、图片准则与本次资产

### 准则

- 产品截图必须来自真实构建，优先成功状态；不得用设计稿伪装成运行结果。
- 开启隐私模式，隐藏真实项目名、用户名、路径、Token、凭证和管理后台。
- 排除“服务不可用”、登录错误、空白骨架等不适合作为产品证据的画面。
- README 图采用仓库相对路径并提供有意义的 `alt` 文本。
- 三列图在窄屏会缩小，单图分析界面保留独立宽屏展示。
- Social Preview 固定为 1280×640、纯色背景、小于 1 MB；Hero 保留 1600×900 宽屏版本。

### 本次资产清单

| 文件 | 用途 | 尺寸 |
| --- | --- | --- |
| `docs/assets/github/hero.webp` | README 首屏 Hero | 1600×900 |
| `docs/assets/github/dashboard-hud.png` | HUD 主题 | 923×768 |
| `docs/assets/github/dashboard-led.png` | LED 主题 | 923×768 |
| `docs/assets/github/dashboard-classic.png` | 经典主题 | 923×768 |
| `docs/assets/github/analysis-mode.png` | AI Token 分析模式 | 923×768 |
| `docs/assets/github/website-home.png` | 公开官网 | 1265×712 |
| `docs/assets/github/social-preview.jpg` | GitHub Social Preview | 1280×640 |

本轮没有为了凑数量伪造刘海或 Skills 独立截图：macOS 辅助功能未稳定暴露这些瞬时界面，且全屏捕获可能带入工作区隐私。后续应在干净桌面与演示数据环境中补拍，再替换图集，而不是拼接虚假状态。

## 八、Topics、标签与社区分类

### Topics

建议 15 个（低于 GitHub 的 20 个上限）：

`macos`、`swift`、`swiftui`、`menu-bar`、`menubar-app`、`macos-app`、`system-monitor`、`apple-silicon`、`cpu-monitor`、`memory-monitor`、`smc`、`ai-usage`、`token-usage`、`claude-code`、`codex-cli`

### 标签

| 类别 | 标签 | 色彩策略 |
| --- | --- | --- |
| 类型 | `bug`、`enhancement`、`documentation` | 红、青、蓝 |
| 风险 | `privacy`、`security` | 紫、深红 |
| 区域 | `area: system`、`area: ai-usage`、`area: quota`、`area: cleanup`、`area: skills`、`area: ui`、`area: website` | 统一浅蓝 |
| 社区状态 | `needs triage`、`good first issue`、`help wanted` | 灰、紫、绿 |

原计划写“六个 `area:*`”但同时列出了七个真实产品区域。本方案按产品结构保留七个，避免把官网或 UI 问题塞进不相关分类。仓库中的 `.github/labels.yml` 作为名称、说明与颜色的可审查来源；线上标签需通过 GitHub 设置同步。

## 九、上线检查

- [ ] `README.md` 与 `README.zh-CN.md` 首屏互链，主张一致。
- [ ] Release 徽章动态读取，正文明确 v0.9.0 / v0.10 边界。
- [ ] 所有相对链接和图片路径在分支上存在。
- [ ] Social Preview 为 1280×640 且小于 1 MB。
- [ ] README 在 GitHub PR 页面上检查桌面和窄屏布局。
- [ ] CI 通过，且本任务没有修改 Swift 产品逻辑或发布新版本。
- [ ] 仓库 About 使用准确简介与官网链接。
- [ ] Topics、标签和 Social Preview 已在线同步；无法登录时明确标记为阻塞项。
- [ ] PR 保持未合并，由维护者最后确认。

## 十、仓库元数据建议值

- **Description**：`Native macOS menu bar monitor for system health, Claude Code & Codex usage, cost estimates, quotas, and local-first tools.`
- **Website**：`https://macpulse-monitor.peaceaii.chatgpt.site`
- **Social Preview**：`docs/assets/github/social-preview.jpg`
