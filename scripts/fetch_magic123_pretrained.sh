#!/usr/bin/env bash
# 下载 Magic123 所需预训练权重（不占用 GPU，可与 background 训练并行）
set -euo pipefail

M123="${M123_ROOT:-$HOME/hw3/external/Magic123}"
LOG="${1:-$HOME/hw3/logs/fetch_magic123_pretrained.log}"

mkdir -p "$(dirname "$LOG")"

exec >>"$LOG" 2>&1
echo "=== [m123-pretrained] $(date) 开始 ==="

source ~/miniconda3/etc/profile.d/conda.sh
set +u
conda activate hw3-2dgs
set -u
PY="${CONDA_PREFIX}/bin/python"

ZERO="$M123/pretrained/zero123/105000.ckpt"
MIDAS="$M123/pretrained/midas/dpt_beit_large_512.pt"
ZERO_MIN_BYTES=$((10 * 1000 * 1000 * 1000)) # ~10GB，官方约 15.5GB
MIDAS_MIN_BYTES=$((100 * 1000 * 1000))      # ~100MB
HF_MIRROR="${HF_ENDPOINT:-https://hf-mirror.com}"

file_size() {
  stat -c%s "$1" 2>/dev/null || echo 0
}

merge_hf_incomplete_to_part() {
  local part="$1"
  local cache="${HUGGINGFACE_HUB_CACHE:-$HOME/.cache/huggingface}"
  local inc
  inc=$(find "$cache/models--cvlab--zero123-weights/blobs" -name "*.incomplete" 2>/dev/null | head -1 || true)
  [[ -n "$inc" ]] || return 0
  local inc_sz part_sz
  inc_sz=$(file_size "$inc")
  part_sz=$(file_size "$part")
  if (( inc_sz > part_sz )); then
    echo "=== 合并 HF incomplete ${inc_sz}B -> ${part} (原 ${part_sz}B) ==="
    cp -f "$inc" "$part"
  fi
}

download_aria2() {
  local dest="$1"
  local url="$2"
  local min_bytes="$3"
  local part="${dest}.part"
  local dir part_name i
  dir=$(dirname "$dest")
  part_name=$(basename "$part")
  mkdir -p "$dir"

  if [[ -f "$dest" ]] && [[ "$(file_size "$dest")" -ge "$min_bytes" ]]; then
    echo "=== 已存在: $dest ($(du -h "$dest" | cut -f1)) ==="
    return 0
  fi

  if ! command -v aria2c >/dev/null 2>&1; then
    echo "=== aria2c 未安装 ==="
    return 1
  fi

  for i in 1 2 3 4 5; do
    echo "=== aria2c try $i: $url (已有 $(du -h "$part" 2>/dev/null | cut -f1 || echo 0)) ==="
    if ( cd "$dir" && aria2c -c --continue=true -x 16 -s 16 -k 1M \
      --file-allocation=none --summary-interval=30 --console-log-level=notice \
      -o "$part_name" "$url" ) && [[ -f "$part" ]]; then
      local actual
      actual=$(du -b "$part" 2>/dev/null | cut -f1)
      if [[ "${actual:-0}" -ge "$min_bytes" ]] || [[ "$(file_size "$part")" -ge "$min_bytes" ]]; then
        mv -f "$part" "$dest"
        rm -f "${part}.aria2" 2>/dev/null || true
        echo "=== OK (aria2c): $dest ($(du -h "$dest" | cut -f1)) ==="
        return 0
      fi
      echo "=== aria2c 未完成，实际 $(du -h "$part" | cut -f1)，继续 ==="
    else
      echo "=== aria2c 中断，保留 .part 续传 ==="
      sleep 10
    fi
  done
  return 1
}

download_zero123_aria2() {
  local dest="$1"
  local url="$2"
  merge_hf_incomplete_to_part "${dest}.part"
  download_aria2 "$dest" "$url" "$ZERO_MIN_BYTES"
}

download_zero123_curl() {
  local dest="$1"
  local url="$2"
  local part="${dest}.part"
  local i
  mkdir -p "$(dirname "$dest")"
  merge_hf_incomplete_to_part "$part"

  for i in 1 2 3 4 5 6 7 8 9 10; do
    echo "=== curl try $i: $url (已有 $(du -h "$part" 2>/dev/null | cut -f1 || echo 0)) ==="
    if curl -fL --retry 8 --retry-delay 15 --connect-timeout 60 --max-time 0 \
      -C - -o "$part" "$url" && mv -f "$part" "$dest"; then
      if [[ "$(file_size "$dest")" -ge "$ZERO_MIN_BYTES" ]]; then
        echo "=== OK (curl): $dest ($(du -h "$dest" | cut -f1)) ==="
        return 0
      fi
      echo "=== 大小异常: $(file_size "$dest")B ==="
      rm -f "$dest"
    fi
    echo "=== curl 失败/中断，保留 .part 续传，10s 后重试 ==="
    sleep 10
  done
  return 1
}

download_hf_zero123() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]] && [[ "$(file_size "$dest")" -ge "$ZERO_MIN_BYTES" ]]; then
    echo "=== 已存在: $dest ($(du -h "$dest" | cut -f1)) ==="
    return 0
  fi

  echo "=== HF 镜像续传 zero123 (hf_hub_download + cache) ==="
  export HF_ENDPOINT="$HF_MIRROR"
  export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HOME/.cache/huggingface}"
  export ZERO_DEST="$dest"
  unset HF_HUB_ENABLE_HF_TRANSFER 2>/dev/null || true

  "$PY" - <<'PY'
import os, shutil, time, glob
from huggingface_hub import hf_hub_download

