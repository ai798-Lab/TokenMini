#!/bin/zsh
# 首次公开与每次发版前的静态闸门。
# 只输出命中文件名，不把可能的密钥内容打到终端或 CI 日志。
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT
HISTORY_REF="${PUBLIC_HISTORY_REF:-HEAD}"

SECRET_PATTERN='sk-ant-[A-Za-z0-9_-]{16,}|sk-proj-[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----|"access_token"[[:space:]]*:[[:space:]]*"[A-Za-z0-9._-]{20,}"'
SCAN_GLOBS=(
    --glob '!.git/**'
    --glob '!.build/**'
    --glob '!dist/**'
    --glob '!website/node_modules/**'
    --glob '!website/.next/**'
)

report_file() {
    local title="$1"
    local report_path="$2"
    if [ -s "${report_path}" ]; then
        echo "错误:${title}" >&2
        sort -u "${report_path}" | sed 's/^/  - /' >&2
        failures=$((failures + 1))
    fi
}

echo "==> 检查当前源码树的密钥特征"
rg -I -l -e "${SECRET_PATTERN}" "${SCAN_GLOBS[@]}" . > "${TEMP_DIR}/worktree-secrets" || true
report_file "当前源码树疑似包含凭证" "${TEMP_DIR}/worktree-secrets"

echo "==> 检查当前用户的绝对路径"
PRIVATE_HOME="/Users/${USER}/"
rg -I -l -F "${PRIVATE_HOME}" "${SCAN_GLOBS[@]}" . > "${TEMP_DIR}/worktree-paths" || true
report_file "当前源码树包含私人绝对路径" "${TEMP_DIR}/worktree-paths"

if ! git rev-parse --verify "${HISTORY_REF}^{commit}" >/dev/null 2>&1; then
    echo "错误:无法解析待发布历史 ${HISTORY_REF}" >&2
    exit 1
fi
echo "==> 扫描待发布历史 ${HISTORY_REF}"
for revision in $(git rev-list "${HISTORY_REF}"); do
    git grep -I -l -E "${SECRET_PATTERN}" "${revision}" -- . \
        >> "${TEMP_DIR}/history-secrets" 2>/dev/null || true
    git grep -I -l -F "${PRIVATE_HOME}" "${revision}" -- . \
        >> "${TEMP_DIR}/history-paths" 2>/dev/null || true
    git -c core.quotepath=false ls-tree -r --name-only "${revision}" \
        | rg '(^|/)(会话纪要\.md|交接文档-[^/]*\.md)$' \
        >> "${TEMP_DIR}/history-internal" || true
done
report_file "Git 历史疑似包含凭证" "${TEMP_DIR}/history-secrets"
report_file "Git 历史包含私人绝对路径" "${TEMP_DIR}/history-paths"
report_file "Git 历史包含内部会话或交接纪要" "${TEMP_DIR}/history-internal"

echo "==> 检查开源与发布必需文件"
for required in LICENSE PRIVACY.md SECURITY.md CONTRIBUTING.md CHANGELOG.md \
                THIRD_PARTY_NOTICES.txt Config/SparklePublicKey.txt; do
    if [ ! -s "${required}" ]; then
        echo "错误:缺少 ${required}" >&2
        failures=$((failures + 1))
    fi
done

if [ -n "$(git status --porcelain)" ]; then
    echo "错误:工作区不干净，不得创建发布标签。" >&2
    failures=$((failures + 1))
fi
if ! git remote get-url origin >/dev/null 2>&1; then
    echo "错误:尚未配置 Git origin。" >&2
    failures=$((failures + 1))
fi

if (( failures > 0 )); then
    echo "" >&2
    echo "发布预检失败:${failures} 类问题待处理。首次公开前应在未推送的分支重写历史。" >&2
    exit 1
fi

echo "==> 发布预检通过"
