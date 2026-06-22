#!/usr/bin/env bash
# 完整实验流水线：A → B → C → counter 背景 → 融合
# Step 5 融合硬性要求 object_b/mesh.obj 与 object_c/mesh.obj 均存在
# 续跑: START_STEP=2 bash scripts/run_full_pipeline.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
set +u
conda activate hw3-2dgs
set -u

export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

PROMPT_B='a light blue plastic mug with handle, matte finish, studio lighting, high quality 3D object'
LOG="$ROOT/logs/pipeline.log"
START_STEP="${START_STEP:-1}"

OBJECT_A_PLY="$ROOT/outputs/object_a/point_cloud.ply"
OBJECT_B_MESH="$ROOT/outputs/object_b/mesh.obj"
OBJECT_C_MESH="$ROOT/outputs/object_c/mesh.obj"
BG_PLY="$ROOT/outputs/background/point_cloud.ply"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

die() {
  log "错误: $*"
  log "流水线已终止。请修复上述问题后从对应步骤续跑（例: START_STEP=2 bash scripts/run_full_pipeline.sh）"
  exit 1
}

check_fusion_prerequisites() {
  local missing=0
  log "检查 Step 5 融合前置条件 ..."
  if [[ ! -f "$OBJECT_A_PLY" ]]; then
    log "  ✗ 缺少物体 A: $OBJECT_A_PLY"
    missing=1
  else
    log "  ✓ 物体 A"
  fi
  if [[ ! -f "$OBJECT_B_MESH" ]]; then
    log "  ✗ 缺少物体 B mesh: $OBJECT_B_MESH （必须先完成 Step 2 threestudio）"
    missing=1
  else
    log "  ✓ 物体 B mesh"
  fi
  if [[ ! -f "$OBJECT_C_MESH" ]]; then
    log "  ✗ 缺少物体 C mesh: $OBJECT_C_MESH （必须先完成 Step 3 Magic123）"
    missing=1
  else
    log "  ✓ 物体 C mesh"
  fi
  if [[ ! -f "$BG_PLY" ]]; then
    log "  ✗ 缺少背景点云: $BG_PLY （必须先完成 Step 4）"
    missing=1
  else
    log "  ✓ 背景 counter"
  fi
  if [[ "$missing" -ne 0 ]]; then
    die "Step 5 融合不允许跳过 Step 2/3；物体 B 与 C 的 mesh.obj 必须全部存在"
  fi
}

log "========== 流水线开始 (START_STEP=$START_STEP) =========="
python -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())" | tee -a "$LOG"

if [[ "$START_STEP" -le 1 ]]; then
  log ">>> Step 1/5: 物体 A (COLMAP + 2DGS)"
  bash scripts/01_object_a_colmap_2dgs.sh 2>&1 | tee -a "$ROOT/logs/step01_object_a.log"
  [[ -f "$OBJECT_A_PLY" ]] || die "Step 1 未生成 object_a 点云"
else
  log ">>> Step 1/5: 跳过（START_STEP=$START_STEP）"
  [[ -f "$OBJECT_A_PLY" ]] || die "Step 1 产物缺失: $OBJECT_A_PLY"
fi

if [[ "$START_STEP" -le 2 ]]; then
  if [[ -f "$OBJECT_B_MESH" ]]; then
    log ">>> Step 2/5: 物体 B 已存在，跳过"
  else
    log ">>> Step 2/5: 物体 B (threestudio) — 耗时最长，可能 1-3h"
    if ! bash scripts/02_object_b_threestudio.sh "$PROMPT_B" 2>&1 | tee -a "$ROOT/logs/step02_object_b.log"; then
      die "Step 2 物体 B (threestudio) 失败，不可继续（Step 5 需要 object_b/mesh.obj）"
    fi
    [[ -f "$OBJECT_B_MESH" ]] || die "Step 2 未生成 $OBJECT_B_MESH"
    log "物体 B 完成"
  fi
else
  log ">>> Step 2/5: 跳过（START_STEP=$START_STEP）"
fi

if [[ "$START_STEP" -le 3 ]]; then
  if [[ -f "$OBJECT_C_MESH" ]]; then
    log ">>> Step 3/5: 物体 C 已存在，跳过"
  else
    log ">>> Step 3/5: 物体 C (Magic123)"
    if ! bash scripts/03_object_c_magic123.sh "$ROOT/data/object_c/photo.jpg" 2>&1 | tee -a "$ROOT/logs/step03_object_c.log"; then
      die "Step 3 物体 C (Magic123) 失败，不可继续（Step 5 需要 object_c/mesh.obj）"
    fi
    [[ -f "$OBJECT_C_MESH" ]] || die "Step 3 未生成 $OBJECT_C_MESH"
    log "物体 C 完成"
  fi
else
  log ">>> Step 3/5: 跳过（START_STEP=$START_STEP）"
fi

if [[ "$START_STEP" -le 4 ]]; then
  if [[ -f "$BG_PLY" ]]; then
    log ">>> Step 4/5: 背景点云已存在，跳过"
  else
    log ">>> Step 4/5: 背景 counter (2DGS 30k iter) — 可能 2-4h"
    if ! bash scripts/04_background_2dgs.sh counter 2>&1 | tee -a "$ROOT/logs/step04_background.log"; then
      die "Step 4 背景重建失败"
    fi
    [[ -f "$BG_PLY" ]] || die "Step 4 未生成 $BG_PLY"
    log "背景 counter 完成"
  fi
else
  log ">>> Step 4/5: 跳过（START_STEP=$START_STEP）"
fi

if [[ "$START_STEP" -le 5 ]]; then
  check_fusion_prerequisites
  log ">>> Step 5/5: 场景融合与漫游渲染"
  python scripts/05_fuse_and_render.py 2>&1 | tee -a "$ROOT/logs/step05_fusion.log"
  log "========== 流水线全部完成 =========="
  log "视频: $ROOT/outputs/fused/walkthrough.mp4"
  log "融合点云: $ROOT/outputs/fused/fused_scene.ply"
else
  log ">>> Step 5/5: 跳过（START_STEP=$START_STEP）"
fi
