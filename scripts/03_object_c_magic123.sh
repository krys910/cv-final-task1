#!/usr/bin/env bash
# 物体 C: 单图抠图 + Magic123 生成 3D
# 用法: bash scripts/03_object_c_magic123.sh [输入图片]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${1:-$ROOT/data/object_c/input.png}"
OUT="$ROOT/outputs/object_c"
M123="$ROOT/external/Magic123"
DATA_DIR="$OUT/magic123_data"
RUN_ID="object_c"
DATASET="hw3"

# WandB: 凭据来自 ~/.wandb_api_key（勿提交 git）
# shellcheck disable=SC1091
source "$ROOT/scripts/utils/wandb_env.sh"

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="$CUDA_HOME/bin:$PATH"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}"
export TORCH_EXTENSIONS_DIR="${TORCH_EXTENSIONS_DIR:-/data/torch_extensions}"
export TMPDIR="${TMPDIR:-/data/tmp}"
mkdir -p "$TORCH_EXTENSIONS_DIR" "$TMPDIR"
set +u
conda activate hw3-2dgs
set -u

mkdir -p "$OUT" "$DATA_DIR"

if [[ ! -f "$INPUT" ]]; then
  echo "错误: 输入图片不存在: $INPUT"
  exit 1
fi

# 让 diffusers 使用本地 SD1.5 缓存
SD_CACHE="/data/modelscope-sd15-cache/AI-ModelScope/stable-diffusion-v1-5"
HF_SNAP="$HOME/.cache/huggingface/hub/models--runwayml--stable-diffusion-v1-5/snapshots/local"
mkdir -p "$(dirname "$HF_SNAP")" "$(dirname "$HF_SNAP")/../refs"
ln -sfn "$SD_CACHE" "$HF_SNAP"
echo "local" > "$(dirname "$HF_SNAP")/../refs/main"

echo "=== Step 1: 预处理 (depth + rgba) ==="
cp -f "$INPUT" "$DATA_DIR/main.png"
cp -f "$INPUT" "$DATA_DIR/rgba.png"
cd "$M123"
python preprocess_image.py --path "$DATA_DIR/main.png"
IMAGE="$DATA_DIR/rgba.png"

COARSE_WS="out/magic123-${RUN_ID}-coarse/${DATASET}/magic123_${RUN_ID}_${RUN_ID}_coarse"
FINE_WS="out/magic123-${RUN_ID}-dmtet/${DATASET}/magic123_${RUN_ID}_dmtet"
COARSE_CKPT="${COARSE_WS}/checkpoints/magic123_${RUN_ID}_${RUN_ID}_coarse.pth"

WANDB_ARGS=(--use_wandb)

echo "=== Step 2: Magic123 coarse (NeRF) ==="
python main.py -O \
  --text "A high-resolution DSLR image of an object" \
  --sd_version 1.5 \
  --image "$IMAGE" \
  --workspace "$COARSE_WS" \
  --optim adam \
  --iters 5000 \
  --guidance SD zero123 \
  --lambda_guidance 1.0 40 \
  --guidance_scale 100 5 \
  --latent_iter_ratio 0 \
  --normal_iter_ratio 0.2 \
  --t_range 0.2 0.6 \
  --bg_radius -1 \
  --save_mesh \
  "${WANDB_ARGS[@]}"

echo "=== Step 3: Magic123 fine (DMTet) ==="
python main.py -O \
  --text "A high-resolution DSLR image of an object" \
  --sd_version 1.5 \
  --image "$IMAGE" \
  --workspace "$FINE_WS" \
  --dmtet --init_ckpt "$COARSE_CKPT" \
  --iters 5000 \
  --optim adam \
  --known_view_interval 4 \
  --latent_iter_ratio 0 \
  --guidance SD zero123 \
  --lambda_guidance 1e-3 0.01 \
  --guidance_scale 100 5 \
  --rm_edge \
  --bg_radius -1 \
  --save_mesh \
  "${WANDB_ARGS[@]}"

echo "=== Step 4: 导出 Mesh ==="
python "$ROOT/scripts/utils/export_magic123_mesh.py" \
  --exp_dir "$M123/$FINE_WS" \
  --output "$OUT/mesh.obj"

echo "完成: $OUT/mesh.obj"
