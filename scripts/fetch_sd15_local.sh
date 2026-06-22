#!/usr/bin/env bash
# 下载 SD1.5 到本地目录（国内服务器 ModelScope 更稳）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SD_DIR="${SD_DIR:-$ROOT/external/models/sd-v1-5}"
SD_CACHE="${SD_CACHE_DIR:-/data/modelscope-sd15-cache}"
LOG="${1:-$ROOT/logs/fetch_sd15.log}"
mkdir -p "$(dirname "$LOG")"

exec >>"$LOG" 2>&1
echo "=== [sd15] $(date) 开始 -> $SD_DIR (cache: $SD_CACHE) ==="

source ~/miniconda3/etc/profile.d/conda.sh
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
set +u
conda activate hw3-2dgs
set -u

PY="${CONDA_PREFIX}/bin/python"

sd_ok() {
  "$PY" -c "
import os, glob, sys
root = sys.argv[1]
unet = glob.glob(root + '/unet/*.safetensors') + glob.glob(root + '/unet/*.bin')
ok = os.path.isfile(os.path.join(root, 'model_index.json')) and unet and os.path.getsize(unet[0]) > 3.3e9
raise SystemExit(0 if ok else 1)
" "$1" 2>/dev/null
}

link_sd() {
  "$PY" -c "
import os, sys
root, dst = sys.argv[1], sys.argv[2]
parent = os.path.dirname(dst)
os.makedirs(parent, exist_ok=True)
if os.path.lexists(dst):
    if os.path.islink(dst):
        os.unlink(dst)
    elif os.path.isdir(dst) and not os.listdir(dst):
        os.rmdir(dst)
    elif os.path.isdir(dst):
        import shutil
        shutil.rmtree(dst)
if not os.path.exists(dst):
    os.symlink(root, dst)
print('SD1.5 OK', root, '->', dst)
" "$1" "$SD_DIR"
}

MS_DIR="$SD_CACHE/AI-ModelScope/stable-diffusion-v1-5"

if sd_ok "$SD_DIR"; then
  echo "=== [sd15] 已存在，跳过 ==="
  exit 0
fi

if sd_ok "$MS_DIR"; then
  echo "=== [sd15] 缓存完整，创建符号链接 ==="
  link_sd "$MS_DIR"
  exit 0
fi

if [[ -d "$MS_DIR" ]]; then
  echo "=== [sd15] 缓存不完整（unet 续传中），跳过 ModelScope 全量下载 ==="
  exit 1
fi

pip install -q modelscope

"$PY" - <<PY
from modelscope import snapshot_download
import os, glob
dst = "$SD_DIR"
cache = "$SD_CACHE"
os.makedirs(cache, exist_ok=True)
MS_DIR=os.path.join(cache, "AI-ModelScope/stable-diffusion-v1-5")
cache_path = snapshot_download("AI-ModelScope/stable-diffusion-v1-5", cache_dir=cache)
root = cache_path if os.path.isfile(os.path.join(cache_path, "model_index.json")) else MS_DIR
unet = glob.glob(root + "/unet/*.safetensors") + glob.glob(root + "/unet/*.bin")
assert os.path.isfile(os.path.join(root, "model_index.json")) and unet and os.path.getsize(unet[0]) > 3.3e9
parent = os.path.dirname(dst)
os.makedirs(parent, exist_ok=True)
if os.path.lexists(dst):
    if os.path.islink(dst):
        os.unlink(dst)
    elif os.path.isdir(dst) and not os.listdir(dst):
        os.rmdir(dst)
    elif os.path.isdir(dst):
        import shutil
        shutil.rmtree(dst)
if not os.path.exists(dst):
    os.symlink(root, dst)
print("SD1.5 OK", root, "->", dst)
PY

echo "=== [sd15] $(date) 完成 $(du -sh "$SD_DIR" | cut -f1) ==="
