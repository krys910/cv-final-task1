#!/usr/bin/env bash
# 单路径：本地 wheel 装 torch 2.0.1+cu118 → 编译扩展 → 从 zero123 提取 CLIP → 启动 Step 3
set -euo pipefail

ROOT="${HOME}/hw3"
LOG="${ROOT}/logs/post_torch.log"
M123="${ROOT}/external/Magic123"
TORCH_WHL="/data/wheels/torch-2.0.1+cu118-cp310-cp310-linux_x86_64.whl"
TV_WHL="/data/wheels/torchvision-0.15.2+cu118-cp310-cp310-linux_x86_64.whl"
TORCH_MIN=$((2200 * 1000 * 1000))
ZERO="/data/ubuntu/hw3-pretrained/zero123/105000.ckpt"
[[ -f "${ZERO}" ]] || ZERO="${M123}/pretrained/zero123/105000.ckpt"
CLIP_OUT="/data/clip-cache/ViT-L-14.pt"
CLIP_MIN=$((850 * 1000 * 1000))
MESH="${ROOT}/outputs/object_c/mesh.obj"

mkdir -p "${ROOT}/logs" /data/clip-cache /data/torch_extensions /data/tmp "${HOME}/.cache/clip"
exec >>"${LOG}" 2>&1

log() { echo "[$(date '+%F %T')] $*"; }

export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}"
export TORCH_EXTENSIONS_DIR="${TORCH_EXTENSIONS_DIR:-/data/torch_extensions}"
export TMPDIR="${TMPDIR:-/data/tmp}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-/data/ubuntu/pip-cache}"

source "${HOME}/miniconda3/etc/profile.d/conda.sh"
set +u
conda activate hw3-2dgs
set -u

file_size() { stat -c%s "$1" 2>/dev/null || echo 0; }

torch_ready() {
  python -c "import torch; assert torch.__version__.startswith('2.0'); assert torch.cuda.is_available()" 2>/dev/null
}

ext_ready() {
  for m in gridencoder raymarching freqencoder shenencoder; do
    python -c "import ${m}" 2>/dev/null || return 1
  done
}

clip_ready() {
  [[ -f "${CLIP_OUT}" ]] && [[ "$(file_size "${CLIP_OUT}")" -ge "${CLIP_MIN}" ]]
}

log "=== hw3_post_torch 启动 ==="

# 1) 安装 torch（仅本地 wheel，不走网络）
if ! torch_ready; then
  wsz=$(file_size "${TORCH_WHL}")
  if [[ "${wsz}" -lt "${TORCH_MIN}" ]] || ! unzip -t "${TORCH_WHL}" >/dev/null 2>&1; then
    log "ERROR: torch wheel 不完整或损坏 (${wsz} bytes)，等待 aria2"
    exit 1
  fi
  log "pip install torch wheel (${wsz} bytes)"
  pip install --no-index --find-links=/data/wheels "${TORCH_WHL}" "${TV_WHL}" 2>&1 || \
    pip install "${TORCH_WHL}" "${TV_WHL}" --no-deps 2>&1
  python -c "import torch; print('torch OK', torch.__version__, torch.cuda.is_available())"
fi

# 2) 编译 Magic123 CUDA 扩展
if ! ext_ready; then
  log "编译 CUDA 扩展..."
  for ext in gridencoder raymarching freqencoder shenencoder; do
    log "build ${ext}"
    pip install -e "${M123}/${ext}" --no-build-isolation 2>&1
    python -c "import ${ext}; print('${ext} OK')"
  done
fi

# 3) 从 zero123 提取 CLIP（禁止网络下载）
if ! clip_ready; then
  log "从 zero123 提取 CLIP -> ${CLIP_OUT}"
  rm -f "${CLIP_OUT}" "${CLIP_OUT}.tmp" 2>/dev/null || true
  python - <<PY
import os, torch
zero = "${ZERO}"
out = "${CLIP_OUT}"
sd = torch.load(zero, map_location="cpu")["state_dict"]
clip_sd = {k[len("cond_stage_model.model."):]: v for k, v in sd.items() if k.startswith("cond_stage_model.model.")}
if len(clip_sd) < 100:
    raise SystemExit(f"CLIP keys too few: {len(clip_sd)}")
torch.save(clip_sd, out + ".tmp")
os.replace(out + ".tmp", out)
print("CLIP OK", len(clip_sd), "keys", os.path.getsize(out), "bytes")
PY
fi
ln -sfn "${CLIP_OUT}" "${HOME}/.cache/clip/ViT-L-14.pt"

# 4) 启动 Step 3
if [[ -f "${MESH}" ]]; then
  log "mesh.obj 已存在，跳过 Step 3"
  exit 0
fi

if pgrep -f "${M123}/main.py" >/dev/null 2>&1 || pgrep -f "03_object_c_magic123.sh" >/dev/null 2>&1; then
  log "Step 3 已在运行"
  exit 0
fi

log "启动 Step 3 Magic123"
nohup bash "${ROOT}/scripts/03_object_c_magic123.sh" >> "${ROOT}/logs/step03_object_c.log" 2>&1 &
log "Step 3 PID=$!"
log "=== hw3_post_torch 完成 ==="
