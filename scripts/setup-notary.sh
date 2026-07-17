#!/bin/zsh
# 一次性存储公证凭据(交互式)。运行前先准备好:
#   1. Apple ID 邮箱
#   2. Team ID(developer.apple.com/account 底部 Membership details,10 位字符)
#   3. App 专用密码(account.apple.com → 登录与安全 → App 专用密码 → 生成)
set -euo pipefail

echo "== MacPulse 公证凭据初始化 =="
read "APPLE_ID?Apple ID 邮箱: "
read "TEAM_ID?Team ID(10 位): "
read -s "APP_PW?App 专用密码(输入不回显): "
echo ""

xcrun notarytool store-credentials macpulse-notary \
  --apple-id "${APPLE_ID}" \
  --team-id "${TEAM_ID}" \
  --password "${APP_PW}"

echo ""
echo "==> 凭据已存入钥匙串(profile: macpulse-notary),验证中..."
xcrun notarytool history --keychain-profile macpulse-notary | head -3
echo "==> 完成。之后发版运行: ./scripts/release.sh <版本号> <递增构建号>"
