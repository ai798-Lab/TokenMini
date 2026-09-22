# TokenMini 官网中英文版（2026-09-22）

本地预览：http://localhost:4328/

## 交付

- 首页、社区排行和隐私说明提供英文与简体中文；右上角 EN / 中文 即时切换。
- 没有偏好时默认英文，不根据浏览器语言自动改成中文。
- 主动选择后使用一方 Cookie 保存一年；刷新和内页跳转保留选择。Cookie 被禁用时，当前页面仍能即时切换，但后续访问可能无法记忆。
- 页面标题、描述、HTML 语言、按钮、排行加载/失败/空状态及数字格式跟随语言。
- 保留 API 等价估算、本地数据处理与自愿加入排行的说明。
- 英文调整为自然的产品文案，并独立调整标题尺寸和移动端排版。

## 来源与范围

本任务最初位于旧 MacPulse 提交 4764f3c，已切换至 TokenMini 基线 df2bc20 的独立分支 codex/website-bilingual。
网站视觉沿用 codex/tokenmini-kinetic-hero 工作区当时最新的 Kinetic 页面、样式、静态主视觉和全站动效控件。该设计尚未提交在 df2bc20 中，因此本分支包含继承的视觉文件。原工作区未修改。
仅修改官网。初次交付为本地预览；用户随后确认该版并授权发布，线上记录见文末。未修改桌面应用、安装包或更新源，未向生产数据库写入信息。

## 验证结果

- npm test：生产构建及 23 项测试全部通过。覆盖缺省英文、无效语言回退、中文首屏服务端渲染、首页/排行/隐私和原有后端回归。
- npm run lint：通过，无警告。
- 前端 TypeScript 检查：通过。
- 全仓 tsc --noEmit：仍受既有 tests/worker-api.test.ts、tests/worker-lifecycle.test.ts 和 worker/types.ts 类型错误影响，包含 .ts 导入设置、Fetcher 环境类型和测试查询结果可能为空；这些文件未改动，未将全仓类型检查记为通过。
- 浏览器实际点击：首次英文 → 中文 → 刷新仍中文 → 进入隐私页仍中文 → 切回英文 → 进入排行页仍英文，均通过。
- 排行页 Token / API 等价费用切换、费用说明和中英文空榜提示正常。
- 键盘 Enter 可切换语言；HTML lang、页面标题和选中状态同步。
- 桌面 1280 宽、手机 320/390 宽已检查；所检查页面 scrollWidth 与视口一致，未发现横向溢出。英文首页正文未发现中文残留。
- 浏览器 error/warn 日志为空。

本地排行数据库为空；本次验证空榜展示，不代表已经验证生产排行榜的数据内容或真实登录。

## 维护入口

- website/app/translations.ts：中英文文案。
- website/app/language.tsx：全站语言状态与切换按钮。
- website/app/locale-server.ts：服务端语言偏好与页面元信息。
- website/app/language.css：语言切换与双语排版适配。
- website/app/home-content.tsx：首页。
- website/app/privacy/privacy-content.tsx、rankings/rankings-content.tsx：公开内页。

开发启动：在 website 目录运行 npm run dev -- --port 4328。该环境监听 localhost（IPv6），请使用 localhost 链接。

## 首屏字形与图文避让修订（2026-09-22）

- 顶部 TOKENMINI 使用自托管 Archivo Black，字体与 OFL 许可位于 public/fonts；去掉纵向拉伸与右侧小标语，形成完整厚重的横向品牌标题。
- 圆环限定在首屏右侧独立区域；图片区裁剪阻止圆环向上覆盖品牌字，边缘渐隐消除硬切线。
- 首屏文案限制在左侧安全宽度；手机采用文字在上、圆环在下的布局。
- 真实浏览器检查英文与中文的 1920、1440、1024、800、390、320 像素宽度，品牌字均完整且无页面横向溢出；发现的 800 像素英文说明越界已修复并复核，文字至图片区剩余 19.97 像素；390 像素中文文案至图片区为 28.64 像素。
- 调整后生产构建、23 项测试与 ESLint 通过，浏览器未捕获 error/warn。
- 预览截图：masthead-refinement-en.png。

## 正式发布与线上验收（2026-09-22）

- 用户明确批准当前版本后，更新现有公开站点 https://tokenmini.cc；Sites 版本 13，部署状态 succeeded。
- 发布源码提交：51268438ed925345c74d4325d99beb11bcd5b763。
- 版本 ID：appgprj_6a599c457e8c8191b66c966ed83ca95d~appgver_09c63a5af7f88191a6bf973e9505e798。
- 部署 ID：appgdep_6ab23d380d2c8191b161851227c988d4。
- 在现有线上源码的独立目录构建发布；发布前确认 worker、锁文件与 appcast 跟线上一致。发布构建、23 项测试与 ESLint 全部通过。
- 正式域名浏览器验收：首次英文、厚重 Archivo Black 品牌标题、桌面图文分区；切换中文、刷新保留中文、进入隐私和排行榜保留中文；排行榜切回英文及 API 等价费用视图正常。
- 线上榜单返回正常空榜提示。本次没有登录、上传汇总或验证真实用户排行数据。
- 390 像素手机宽度分别检查中英文，图文无重叠，scrollWidth 均等于 390；恢复正常桌面视口并保留英文页面供查看。
- 浏览器未捕获 error/warn。线上截图：live-20260922-en.png。
- 保留现有公开访问范围、下载地址与签名更新源。
