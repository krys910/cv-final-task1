#!/usr/bin/env bash
# Step 5 完成后重跑 Step 2/3 的前置准备（不杀 GPU 训练进程）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs/prep_rerun_steps23.log"
mkdir -p "$ROOT/logs"

exec >>"$LOG" 2>&1
echo "=== [prep23] $(date) 开始 ==="

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
set +u
conda activate hw3-2dgs
set -u

echo "=== [prep23] pip install pytorch_lightning ==="
pip install -q pytorch_lightning torchmetrics lightning-utilities

python -c "import pytorch_lightning; print('pytorch_lightning OK', pytorch_lightning.__version__)"

echo "=== [prep23] rembg u2net ==="
bash "$ROOT/scripts/fetch_rembg_u2net.sh" "$ROOT/logs/fetch_rembg_u2net.log"

echo "=== [prep23] Magic123 pretrained ==="
bash "$ROOT/scripts/fetch_magic123_pretrained.sh" "$ROOT/logs/fetch_magic123_pretrained.log"

echo "=== [prep23] $(date) 完成 ==="
