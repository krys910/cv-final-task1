#!/usr/bin/env bash
# 编译安装 2DGS CUDA 扩展（diff_surfel_rasterization + simple_knn）
# 需已激活 hw3-2dgs；conda 内建议已装 cuda-cudart-dev / cuda-cccl（见 server_bootstrap_fast）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DGS="$ROOT/external/2d-gaussian-splatting"
KNN_CU="$DGS/submodules/simple-knn/simple_knn.cu"
GLM_DIR="$DGS/submodules/diff-surfel-rasterization/third_party/glm"

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  echo "错误: 请先 conda activate hw3-2dgs"
  exit 1
fi

export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export CUDA_HOME="${CUDA_HOME:-$CONDA_PREFIX}"
export CPATH="${CONDA_PREFIX}/targets/x86_64-linux/include:${CONDA_PREFIX}/include${CPATH:+:$CPATH}"
export CPLUS_INCLUDE_PATH="$CPATH"
export PATH="${CONDA_PREFIX}/bin:${PATH}"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}"

cd "$DGS"

echo "=== [2dgs-cuda] git submodule update --init --recursive ==="
git submodule update --init --recursive || true

# glm 子模块偶发损坏时手动补全
if [[ ! -f "$GLM_DIR/glm/glm.hpp" ]]; then
  echo "=== [2dgs-cuda] 修复 glm ==="
  rm -rf "$GLM_DIR"
  git clone --depth 1 https://github.com/g-truc/glm.git "$GLM_DIR"
fi

# CUDA 12.1 nvcc 需显式包含 cfloat
if [[ -f "$KNN_CU" ]] && ! grep -q '#include <cfloat>' "$KNN_CU"; then
  sed -i '1i #include <cfloat>' "$KNN_CU"
fi

if [[ ! -f "${CONDA_PREFIX}/include/cuda_runtime.h" ]]; then
  echo "警告: 未找到 cuda_runtime.h，尝试 conda install cuda-cudart-dev=12.1 ..."
  conda install -y -c nvidia cuda-cudart-dev=12.1 ninja || true
fi

echo "=== [2dgs-cuda] pip install (CUDA_HOME=$CUDA_HOME) ==="
pip install --no-build-isolation \
  submodules/diff-surfel-rasterization \
  submodules/simple-knn

python -c "import diff_surfel_rasterization; import simple_knn; print('2DGS CUDA extensions OK')"
