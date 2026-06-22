#!/usr/bin/env bash
# 初始化 2DGS 子模块并编译 CUDA 扩展（可与 counter 下载并行）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs/install_2dgs_submodules.log"
mkdir -p "$ROOT/logs"
exec >>"$LOG" 2>&1
echo "=== [2dgs] $(date) 开始 ==="

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

set +u
conda activate hw3-2dgs
set -u

bash "$ROOT/scripts/install_2dgs_cuda.sh"

echo "=== [2dgs] $(date) 完成 ==="
