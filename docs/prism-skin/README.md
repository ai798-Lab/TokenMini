# N3 设计研究与 TokenMini Prism 光核

## 2026-09-21 静态主视觉统一更新

用户确认去掉官网主视觉的逐帧假动效，并要求新皮肤使用官网同款图形。以下记录优先于后面的初版光核资产、尺寸和动效描述；旧生成提示词只作为设计历史保留。

- `Resources/Prism/PrismCore.png` 与 `website/public/brand/prism-core.png` 已替换为官网圆环机械、绿色光束的透明 PNG，1672 × 941，1,818,200 字节。两者与官网原始 `frame-00.png` 字节一致。
- 官网新皮肤展示页的 Hero 与下方机械图改为静态构图，不再漂移、旋转或随滚动移动；其他文字与界面动效保留。已在实际浏览器查看 Hero 与总览演示，图片加载正常，文字和读数可辨识。
- 原生应用继续通过已有 PrismArtwork 读取同名资源，无需改变业务逻辑与主题功能。
- 网页原有 17 项测试、构建和 ESLint 通过。当前预览为 `http://localhost:4317/`。
- 本机应用替换包已使用原 Developer ID 签名并验证；当前运行实例尚未退出，因此尚未覆盖 `/Applications/TokenMini.app`，也尚未完成这次原生图片的实际界面验收。
- 未发布网站、GitHub 新版本或 appcast。


日期：2026-09-21。工作分支：codex/n3-prism-skin。基线：df2bc20（TokenMini 品牌版本）。

## 参考事实与设计判断

本轮直接浏览了 N3 官网及 TXC、Beijing TV 案例页面和画面。N3 官方将自己描述为广播、商业和现场活动的动态设计工作室。这份总结是对这些案例的提炼，不代表其全部作品都采用同一种风格；本轮未对案例视频逐帧分析。

| 观察 | 对应细节 | Prism 的转译 |
| --- | --- | --- |
| 把抽象技术变成有体积的场景 | TXC 使用工业建筑、机械结构、透明体、发光路径呈现数字服务 | 用原创金属与玻璃光核表现不可见的 Token 流动 |
| 主体尺度压过常规版式 | 特写、纵深、前后遮挡、画面边缘裁切让主体具有体量 | 官网巨大光核冲出画面，正文保持真实 HTML，下载入口始终可读 |
| 材质决定细节密度 | 金属倒角、反射、玻璃折射、细小构件和发光边缘形成层次 | 冷银、石墨、光学玻璃、荧光绿、珊瑚红与电蓝反射 |
| 品牌色进入物体和光线 | TXC 官方案例说明以绿色为色彩中心，亮色突出于暗工业环境 | 荧光绿同时进入主视觉、按钮、图表和状态选中态；警告仍使用琥珀和红色 |
| 细小单元组成大型形象 | Beijing TV 画面中大量颗粒/几何单元构成龙等具象主体 | 以细线、分段读数与复杂光核纹理连接微观细节和宏观形象 |
| 强视觉与简明信息形成节奏 | 官网将作品画面放在明显层级，文字说明退为辅助 | 深黑首屏 → 荧光字带 → 可交互界面 → 珊瑚红功能区 → 全幅特效 → 荧光下载区 |

