#!/usr/bin/env bash
# 重试 Magic123 获取，完成后继续 bootstrap 步骤 4-5（Magic123 失败不阻塞）
set -euo pipefail

cd ~/hw3
LOG="$HOME/hw3/logs/clone_and_continue.log"
mkdir -p logs

exec >>"$LOG" 2>&1
echo "=== [continue] $(date) 开始 ==="

source ~/miniconda3/etc/profile.d/conda.sh
export MKL_INTERFACE_LAYER="${MKL_INTERFACE_LAYER:-LP64,GNU}"
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

EXT="$HOME/hw3/external"
cd "$EXT"

fetch_magic123() {
  rm -rf Magic123 Magic123.zip Magic123-main

  echo "=== [continue] 方式1: gitclone 镜像 ==="
  if git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 \
    clone --depth 1 https://gitclone.com/github.com/guochengqian/Magic123.git Magic123; then
    [[ -f Magic123/README.md ]] && return 0
  fi
  rm -rf Magic123

  echo "=== [continue] 方式2: ghproxy ZIP ==="
  local url="https://mirror.ghproxy.com/https://github.com/guochengqian/Magic123/archive/refs/heads/main.zip"
  if curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 --max-time 7200 \
    -o Magic123.zip "$url"; then
    if unzip -t Magic123.zip >/dev/null 2>&1; then
      unzip -q Magic123.zip
      mv Magic123-main Magic123
      rm -f Magic123.zip
      [[ -f Magic123/README.md ]] && return 0
    fi
    echo "ZIP 校验失败（可能下载不完整，当前 $(du -h Magic123.zip | cut -f1)）"
  fi
  rm -rf Magic123 Magic123.zip Magic123-main

  echo "=== [continue] 方式3: GitHub 直连 git (HTTP/1.1) ==="
  if git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 \
    -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=600 \
    clone --depth 1 https://github.com/guochengqian/Magic123.git Magic123; then
    [[ -f Magic123/README.md ]] && return 0
  fi
  rm -rf Magic123
  return 1
}

if [[ ! -f Magic123/README.md ]]; then
  if fetch_magic123; then
    echo "=== [continue] Magic123 OK: $(du -sh Magic123 | cut -f1) ==="
  else
    echo "=== [continue] 警告: Magic123 获取失败，跳过（物体 C 步骤可能失败，A/B/背景不受影响）==="
  fi
else
  echo "=== [continue] Magic123 已存在: $(du -sh Magic123 | cut -f1) ==="
fi

set +u
conda activate hw3-2dgs
set -u

echo "=== [fast] 4. 2DGS Python 依赖 ==="
cd "$EXT/2d-gaussian-splatting"
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

echo "=== [fast] 完成 ===" >> ~/hw3/bootstrap_fast.log
echo "=== [fast] 完成 ==="
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

echo "=== [continue] $(date) 完成 ==="
