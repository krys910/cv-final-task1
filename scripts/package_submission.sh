#!/usr/bin/env bash
# 打包代码与报告素材（不含大体积 outputs/external）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP=$(date +%Y%m%d)
OUT="$ROOT/dist/hw3_submission_${STAMP}"
mkdir -p "$OUT"
rsync -a \
  --exclude '.git' --exclude '.venv' --exclude 'external' --exclude 'data' \
  --exclude 'outputs' --exclude 'dist' --exclude '__pycache__' --exclude '*.log' \
  "$ROOT/" "$OUT/hw3/"
mkdir -p "$OUT/figures"
cp -r "$ROOT/report/figures/"* "$OUT/figures/" 2>/dev/null || true
cp "$ROOT/outputs/fused/walkthrough.mp4" "$OUT/" 2>/dev/null || echo "提示: 本地无 walkthrough.mp4，请从服务器 scp"
(cd "$ROOT/dist" && zip -rq "hw3_submission_${STAMP}.zip" "hw3_submission_${STAMP}")
echo "打包完成: $ROOT/dist/hw3_submission_${STAMP}.zip"
