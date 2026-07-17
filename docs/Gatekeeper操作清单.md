# MacPulse 正式发布：需要你操作的 4 件事

这份清单只包含必须由账户持有者确认、输入凭据或保管私钥的步骤。
不要把 Apple ID 密码、App 专用密码、Team ID 凭据、`.p12` 或 Sparkle 私钥发到聊天中。

## 1. 创建空的 GitHub 公开仓库

GitHub 已确认当前连接账号为 `hepinga`。请创建：

- Owner：`hepinga`
- Repository name：`MacPulse`
- Visibility：`Public`
- **不要**勾选 README、`.gitignore` 或 License，保持空仓库

完成后只需回复：`GitHub 空仓库已创建`。

另外，本机 GitHub CLI 已安装。如果 Codex 已发起设备登录，请在
<https://github.com/login/device> 输入终端显示的一次性代码并批准 `hepinga`；不要把 GitHub token 发到聊天中。

## 2. 创建 Developer ID Application 证书

1. 打开 Xcode → Settings → Accounts。
2. 选中 Apple Developer Program 账号。
3. Manage Certificates… → `+` → Developer ID Application。
4. 等待证书出现在列表中。

完成后在你自己的终端执行：

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

只要回复：`Developer ID 已创建`，不要粘贴证书私钥。

## 3. 存储 Apple 公证凭据

先在 Apple Account 生成 App 专用密码，再在你自己的终端执行：

```sh
cd '<MacPulse 源码目录>'
./scripts/setup-notary.sh
```

脚本会交互读取 Apple ID、Team ID 和 App 专用密码，并存到本机钥匙串的
`macpulse-notary` profile。请在本机直接输入，不要通过聊天传递。

完成后只需回复：`macpulse-notary 已配置`。

## 4. 备份两把发布私钥

### Developer ID

在“钥匙串访问”中展开 Developer ID Application 证书，连同私钥导出为强密码保护的 `.p12`，
存入加密密码库或离线介质。

### Sparkle EdDSA

本机已生成 Sparkle 私钥。在安全的临时目录导出：

```sh
mkdir -m 700 /private/tmp/macpulse-key-backup
cd '<MacPulse 源码目录>'
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /private/tmp/macpulse-key-backup/sparkle-ed25519-private-key.txt
```

立即把文件放入加密密码库/加密离线介质，确认可恢复后，用 Finder 把临时文件移入废纸篓并清空。
不要粘贴或截图私钥内容。

全部完成后回复：`Developer ID 和 Sparkle 私钥已备份`。

## 完成后

你只要回复下面四项的完成状态，不需要发任何密码或 token：

```text
GitHub 空仓库已创建
Developer ID 已创建
macpulse-notary 已配置
Developer ID 和 Sparkle 私钥已备份
```

之后的仓库推送、标签、签名、公证、GitHub Release、下载站/appcast 更新以及更新链验证都由 Codex 继续完成。
