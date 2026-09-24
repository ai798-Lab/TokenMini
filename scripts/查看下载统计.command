#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/download-metrics.py
open dist/metrics/index.html
