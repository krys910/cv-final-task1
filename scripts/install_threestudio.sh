#!/usr/bin/env bash
# 安装 threestudio 及 Step 2 所需依赖，并验证 launch.py 可导入
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TS="$ROOT/external/threestudio"
LOG="${1:-$ROOT/logs/install_threestudio.log}"
mkdir -p "$ROOT/logs"

exec >>"$LOG" 2>&1
echo "=== [threestudio] $(date) 开始 ==="

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
set +u
conda activate hw3-2dgs
set -u

pip install -q \
  pytorch_lightning torchmetrics lightning-utilities \
  omegaconf einops jaxtyping typeguard \
  trimesh "transformers==4.28.1" "diffusers==0.19.3" "huggingface_hub==0.16.4" \
  "accelerate==0.20.3" safetensors controlnet_aux tensorboard \
  opencv-python xatlas pysdf PyMCubes networkx kornia einops \
  "libigl==2.5.1"

export CUDA_HOME="${CUDA_HOME:-$CONDA_PREFIX}"
export CPATH="${CONDA_PREFIX}/targets/x86_64-linux/include:${CONDA_PREFIX}/include${CPATH:+:$CPATH}"
export CPLUS_INCLUDE_PATH="$CPATH"
export PATH="${CONDA_PREFIX}/bin:${PATH}"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}"

if ! python -c "import nvdiffrast" 2>/dev/null; then
  echo "=== [threestudio] 安装 nvdiffrast ==="
  pip install -q --no-build-isolation \
    git+https://ghfast.top/https://github.com/NVlabs/nvdiffrast.git
fi

if ! python -c "import nerfacc" 2>/dev/null; then
  echo "=== [threestudio] 安装 nerfacc ==="
  pip install -q --no-build-isolation \
    git+https://ghfast.top/https://github.com/KAIR-BAIR/nerfacc.git@v0.5.2
fi

if ! python -c "import envlight" 2>/dev/null; then
  echo "=== [threestudio] 安装 envlight ==="
  pip install -q --no-build-isolation \
    git+https://ghfast.top/https://github.com/ashawkey/envlight.git
fi

export CUDA_HOME="${CUDA_HOME:-$CONDA_PREFIX}"
export CPATH="${CONDA_PREFIX}/targets/x86_64-linux/include:${CONDA_PREFIX}/include${CPATH:+:$CPATH}"
export CPLUS_INCLUDE_PATH="$CPATH"
export PATH="${CONDA_PREFIX}/bin:${PATH}"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}"

if ! python -c "import tinycudann" 2>/dev/null; then
  echo "=== [threestudio] 安装 tinycudann (本地镜像克隆) ==="
  TCNN_DIR="/tmp/tiny-cuda-nn-build"
  rm -rf "$TCNN_DIR"
  git clone --depth 1 https://ghfast.top/https://github.com/NVlabs/tiny-cuda-nn.git "$TCNN_DIR"
  mkdir -p "$TCNN_DIR/dependencies"
  rm -rf "$TCNN_DIR/dependencies/fmt" "$TCNN_DIR/dependencies/cmrc"
  git clone --depth 1 https://ghfast.top/https://github.com/fmtlib/fmt.git "$TCNN_DIR/dependencies/fmt"
  git clone --depth 1 https://ghfast.top/https://github.com/vector-of-bool/cmrc.git "$TCNN_DIR/dependencies/cmrc"
  git clone --depth 1 https://ghfast.top/https://github.com/NVIDIA/cutlass.git "$TCNN_DIR/dependencies/cutlass"
  pip install -q "setuptools<81" wheel ninja
  pip install --no-build-isolation "$TCNN_DIR/bindings/torch"
fi

if [[ ! -d "$TS/threestudio" ]]; then
  echo "错误: $TS 不存在，请先 bash scripts/setup_repos.sh"
  exit 1
fi

cd "$TS"
pip install -q -e .

echo "=== [threestudio] 验证 import ==="
python - <<'PY'
import threestudio
from threestudio.utils.config import parse_structured
print("threestudio OK", threestudio.__file__)
PY

python launch.py --help >/dev/null

echo "=== [threestudio] 预拉 SD1.5 (hf-mirror) ==="
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
"$CONDA_PREFIX/bin/python" - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download("runwayml/stable-diffusion-v1-5")
print("SD1.5 cache OK")
PY

echo "=== [threestudio] $(date) 完成 ==="
