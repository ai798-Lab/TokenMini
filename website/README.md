# MacPulse 下载站

MacPulse 公开 Beta 的固定 HTTPS 下载入口，使用 vinext 和 Sites 托管。站点不接入通用遥测或分析脚本；只有用户主动使用 Google 登录加入排行榜后，才会把每日 Token 与 API 等价费用汇总写入 D1。

- 生产站：<https://macpulse-monitor.peaceaii.chatgpt.site>
- 下载页：`app/page.tsx`
- 公开榜单：`app/rankings/page.tsx`（无需登录）
- 隐私说明：`app/privacy/page.tsx`
- 轻量后台：`app/admin/page.tsx`（仅 `ADMIN_EMAILS` 白名单）
- API：`worker/api.ts`
- D1 迁移：`drizzle/0001_rankings.sql`
- 样式：`app/globals.css`
- Sparkle feed：`public/appcast.xml`

排行榜仅存用户标识、名称显示方式、上海时区每日总 Token、费用汇总、价格表版本与 App 版本。不会存会话正文、项目名、路径、模型明细或第三方 AI 凭证。后台的用户数、DAU 与留存都只代表已加入排行榜的成员，不代表全部 MacPulse 用户。

## 本地验证

```bash
npm ci
npm run lint
npm test
npm run dev # 自动把 drizzle/0001_rankings.sql 应用到本地 D1 后启动
```

Google OAuth 与 D1 未配置时，下载页、隐私页和本地 App 功能仍可正常使用；排行榜接口会显示未配置或暂时不可用，不应阻断本地监控。

正式发布时，先上传已公证的 GitHub Release DMG，再将根目录 `dist/appcast.xml`替换到
`public/appcast.xml`，重新构建并部署。不要手工编辑已签名 appcast。
