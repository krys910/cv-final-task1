#!/usr/bin/env bash
# 跳过 Magic123，直接跑 bootstrap 步骤 4-5
set -euo pipefail

cd ~/hw3
LOG="$HOME/hw3/logs/bootstrap_step45.log"
mkdir -p logs
exec >>"$LOG" 2>&1
echo "=== [step45] $(date) 开始（跳过 Magic123）==="

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

set +u
conda activate hw3-2dgs
set -u

EXT="$HOME/hw3/external"

echo "=== [fast] 4. 2DGS Python 依赖 + CUDA 扩展 ==="
cd "$EXT/2d-gaussian-splatting"
pip install mediapy lpips tqdm opencv-python || true
conda install -y -c nvidia cuda-cudart-dev=12.1 ninja || true
bash ~/hw3/scripts/install_2dgs_cuda.sh || true

echo "=== [fast] 5. 下载 counter 场景 ==="
mkdir -p ~/hw3/data/background
cd ~/hw3/data/background
if [[ ! -d counter/images ]]; then
  if [[ ! -f 360_v2.zip ]]; then
    echo "Downloading 360_v2.zip (~11GB) ..."
    wget -c http://storage.googleapis.com/gresearch/refraw360/360_v2.zip
  fi
  unzip -q 360_v2.zip "counter/*" -d .
fi

echo "=== [fast] 完成 ===" >> ~/hw3/bootstrap_fast.log
echo "=== [fast] 完成 ==="
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
echo "=== [step45] $(date) 完成 ==="
