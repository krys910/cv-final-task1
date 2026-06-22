#!/usr/bin/env bash
# 加速版环境安装：conda 装 torch + 清华 pip 镜像
set -euo pipefail

cd ~/hw3
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

echo "=== [fast] 0. 停止旧安装 ==="
pkill -f "server_bootstrap.sh" 2>/dev/null || true
pkill -f "conda env create -f environment.yml" 2>/dev/null || true
pkill -f "condaenv.*requirements.txt" 2>/dev/null || true
sleep 2

source ~/miniconda3/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

if conda env list | grep -q "^hw3-2dgs "; then
  echo "Removing incomplete env hw3-2dgs ..."
  conda env remove -n hw3-2dgs -y
fi
rm -f condaenv.*.requirements.txt 2>/dev/null || true

echo "=== [fast] 1. 创建 conda 环境（含 pytorch）==="
conda env create -f environment.yml

echo "=== [fast] 2. 验证 torch ==="
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
set +u
conda activate hw3-2dgs
set -u
python - <<'PY'
import torch
print("torch", torch.__version__, "cuda", torch.cuda.is_available())
PY

echo "=== [fast] 3. 克隆第三方仓库 ==="
bash scripts/setup_repos.sh

echo "=== [fast] 4. 2DGS Python 依赖 + CUDA 扩展 ==="
cd external/2d-gaussian-splatting
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

echo "=== [fast] 完成 ==="
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
echo "Next: conda activate hw3-2dgs && cd ~/hw3 && bash scripts/01_object_a_colmap_2dgs.sh"
