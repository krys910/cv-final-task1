#!/usr/bin/env bash
# 背景场景: Mip-NeRF 360 + 2DGS
# 用法: bash scripts/04_background_2dgs.sh [场景名，默认 garden]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/utils/wandb_env.sh"
SCENE="${1:-garden}"
DATA="$ROOT/data/background/$SCENE"
OUT="$ROOT/outputs/background"
DGS="$ROOT/external/2d-gaussian-splatting"

mkdir -p "$ROOT/data/background" "$OUT"

if [[ ! -d "$DATA/images" ]]; then
  echo "=== 下载 Mip-NeRF 360 数据集 ==="
  echo "请手动下载并解压到 $ROOT/data/background/"
  echo "URL: https://storage.googleapis.com/gresearch/refraw360/360_v2.zip"
  echo "解压后应有: data/background/garden/images/ ..."
  exit 1
fi

cd "$DGS"
ITER_PLY="$OUT/model/point_cloud/iteration_30000/point_cloud.ply"

if [[ -f "$ITER_PLY" ]]; then
  echo "=== 训练已完成 (iteration_30000)，跳过 train ==="
else
  echo "=== 2DGS 训练背景场景: $SCENE ==="
  python train.py -s "$DATA" -m "$OUT/model" --iterations 30000
fi

echo "=== 导出点云 ==="
if [[ -f "$ITER_PLY" ]]; then
  cp "$ITER_PLY" "$OUT/point_cloud.ply"
  echo "已从 checkpoint 复制点云（跳过 render.py，避免 OOM）"
elif python render.py -m "$OUT/model" --skip_train; then
  cp "$OUT/model/point_cloud/iteration_30000/point_cloud.ply" "$OUT/point_cloud.ply"
else
  echo "警告: render.py 失败，尝试直接复制 iteration PLY"
  [[ -f "$ITER_PLY" ]] && cp "$ITER_PLY" "$OUT/point_cloud.ply"
fi

echo "完成: $OUT/point_cloud.ply"
