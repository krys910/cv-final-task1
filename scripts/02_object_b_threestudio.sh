#!/usr/bin/env bash
# 物体 B: threestudio 文本生成 3D (DreamFusion / Magic3D + SDS)
# 用法: bash scripts/02_object_b_threestudio.sh "your prompt here"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/utils/wandb_env.sh"
PROMPT="${1:-a cute ceramic mug with blue stripes, studio lighting, high quality 3D object}"
OUT="$ROOT/outputs/object_b"
TS="$ROOT/external/threestudio"

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HOME/.cache/huggingface}"
set +u
conda activate hw3-2dgs
set -u

PY="${CONDA_PREFIX}/bin/python"

# mp4 测试视频导出依赖 ffmpeg 插件，避免 imageio 误用 tiff 导致 fps 报错
"$PY" -m pip install -q imageio-ffmpeg 2>/dev/null || true

mkdir -p "$OUT"
cd "$TS"

if ! "$PY" -c "from threestudio.utils.config import parse_structured" 2>/dev/null; then
  echo "错误: threestudio 未安装或依赖缺失，请先运行: bash scripts/install_threestudio.sh"
  exit 1
fi

# 优先使用本地 SD1.5（bash scripts/fetch_sd15_local.sh）
SD_LOCAL="${SD_LOCAL:-$ROOT/external/models/sd-v1-5}"
SD_MODEL="${SD_MODEL:-runwayml/stable-diffusion-v1-5}"
if [[ -f "$SD_LOCAL/model_index.json" ]]; then
  SD_MODEL="$SD_LOCAL"
  echo "=== 使用本地 SD: $SD_MODEL ==="
elif ! "$PY" -c "from huggingface_hub import hf_hub_download; hf_hub_download('runwayml/stable-diffusion-v1-5', 'model_index.json')" 2>/dev/null; then
  echo "=== SD 未缓存，请先运行: bash scripts/fetch_sd15_local.sh ==="
  bash "$ROOT/scripts/fetch_sd15_local.sh" "$ROOT/logs/fetch_sd15.log"
  SD_MODEL="$SD_LOCAL"
fi

unset HF_ENDPOINT
export TRANSFORMERS_OFFLINE="${TRANSFORMERS_OFFLINE:-0}"

TAG="object_b_$(date +%Y%m%d_%H%M%S)"

echo "=== threestudio 训练 (SDS) ==="
echo "Prompt: $PROMPT"

# DreamFusion 系统 — 基于 Stable Diffusion + SDS Loss
"$PY" launch.py \
  --config configs/dreamfusion-sd.yaml \
  --train \
  --gpu 0 \
  system.prompt_processor.prompt="$PROMPT" \
  system.prompt_processor.pretrained_model_name_or_path="$SD_MODEL" \
  system.guidance.pretrained_model_name_or_path="$SD_MODEL" \
  trainer.max_steps=10000 \
  system.loggers.wandb.enable=true \
  system.loggers.wandb.project="$WANDB_PROJECT" \
  tag="$TAG"

# trial 目录带 @timestamp 后缀，取最新匹配
EXP_DIR="$(ls -dt "$TS/outputs/dreamfusion-sd/${TAG}"@* 2>/dev/null | head -1 || true)"
EXP_DIR="${EXP_DIR:-$TS/outputs/dreamfusion-sd/$TAG}"
echo "=== 导出 Mesh (trial: $EXP_DIR) ==="
"$PY" "$ROOT/scripts/utils/export_threestudio_mesh.py" \
  --exp_dir "$EXP_DIR" \
  --threestudio "$TS" \
  --output "$OUT/mesh.obj"

echo "完成: $OUT/mesh.obj"
echo "请将 WandB/SwanLab 训练曲线截图保存到 outputs/object_b/ 供报告使用"
