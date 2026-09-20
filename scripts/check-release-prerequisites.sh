#!/bin/zsh
# 只读验证需要账户持有者完成的发布前置，不输出任何密钥。
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
EXPECTED_REPOSITORY="${GITHUB_REPOSITORY:-ai798-Lab/TokenMini}"
EXPECTED_PUBLIC_KEY="$(tr -d '[:space:]' < Config/SparklePublicKey.txt)"

pass() { echo "通过: $1"; }
fail() { echo "待完成: $1" >&2; failures=$((failures + 1)); }

if security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
    pass "Developer ID Application 证书"
else
    fail "Developer ID Application 证书"
fi

if xcrun notarytool history --keychain-profile macpulse-notary >/dev/null 2>&1; then
    pass "macpulse-notary 公证凭据"
else
    fail "macpulse-notary 公证凭据"
fi

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [ "${ORIGIN_URL}" = "https://github.com/${EXPECTED_REPOSITORY}.git" ] || \
   [ "${ORIGIN_URL}" = "git@github.com:${EXPECTED_REPOSITORY}.git" ]; then
    pass "Git origin = ${EXPECTED_REPOSITORY}"
else
    fail "Git origin 应为 ${EXPECTED_REPOSITORY}"
fi

if git ls-remote "https://github.com/${EXPECTED_REPOSITORY}.git" >/dev/null 2>&1; then
    pass "GitHub 仓库可访问"
else
    fail "GitHub 空仓库尚未创建或当前不可访问"
fi

ACTUAL_PUBLIC_KEY="$(.build/artifacts/sparkle/Sparkle/bin/generate_keys -p 2>/dev/null || true)"
if [ -n "${ACTUAL_PUBLIC_KEY}" ] && [ "${ACTUAL_PUBLIC_KEY}" = "${EXPECTED_PUBLIC_KEY}" ]; then
    pass "Sparkle EdDSA 钥匙串私钥与内置公钥匹配"
else
    fail "Sparkle EdDSA 钥匙串私钥与内置公钥不匹配"
fi

if (( failures > 0 )); then
    echo "" >&2
    echo "发布前置尚有 ${failures} 项待完成。请按维护者私有发布手册处理。" >&2
    exit 1
fi

echo "==> 所有账户级发布前置已通过"
