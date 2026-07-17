#!/bin/zsh
# 正式签名/公证后，推送干净历史并创建未宣传的 GitHub Pre-release。
# 不会把 Pre-release 转为正式版；必须先验证 Sparkle 更新链。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: ./scripts/publish-github-prerelease.sh <版本,如 0.10.0> <递增构建号,如 3>}"
BUILD_NUMBER="${2:?用法: ./scripts/publish-github-prerelease.sh <版本,如 0.10.0> <递增构建号,如 3>}"
REPOSITORY="${GITHUB_REPOSITORY:-hepinga/MacPulse}"
TAG="v${VERSION}"
DMG="dist/MacPulse-${VERSION}.dmg"
CHECKSUM="${DMG}.sha256"
NOTES="release-notes/${VERSION}.md"

if ! command -v gh >/dev/null 2>&1; then
    echo "错误:未安装 GitHub CLI(gh)" >&2
    exit 1
fi
gh auth status --hostname github.com >/dev/null
gh repo view "${REPOSITORY}" --json nameWithOwner >/dev/null

./scripts/check-release-prerequisites.sh
./scripts/preflight-release.sh

echo "==> 构建、Developer ID 签名并公证 ${VERSION} (${BUILD_NUMBER})"
./scripts/release.sh "${VERSION}" "${BUILD_NUMBER}"

HEAD_SHA="$(git rev-parse HEAD)"
if git rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null; then
    if [ "$(git rev-list -n 1 "${TAG}")" != "${HEAD_SHA}" ]; then
        echo "错误:本地 ${TAG} 已指向其他提交" >&2
        exit 1
    fi
else
    git tag -a "${TAG}" -m "MacPulse ${VERSION} public beta"
fi

REMOTE_MAIN="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
if [ -z "${REMOTE_MAIN}" ]; then
    git push --set-upstream origin HEAD:main
elif [ "${REMOTE_MAIN}" != "${HEAD_SHA}" ]; then
    if ! git merge-base --is-ancestor "${REMOTE_MAIN}" "${HEAD_SHA}"; then
        echo "错误:当前提交不是远端 main 的快进后继，停止覆盖" >&2
        exit 1
    fi
    git push origin HEAD:main
fi

REMOTE_TAG_COMMIT="$(git ls-remote origin "refs/tags/${TAG}^{}" | awk '{print $1}')"
if [ -n "${REMOTE_TAG_COMMIT}" ] && [ "${REMOTE_TAG_COMMIT}" != "${HEAD_SHA}" ]; then
    echo "错误:远端 ${TAG} 已指向其他提交" >&2
    exit 1
fi
if [ -z "${REMOTE_TAG_COMMIT}" ]; then
    git push origin "${TAG}"
fi

if gh release view "${TAG}" --repo "${REPOSITORY}" >/dev/null 2>&1; then
    gh release upload "${TAG}" "${DMG}" "${CHECKSUM}" --repo "${REPOSITORY}" --clobber
    gh release edit "${TAG}" --repo "${REPOSITORY}" --prerelease \
        --title "MacPulse ${VERSION} Public Beta" --notes-file "${NOTES}"
else
    gh release create "${TAG}" "${DMG}" "${CHECKSUM}" \
        --repo "${REPOSITORY}" --verify-tag --prerelease \
        --title "MacPulse ${VERSION} Public Beta" --notes-file "${NOTES}"
fi

echo "==> GitHub Pre-release 已准备: https://github.com/${REPOSITORY}/releases/tag/${TAG}"
echo "==> 下一步:部署 dist/appcast.xml，验证 0.8.99 → ${VERSION}，再转正式 Release"
