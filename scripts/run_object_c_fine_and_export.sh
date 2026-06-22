#!/usr/bin/env bash
set -euo pipefail
ROOT=~/hw3
M123=$ROOT/external/Magic123
OUT=$ROOT/outputs/object_c
IMAGE=$OUT/magic123_data/rgba.png
COARSE_CKPT=$M123/out/magic123-object_c-coarse/hw3/magic123_object_c_object_c_coarse/checkpoints/magic123_object_c_object_c_coarse.pth
FINE_WS=out/magic123-object_c-dmtet/hw3/magic123_object_c_dmtet
SD_LOCAL=$ROOT/external/models/sd-v1-5
LOG=$ROOT/logs/step03_fine.log

set +u
source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
conda activate hw3-2dgs
set -u
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="${CONDA_PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export TORCH_EXTENSIONS_DIR="${TORCH_EXTENSIONS_DIR:-/data/torch_extensions}"
export TMPDIR="${TMPDIR:-/data/tmp}"
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
export CLIP_VISUAL_PT=/data/clip-cache/clip_visual_from_zero123.pt

exec >>"$LOG" 2>&1
echo "[$(date)] === Step 3 fine (DMTet) start ==="
test -f "$COARSE_CKPT" || { echo "missing coarse ckpt: $COARSE_CKPT"; exit 1; }

cd "$M123"
python main.py -O \
  --text "A high-resolution DSLR image of an object" \
  --sd_version 1.5 \
  --hf_key "$SD_LOCAL" \
  --image "$IMAGE" \
  --workspace "$FINE_WS" \
  --dmtet --init_ckpt "$COARSE_CKPT" \
  --iters 5000 --optim adam --known_view_interval 4 \
  --latent_iter_ratio 0 --guidance SD zero123 \
  --lambda_guidance 1e-3 0.01 --guidance_scale 100 5 \
  --rm_edge --bg_radius -1 --save_mesh

echo "[$(date)] === export mesh ==="
python "$ROOT/scripts/utils/export_magic123_mesh.py" \
  --exp_dir "$M123/$FINE_WS" \
  --output "$OUT/mesh.obj"

echo "[$(date)] === DONE: $OUT/mesh.obj ==="
ls -lh "$OUT/mesh.obj"
