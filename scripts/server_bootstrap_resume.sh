#!/usr/bin/env bash
# 从 [fast] 2 继续（环境已存在时使用）
set -euo pipefail

cd ~/hw3
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
set +u
conda activate hw3-2dgs
set -u

echo "=== [fast] 2. 验证 torch ==="
python - <<'PY'
import torch
print("torch", torch.__version__, "cuda", torch.cuda.is_available())
PY

echo "=== [fast] 3. 克隆第三方仓库 ==="
bash scripts/setup_repos.sh

echo "=== [fast] 4. 2DGS Python 依赖 ==="
cd external/2d-gaussian-splatting
git submodule update --init --recursive
pip install mediapy lpips tqdm opencv-python || true
pip install submodules/diff-surfel-rasterization submodules/simple-knn || true

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
echo "Next: bash scripts/run_full_pipeline.sh"
