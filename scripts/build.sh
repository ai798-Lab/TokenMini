#!/bin/zsh
# 构建 MacPulse.app:SPM 编译 release 二进制 → 组装 .app bundle → ad-hoc 签名
#
# 注意:本机 CLT(Swift 6.0.3)安装损坏 —— 存在两个旧版本残留文件,
# 会导致任何 swift build 失败。下面的 workaround 已在本机实测通过。
# 永久修复(需 sudo,修好后可删除 workaround 段):
#   sudo rm /Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface
#   sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
set -euo pipefail
cd "$(dirname "$0")/.."
PROJ_DIR="$(pwd)"

APP_NAME="TokenMini"
EXECUTABLE_NAME="MacPulse"
DISPLAY_NAME="TokenMini"
BUNDLE_ID="com.liangheping.macpulse"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"
VERSION="${1:-0.11.0}"
BUILD_NUMBER="${2:-5}"
SITE_URL="${MACPULSE_SITE_URL:-https://tokenmini.cc}"
UPDATE_FEED_URL="${MACPULSE_UPDATE_FEED_URL:-${SITE_URL}/appcast.xml}"
SOURCE_URL="${MACPULSE_SOURCE_URL:-https://github.com/ai798-Lab/TokenMini}"
SPARKLE_KEY_FILE="Config/SparklePublicKey.txt"
SPARKLE_FRAMEWORK_SOURCE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

if [[ ! "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "错误:版本号必须是三段数字,如 0.9.0" >&2
    exit 1
fi
if [[ ! "${BUILD_NUMBER}" =~ '^[1-9][0-9]*$' ]]; then
    echo "错误:构建号必须是递增正整数,如 2" >&2
    exit 1
fi
if [ ! -f "${SPARKLE_KEY_FILE}" ]; then
    echo "错误:缺少 ${SPARKLE_KEY_FILE},请先用 Sparkle generate_keys 生成公钥" >&2
    exit 1
fi
SPARKLE_PUBLIC_KEY="$(tr -d '[:space:]' < "${SPARKLE_KEY_FILE}")"

# ===== CLT 损坏 workaround(无 sudo;修好 CLT 后此段自动无害)=====
EXTRA_FLAGS=()
if [ -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap ] && \
   ls /Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface >/dev/null 2>&1; then
    WORK="$PROJ_DIR/.clt-fix"
    if [ ! -d "$WORK/swiftpm-libs" ]; then
        echo "==> 检测到损坏的 CLT,生成无 sudo workaround(.clt-fix/)"
        mkdir -p "$WORK/swiftpm-libs" "$WORK/inc"
        cp -R /Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI "$WORK/swiftpm-libs/ManifestAPI"
        cp -R /Library/Developer/CommandLineTools/usr/lib/swift/pm/PluginAPI  "$WORK/swiftpm-libs/PluginAPI"
        rm "$WORK/swiftpm-libs/ManifestAPI/PackageDescription.swiftmodule/"*.private.swiftinterface
        printf '// masked stale duplicate\n' > "$WORK/inc/empty.modulemap"
        cat > "$WORK/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [
  { "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap",
    "type": "file", "external-contents": "$WORK/inc/empty.modulemap" } ] }
EOF
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$WORK/swiftpm-libs"
    # 必须走 -Xswiftc -vfsoverlay(-Xcc 不行:swiftinterface 重建子任务不继承 -Xcc)
    EXTRA_FLAGS=(-Xswiftc -vfsoverlay -Xswiftc "$WORK/overlay.yaml")
fi
# ===== workaround 结束 =====

echo "==> swift build -c release"
swift build -c release "${EXTRA_FLAGS[@]}"

echo "==> 组装 ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${APP_DIR}/Contents/Frameworks"
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

if [ ! -d "${SPARKLE_FRAMEWORK_SOURCE}" ]; then
    echo "错误:未找到 Sparkle.framework,请先运行 swift package resolve" >&2
    exit 1
fi
# ditto 会保留 Sparkle.framework 的版本化符号链接与可执行权限。
ditto "${SPARKLE_FRAMEWORK_SOURCE}" "${APP_DIR}/Contents/Frameworks/Sparkle.framework"

cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Liang Heping · MIT License</string>
    <key>MacPulseHomepageURL</key><string>${SITE_URL}</string>
    <key>MacPulsePrivacyURL</key><string>${SITE_URL}/privacy</string>
    <key>MacPulseSourceURL</key><string>${SOURCE_URL}</string>
    <key>SUFeedURL</key><string>${UPDATE_FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SURequireSignedFeed</key><true/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
        <key>CFBundleURLSchemes</key><array><string>macpulse</string><string>tokenmini</string></array>
    </dict></array>
</dict>
</plist>
PLIST

# 图标:设计源文件(logo icon.svg)比 icns 新就自动重新生成。
# 没这一步的话,改了设计稿、构建出来的还是旧图标,看着像"图标缓存没刷新",实际是根本没重新生成过。
if [ -f "logo icon.svg" ] && [ -f "scripts/make-icon.swift" ]; then
    if [ ! -f "Resources/AppIcon.icns" ] || [ "logo icon.svg" -nt "Resources/AppIcon.icns" ]; then
        echo "==> logo icon.svg 有更新,重新生成 AppIcon.icns"
        ICON_TMP="$(mktemp -d)"
        swift scripts/make-icon.swift "${ICON_TMP}/AppIcon.iconset" >/dev/null
        iconutil -c icns "${ICON_TMP}/AppIcon.iconset" -o "Resources/AppIcon.icns"
        rm -rf "${ICON_TMP}"
    fi
fi

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP_DIR}/Contents/Info.plist"
fi

if [ -f "THIRD_PARTY_NOTICES.txt" ]; then
    cp "THIRD_PARTY_NOTICES.txt" "${APP_DIR}/Contents/Resources/"
fi

cp "Resources/Brand/HeaderMark.pdf" "Resources/Brand/MenuBarMark.pdf" "${APP_DIR}/Contents/Resources/"

cp "Resources/Prism/PrismCore.png" "${APP_DIR}/Contents/Resources/"

ditto "${BUILD_DIR}/MacPulse_MacPulse.bundle" "${APP_DIR}/Contents/Resources/MacPulse_MacPulse.bundle"
ditto "Resources/ThirdParty" "${APP_DIR}/Contents/Resources/ThirdParty"

echo "==> ad-hoc 签名"
codesign --force -s - "${APP_DIR}"
codesign --verify --strict --deep "${APP_DIR}"

echo "==> 完成: ${APP_DIR} (版本 ${VERSION},构建 ${BUILD_NUMBER})"
