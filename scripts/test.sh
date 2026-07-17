#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 运行生产代码回归测试"
swift test
