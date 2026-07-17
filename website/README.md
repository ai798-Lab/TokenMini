# MacPulse 下载站

MacPulse 公开 Beta 的固定 HTTPS 下载入口，使用 vinext 和 Sites 托管。站点没有账户、后台业务数据、数据库或分析脚本。

- 生产站：<https://macpulse-monitor.peaceaii.chatgpt.site>
- 页面：`app/page.tsx`
- 样式：`app/globals.css`
- Sparkle feed：`public/appcast.xml`

## 本地验证

```bash
npm install
npm test
npm run dev
```

正式发布时，先上传已公证的 GitHub Release DMG，再将根目录 `dist/appcast.xml`替换到
`public/appcast.xml`，重新构建并部署。不要手工编辑已签名 appcast。
