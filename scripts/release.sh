#!/bin/zsh
# MacPulse 官网分发版：构建 → 嵌套签名 → 公证 → DMG → Sparkle appcast。
#
# 用法:
#   ./scripts/release.sh 0.10.0 3
#   SKIP_NOTARIZE=1 ./scripts/release.sh 0.10.0 3  # 仅验证本地打包，不能公开分发
#   SKIP_APPCAST=1 ./scripts/release.sh 0.8.99 1  # 公证内测旧版，不发布 feed
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: ./scripts/release.sh <版本,如 0.10.0> <递增构建号,如 3>}"
BUILD_NUMBER="${2:?用法: ./scripts/release.sh <版本,如 0.10.0> <递增构建号,如 3>}"
APP_NAME="TokenMini"
EXECUTABLE_NAME="MacPulse"
APP_DIR="dist/${APP_NAME}.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-macpulse-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_APPCAST="${SKIP_APPCAST:-0}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-ai798-Lab/TokenMini}"
SITE_URL="${MACPULSE_SITE_URL:-https://tokenmini.cc}"
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
PRIVATE_DIR="dist/private"
UPDATES_DIR="dist/updates"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
RELEASE_NOTES="release-notes/${VERSION}.md"

if [[ ! "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || \
   [[ ! "${BUILD_NUMBER}" =~ '^[1-9][0-9]*$' ]]; then
    echo "错误:版本必须是 0.10.0 形式,构建号必须是递增正整数" >&2
    exit 1
fi
if [ ! -f "${RELEASE_NOTES}" ]; then
    echo "错误:缺少 ${RELEASE_NOTES}" >&2
    exit 1
fi
if [ ! -x "${SPARKLE_BIN}/generate_appcast" ]; then
    echo "错误:缺少 Sparkle 发布工具,请先运行 swift package resolve" >&2
    exit 1
fi

if [ "${SKIP_NOTARIZE}" != "1" ]; then
    ./scripts/preflight-release.sh
fi

IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/')" || true
if [ -z "${IDENTITY}" ]; then
    if [ "${SKIP_NOTARIZE}" = "1" ]; then
        IDENTITY="-"
        echo "==> 无 Developer ID 证书，干跑模式使用 ad-hoc 签名"
    else
        echo "错误:钥匙串中没有 Developer ID Application 证书。" >&2
        echo "请按维护者私有发布手册完成证书和 macpulse-notary 配置。" >&2
        exit 1
    fi
else
    echo "==> 签名身份: ${IDENTITY}"
fi

./scripts/build.sh "${VERSION}" "${BUILD_NUMBER}"

SPARKLE_FRAMEWORK="${APP_DIR}/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="${SPARKLE_FRAMEWORK}/Versions/B"

sign_nested() {
    local target="$1"
    shift
    [ -e "${target}" ] || return 0
    if [ "${IDENTITY}" = "-" ]; then
        codesign --force --options runtime -s - \
            --preserve-metadata=identifier,entitlements "$@" "${target}"
    else
        codesign --force --options runtime --timestamp -s "${IDENTITY}" \
            --preserve-metadata=identifier,entitlements "$@" "${target}"
    fi
}

echo "==> 由内到外签名 Sparkle 与主应用"
sign_nested "${SPARKLE_VERSION}/XPCServices/Installer.xpc"
sign_nested "${SPARKLE_VERSION}/XPCServices/Downloader.xpc"
sign_nested "${SPARKLE_VERSION}/Autoupdate"
sign_nested "${SPARKLE_VERSION}/Updater.app"
sign_nested "${SPARKLE_FRAMEWORK}"
sign_nested "${APP_DIR}"

codesign --verify --strict --deep --verbose=2 "${APP_DIR}"
if codesign -d --entitlements :- "${APP_DIR}" 2>&1 | grep -q 'com.apple.security.get-task-allow'; then
    echo "错误:发布包含 get-task-allow entitlement" >&2
    exit 1
fi
ARCHS="$(lipo -archs "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}")"
if [ "${ARCHS}" != "arm64" ]; then
    echo "错误:主程序架构应为 arm64,实际为 ${ARCHS}" >&2
    exit 1
fi

mkdir -p "${PRIVATE_DIR}"
DSYM_DIR="${PRIVATE_DIR}/${APP_NAME}-${VERSION}.dSYM"
DSYM_ZIP="${PRIVATE_DIR}/${APP_NAME}-${VERSION}-dSYM.zip"
rm -rf "${DSYM_DIR}"
rm -f "${DSYM_ZIP}"
dsymutil "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}" -o "${DSYM_DIR}"
ditto -c -k --keepParent "${DSYM_DIR}" "${DSYM_ZIP}"

if [ "${SKIP_NOTARIZE}" != "1" ]; then
    echo "==> 公证 .app"
    ZIP_PATH="dist/${APP_NAME}-${VERSION}-notarize.zip"
    rm -f "${ZIP_PATH}"
    ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
    xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
    rm -f "${ZIP_PATH}"
    xcrun stapler staple "${APP_DIR}"
    spctl --assess --type exec -v "${APP_DIR}"
else
    echo "==> SKIP_NOTARIZE=1，跳过 .app 公证"
fi

echo "==> 打包 ${DMG_PATH}"
STAGING="$(mktemp -d)"
ditto "${APP_DIR}" "${STAGING}/${APP_NAME}.app"
ln -s /Applications "${STAGING}/Applications"
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" -ov -format UDZO -quiet "${DMG_PATH}"
rm -rf "${STAGING}"

if [ "${IDENTITY}" = "-" ]; then
    codesign --force -s - "${DMG_PATH}"
else
    codesign --force --timestamp -s "${IDENTITY}" "${DMG_PATH}"
fi
if [ "${SKIP_NOTARIZE}" != "1" ]; then
    echo "==> 公证 DMG"
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
fi

shasum -a 256 "${DMG_PATH}" > "${CHECKSUM_PATH}"

if [ "${SKIP_APPCAST}" != "1" ]; then
    echo "==> 生成签名 Sparkle appcast"
    mkdir -p "${UPDATES_DIR}"
    rm -f "${UPDATES_DIR}/${APP_NAME}-${VERSION}.dmg" "${UPDATES_DIR}/${APP_NAME}-${VERSION}.md"
    cp "${DMG_PATH}" "${UPDATES_DIR}/"
    cp "${RELEASE_NOTES}" "${UPDATES_DIR}/${APP_NAME}-${VERSION}.md"
    DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPOSITORY}/releases/download/v${VERSION}/"
    # Generate from this exact archive in a fresh directory. Reusing an old feed
    # can retain another build under the same immutable version download URL.
    APPCAST_STAGE="$(mktemp -d)"
    cp "${DMG_PATH}" "${APPCAST_STAGE}/"
    cp "${RELEASE_NOTES}" "${APPCAST_STAGE}/${APP_NAME}-${VERSION}.md"
    "${SPARKLE_BIN}/generate_appcast" \
        --download-url-prefix "${DOWNLOAD_PREFIX}" \
        --link "${SITE_URL}" \
        --embed-release-notes \
        --maximum-deltas 0 \
        -o "${APPCAST_STAGE}/appcast.xml" \
        "${APPCAST_STAGE}"
    cp "${APPCAST_STAGE}/appcast.xml" "${UPDATES_DIR}/appcast.xml"
    cp "${APPCAST_STAGE}/appcast.xml" "dist/appcast.xml"
    rm -rf "${APPCAST_STAGE}"

    if ! grep -q "${DOWNLOAD_PREFIX}${APP_NAME}-${VERSION}.dmg" "dist/appcast.xml"; then
        echo "错误:appcast 未指向不可变 GitHub Release 地址" >&2
        exit 1
    fi
else
    echo "==> SKIP_APPCAST=1，跳过 Sparkle feed 生成"
fi

echo ""
echo "==> 发布产物已生成"
echo "    DMG:       ${DMG_PATH}"
echo "    SHA-256:   ${CHECKSUM_PATH}"
if [ "${SKIP_APPCAST}" != "1" ]; then
    echo "    Appcast:   dist/appcast.xml"
fi
echo "    发布说明: ${RELEASE_NOTES}"
echo "    dSYM 私存: ${DSYM_ZIP}"
if [ "${SKIP_NOTARIZE}" = "1" ]; then
    echo "    注意:当前是干跑包，不可公开分发。"
fi
