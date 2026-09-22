# TokenMini 官网（静态版）

这个目录就是 <https://tokenmini.cc> 的全部内容。**没有构建步骤、没有服务端、没有数据库、没有密钥**——
把整个 `site/` 目录原样传到任何静态托管上就能跑。

## 目录说明

```
site/
  index.html          英文首页
  zh/index.html       中文首页
  privacy/index.html  英文隐私说明
  zh/privacy/         中文隐私说明
  styles.css          全站样式（含自托管字体声明）
  motion.js           滚动入场动画 + 首屏动效开关
  appcast.xml         Sparkle 自动更新源（签名文件，禁止手改，见下）
  fonts/              Geist / Geist Mono / Archivo Black，全部自托管
  brand/              品牌资产与首屏视觉
  robots.txt  sitemap.xml
```

## 三条必须知道的规矩

**1. 字体只能自托管，不能换成 Google Fonts CDN。**
`fonts/` 里的字体是自己托管的。一旦改成从 `fonts.googleapis.com` 引入，中国大陆用户会加载失败、
整站掉回系统默认字体。这不是性能问题，是能不能看的问题。

**2. `appcast.xml` 是 Sparkle 签名文件，永远不要手工编辑。**
任何改动——哪怕只改一个 URL 或日期——都会让签名失效，导致所有用户的自动更新中断。
要更新它，只能重新跑 `scripts/release.sh`，或用 Sparkle 的 `generate_appcast` 重新生成并签名。

**3. 改中文页时，英文页要同步改，反之亦然。**
两种语言是两套独立的 HTML 文件，没有共享模板。`/` 和 `/zh/` 通过导航栏的 EN / 中文链接互相跳转，
不依赖 JavaScript，也不依赖 cookie。

## 本地预览

```bash
cd site && python3 -m http.server 8000
# 打开 http://localhost:8000
```

## 这版是怎么来的

原本官网是一个 Next.js(vinext) + Cloudflare Worker + D1 数据库的应用，托管在 OpenAI Sites 上。
该托管按国家封锁——实测伊朗、俄罗斯节点返回 HTTP 403，中国大陆在同一份名单上，
导致国内用户完全打不开官网。

2026-09-22 迁出时做了静态化：版式、文案、字体、视觉资产全部沿用原设计，只做了三件事——
去掉框架运行时、语言切换从 cookie 改成两套页面、移除已下线的排行榜入口。

排行榜、Google 登录与管理后台的完整代码保留在 `website/` 目录和 `codex/website-bilingual` 分支里，
哪天要重新启用，从那里接回来。