dest = os.environ["ZERO_DEST"]
cache = os.environ.get("HUGGINGFACE_HUB_CACHE", os.path.expanduser("~/.cache/huggingface"))
os.environ["HF_ENDPOINT"] = os.environ.get("HF_ENDPOINT", "https://hf-mirror.com")

incomplete = glob.glob(os.path.join(cache, "models--cvlab--zero123-weights", "blobs", "*.incomplete"))
if incomplete:
    print(f"续传 HF cache: {os.path.getsize(incomplete[0])/1e6:.1f}MB")

last_err = None
for attempt in range(1, 11):
    try:
        print(f"=== hf_hub_download attempt {attempt}/10 ===")
        path = hf_hub_download(
            repo_id="cvlab/zero123-weights",
            filename="105000.ckpt",
            cache_dir=cache,
            resume_download=True,
        )
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.abspath(path) != os.path.abspath(dest):
            if os.path.exists(dest):
                os.remove(dest)
            shutil.copy2(path, dest)
        print(f"HF OK: {dest} ({os.path.getsize(dest)/1e9:.2f}GB)")
        break
    except Exception as e:
        last_err = e
        print(f"attempt {attempt} failed: {type(e).__name__}: {e}")
        time.sleep(min(60, 10 * attempt))
else:
    raise SystemExit(f"HF hub 失败: {last_err}")
PY

  [[ -f "$dest" ]] && [[ "$(file_size "$dest")" -ge "$ZERO_MIN_BYTES" ]]
}

download_curl() {
  local dest="$1"
  local url="$2"
  local min_bytes="${3:-$ZERO_MIN_BYTES}"
  local i
  mkdir -p "$(dirname "$dest")"
  local part="${dest}.part"

  for i in 1 2 3 4 5; do
    echo "=== curl try $i: $url -> $dest ==="
    if curl -fL --retry 5 --retry-delay 10 --connect-timeout 30 --max-time 0 \
      -C - -o "$part" "$url" && mv "$part" "$dest"; then
      if [[ "$(file_size "$dest")" -ge "$min_bytes" ]]; then
        echo "=== OK (curl): $dest ($(du -h "$dest" | cut -f1)) ==="
        return 0
      fi
      rm -f "$dest" "$part"
    fi
    sleep 10
  done
  return 1
}

download_retry() {
  local dest="$1"
  local min_bytes="$2"
  shift 2
  local url
  for url in "$@"; do
    download_curl "$dest" "$url" "$min_bytes" && return 0
    rm -f "${dest}.part"
  done
  return 1
}

# --- zero123: 已完成则跳过 ---
if [[ -f "$ZERO" ]] && [[ "$(file_size "$ZERO")" -ge "$ZERO_MIN_BYTES" ]]; then
  echo "=== 已存在: $ZERO ($(du -h "$ZERO" | cut -f1))，跳过 zero123 ==="
else
  ZERO_URL="${HF_MIRROR}/cvlab/zero123-weights/resolve/main/105000.ckpt"
  if ! download_zero123_aria2 "$ZERO" "$ZERO_URL"; then
    echo "=== aria2c 未成功，尝试 curl 单线程 ==="
    if ! download_zero123_curl "$ZERO" "$ZERO_URL"; then
      echo "=== curl 镜像未成功，尝试 hf_hub_download ==="
      if ! download_hf_zero123 "$ZERO"; then
        echo "=== 尝试 huggingface.co aria2/curl ==="
        download_zero123_aria2 "$ZERO" "https://huggingface.co/cvlab/zero123-weights/resolve/main/105000.ckpt" || \
        download_zero123_curl "$ZERO" "https://huggingface.co/cvlab/zero123-weights/resolve/main/105000.ckpt" || {
          echo "=== 最后手段 Columbia（极慢）==="
          download_zero123_curl "$ZERO" "https://cv.cs.columbia.edu/zero123/assets/105000.ckpt" || {
            echo "=== zero123 下载失败 ==="
            exit 1
          }
        }
      fi
    fi
  fi
fi
[[ -f "$ZERO" ]] || { echo "=== zero123 下载失败 ==="; exit 1; }

# --- midas: aria2c 16 线程续传 ---
if [[ ! -f "$MIDAS" ]] || [[ "$(file_size "$MIDAS")" -lt "$MIDAS_MIN_BYTES" ]]; then
  MIDAS_URLS=(
    "https://ghfast.top/https://github.com/isl-org/MiDaS/releases/download/v3_1/dpt_beit_large_512.pt"
    "https://github.com/isl-org/MiDaS/releases/download/v3_1/dpt_beit_large_512.pt"
  )
  midas_ok=0
  for url in "${MIDAS_URLS[@]}"; do
    if download_aria2 "$MIDAS" "$url" "$MIDAS_MIN_BYTES"; then
      midas_ok=1
      break
    fi
  done
  if [[ "$midas_ok" -ne 1 ]]; then
    echo "=== aria2c 未成功，尝试 curl 备用 ==="
    download_retry "$MIDAS" "$MIDAS_MIN_BYTES" "${MIDAS_URLS[@]}" || { echo "=== midas 下载失败 ==="; exit 1; }
  fi
else
  echo "=== 已存在: $MIDAS ($(du -h "$MIDAS" | cut -f1)) ==="
fi

echo "=== [m123-pretrained] $(date) 完成 ==="
echo "=== 启动 Step 3 自动 watcher（推荐）: ==="
echo "    nohup bash scripts/wait_for_step3_and_run.sh >> logs/wait_step03.log 2>&1 &"
echo "=== 或权重就绪后手动: bash scripts/03_object_c_magic123.sh data/object_c/input.png ==="
