# TokenMini 品牌与域名

确认日期：2026-09-20。

- 正式品牌：TokenMini（原名 MacPulse）。
- 主域名：https://tokenmini.cc/
- 兼容入口：https://www.tokenmini.cc/
- 注册商：Porkbun；继续使用其现有 DNS，不迁移名称服务器。
- 英文定位：Free AI Usage Monitor for Mac。
- 中文定位：免费的 Mac AI 用量监控工具。
- 当前能力：Claude Code / Codex 用量、API 等价费用、额度与 Mac 状态；Token 中转、余额、付费扣款不是当前功能。

## 2026-09-20 官网更新

首页、隐私说明、社区排行和运营页的展示品牌统一为 TokenMini。搜索标题、规范网址、站点地图及 robots.txt 使用 tokenmini.cc。默认域名继续保留。官网依旧使用既有 Sites 项目与数据库，未修改排行榜认证、用户信息或上传范围。

当前公开安装包仍为 MacPulse 0.10.0；官网明确展示更名关系和安装包真实名称。此次未构建、安装或发布新的桌面应用版本，未替换已经签名的 appcast。后续桌面更名必须从包含已验收维护修复的版本合并，保留 bundle ID、偏好设置、钥匙串及旧版更新兼容，并单独验证升级与安装。

## 实际验证

- tokenmini.cc 与 www.tokenmini.cc：托管平台域名和 HTTPS 证书均 active，真实浏览器可打开 TokenMini 页面。
- 真实页面：1440×1000 桌面、390×844 窄屏检查通过；无横向溢出。
- 路径：新域名首页 → 社区排行 → API 等价费用切换 → 返回首页 → 隐私页；www 首页 → 免费下载 → GitHub Releases。
- 公开榜单正常返回空状态，未添加虚构记录。未进行新的真实账号登录。
- 构建、lint 及现有 17 项网站测试通过。

## 源码边界

本次工作区基于公开 origin/main，未覆盖其他工作区的本地修改。网站源码在 website/，发布使用现有 Sites 专用源码库；本仓库中的同一份更改用于后续维护。

## 0.11.0 品牌统一

正式对外名称 TokenMini；本轮官网仍以免费 Token 监控台为主，不展示 Token 购买或预售入口。域名继续为 tokenmini.cc。四片 Logo 沿用已选定的标准矢量几何，应用图标为深色底、第二片品牌绿；菜单栏采用单色小尺寸修正版。

应用 bundle ID、Swift 模块名、可执行文件内部名称、偏好设置前缀、钥匙串标识及 macpulse 回调保持兼容。外部应用包名改为 TokenMini.app，新增 tokenmini 回调别名。本次恢复并纳入此前本机 0.10.1 的维护修复，避免更名回退功能。
