#!/usr/bin/env bash
# Step1 单独 train 完成后：导出 A 点云 → 严格按序执行 Step 2→3→4→5
# Step 5 融合硬性要求 B/C mesh 均存在，不会跳过失败步骤
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs/wait_step01.log"
mkdir -p "$ROOT/logs"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

log "等待 object_a 2DGS 训练 (train.py) 结束 ..."
while pgrep -f "python train.py.*outputs/object_a/model" >/dev/null 2>&1; do
  sleep 60
done
log "train.py 已退出"

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
set +u
conda activate hw3-2dgs
set -u

WORK="$ROOT/outputs/object_a"
DGS="$ROOT/external/2d-gaussian-splatting"

if [[ ! -f "$WORK/point_cloud.ply" ]]; then
  log "导出 object_a 点云 ..."
  cd "$DGS"
  python render.py -m "$WORK/model" --skip_train --skip_test
  cp "$WORK/model/point_cloud/iteration_10000/point_cloud.ply" "$WORK/point_cloud.ply"
  log "点云: $WORK/point_cloud.ply"
fi

log "启动严格流水线 Step 2→3→4→5（Step 5 需 B/C mesh 全部完成）"
exec env START_STEP=2 bash "$ROOT/scripts/run_full_pipeline.sh"