参考来源：[N3 官方](https://n3-design.com/)、[TXC / Tianxingcheng](https://n3-design.com/txc/)、[Beijing TV](https://n3-design.com/beijing_tv2/)。只借鉴设计方法；没有把其作品或标志作为产品资产。

用户明确要求“张扬、整站视觉冲击”。初版克制材质方向已弃用，最终主视觉改为爆裂式轨道光核。

## 已实现

- 新增 Prism 主题，并设为没有既有偏好时的默认主题；明确选择过的经典、HUD、LED 偏好继续保留。
- 本机当前主题已切换为 Prism。
- 菜单面板新增总览、系统、AI 用量、Skills 导航和完整监控台入口。
- 监控台、共享面板、筛选控件、刘海和辅助窗口使用同一套色彩与材质。
- 原生应用主视觉使用缓存图片，不增加持续的三维渲染循环；面板高光随指针移动，尊重减少动态效果。
- 官网采用原创 CGI 资产、视差、缩放/旋转、流动字带；可全站暂停，后台标签页暂停，系统减少动态效果时停用。
- 官网提供总览、额度、系统三种可交互演示，全部明确标为演示数据。
- 隐私页、公开排行页沿用同一深色荧光视觉系统，内容与接口保留。
- 保留已完成的 PDF 高清品牌图标修复，未覆盖其他工作副本。

这是图像与网页动效的组合，不是实时三维模型，也不是逐帧特效视频。

## 资产与生成方式

使用内置图片生成能力；最终项目资产：`Resources/Prism/PrismCore.png` 和 `website/public/brand/prism-core.png`。1536 × 1024，约 2.7 MB。客户端与官网消费同一张原创视觉资产。

最终生成提示词：

> Completely art-direct this ring into a BOLD, EXTRAVAGANT, HIGH IMPACT cinematic broadcast CGI key visual for PRISM, an AI token monitor. The earlier result is much too restrained, calm, grey. Keep precision chrome and optical glass but turn the ring into a spectacular exploded orbital engine: huge interlocking elliptical chrome blades, thick optical glass segments, an incandescent ACID LIME core, vivid hot coral red surfaces, electric cobalt accents, kinetic light traces streaking diagonally through depth. Wide 1536x1024 landscape. The composition has energy and oversized scale, ring occupies the right 65% and breaks the top and right frame, left 35% a dark cinematic void for later live headline. Strong diagonal perspective, controlled motion blur only in streaks, sharp foreground chrome edges, true physical reflections/refractions, monumental sense of depth, highly polished expensive film VFX, maximalist but deliberate color blocking. Deep black background. Not subtle, not tasteful-minimal SaaS. This must feel like the explosive opening title of a future technology broadcast. No typography, no logo, no interface, no frame. Make an original artwork.

## 验收记录

- Swift release 构建通过；已有 36 项测试中 34 项通过，2 项环境/手动启用测试跳过，0 失败。
- 官网生产构建、17 项现有测试、ESLint 通过。
- 桌面 1280 与 1440 宽度、手机 390 宽度实际浏览器检查；手机网格宽度撑开问题已修复，交互控件和标题未再越界。
- 总览→额度→系统展示切换、全站暂停按钮实际点击验证；暂停后 CSS 动画处于 paused。
- 已从 `/Applications/TokenMini.app` 冷启动；同一 Developer ID 签名、主程序与构建产物哈希一致。
- 正式监控台显示 Prism，LED→Prism 实际切换成功；用量自动载入并保留来源、更新时间、未定价模型提示。
- 清理与内存管理正式窗口已确认深色与荧光主题；未执行任何清理操作。
- 首次 Developer ID 验收包因 Sparkle 仍是临时签名而启动失败；已按现有 release.sh 由内到外签名全部组件，随后正常启动。`codesign --verify` 本身不能替代冷启动。
- 本地保留 `dist/TokenMini-before-prism.app` 原应用备份。安装包仍为 0.11.0 (5) 的本机验收构建，未发布新版本、未公证此验收构建、未更新线上 appcast。

## 尚未宣称完成的项目

- 未公开部署或覆盖 tokenmini.cc。
- 未在所有显示器、所有辅助页面、完整菜单弹窗/刘海交互矩阵和系统减少动态效果设置下逐项人工验收。
- 网站本地预览不接入生产排行数据库；本地空/错误提示不代表真实线上榜单状态。

本轮网站预览：`http://127.0.0.1:4317/`。另一个工作副本的官网动效任务仍独立存在；本轮未覆盖其文件或替代其逐帧动画实现。
