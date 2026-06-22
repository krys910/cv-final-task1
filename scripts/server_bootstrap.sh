#!/usr/bin/env bash
# 云服务器首次环境配置（counter 场景）
set -euo pipefail

cd ~/hw3

echo "=== 1. 系统包 ==="
sudo apt-get update -qq
sudo apt-get install -y -qq git wget unzip ffmpeg colmap \
  build-essential cmake libboost-program-options-dev libboost-filesystem-dev \
  libeigen3-dev libflann-dev libfreeimage-dev libmetis-dev libgoogle-glog-dev \
  libgtest-dev libsqlite3-dev libglew-dev qtbase5-dev libqt5opengl5-dev libcgal-dev

echo "=== 2. Miniconda (若未安装) ==="
if ! command -v conda &>/dev/null; then
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
  eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
  conda init bash
fi
source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true

echo "=== 3. Python 环境 ==="
# 新版 Miniconda 非交互安装需先接受 ToS
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda env list | grep -q hw3-2dgs || conda env create -f environment.yml
conda activate hw3-2dgs
pip install -q torch torchvision --index-url https://download.pytorch.org/whl/cu121

echo "=== 4. 克隆第三方仓库 ==="
bash scripts/setup_repos.sh

echo "=== 5. 2DGS 依赖 + CUDA 扩展 ==="
cd ~/hw3/external/2d-gaussian-splatting
pip install -q mediapy lpips tqdm opencv-python || true
conda install -y -c nvidia cuda-cudart-dev=12.1 ninja || true
bash ~/hw3/scripts/install_2dgs_cuda.sh || true

echo "=== 6. 下载 Mip-NeRF 360 counter 场景 ==="
mkdir -p ~/hw3/data/background
cd ~/hw3/data/background
if [[ ! -d counter/images ]]; then
  if [[ ! -f 360_v2.zip ]]; then
    echo "Downloading 360_v2.zip (~11GB, 请耐心等待)..."
    wget -c http://storage.googleapis.com/gresearch/refraw360/360_v2.zip
  fi
  unzip -q 360_v2.zip "counter/*" -d .
  echo "counter scene ready at $(pwd)/counter"
fi

echo "=== 完成 ==="
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
echo "Next: conda activate hw3-2dgs && cd ~/hw3 && bash scripts/01_object_a_colmap_2dgs.sh"
