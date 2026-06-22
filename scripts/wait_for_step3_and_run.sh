#!/usr/bin/env bash
# 等待 zero123 + midas 权重就绪后：清缓存 → 拉 SD1.5 → 后台启动 Step 3
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs/wait_step03.log"
M123="$ROOT/external/Magic123"
ZERO="$M123/pretrained/zero123/105000.ckpt"
MIDAS="$M123/pretrained/midas/dpt_beit_large_512.pt"
INPUT="$ROOT/data/object_c/input.png"
STEP3_LOG="$ROOT/logs/step03_object_c.log"
ZERO_MIN=$((10 * 1000 * 1000 * 1000))
MIDAS_MIN=$((100 * 1000 * 1000))
SD_NEED_GB=5

mkdir -p "$ROOT/logs"

exec >>"$LOG" 2>&1
echo "[$(date '+%F %T')] wait_for_step3 启动，等待 zero123 + midas ..."

log() { echo "[$(date '+%F %T')] $*"; }

file_size() { stat -c%s "$1" 2>/dev/null || echo 0; }

weights_ready() {
  [[ -f "$ZERO" ]] && [[ "$(file_size "$ZERO")" -ge "$ZERO_MIN" ]] && \
  [[ -f "$MIDAS" ]] && [[ "$(file_size "$MIDAS")" -ge "$MIDAS_MIN" ]]
}

avail_kb() { df / | tail -1 | awk '{print $4}'; }

clean_hf_cache_if_needed() {
  local need_kb=$((SD_NEED_GB * 1024 * 1024))
  local avail
  avail=$(avail_kb)
  if (( avail >= need_kb )); then
    log "磁盘 OK: $(df -h / | tail -1 | awk '{print $4}') 可用"
    return 0
  fi
  log "磁盘紧张 ($(df -h / | tail -1 | awk '{print $4}') 可用)，清理缓存（保留 SD 下载进度）..."
  rm -rf "$HOME/.cache/huggingface/hub" "$HOME/.cache/huggingface/models--"* 2>/dev/null || true
  find "$HOME/.cache/huggingface" -name "*.incomplete" -delete 2>/dev/null || true
  pip cache purge 2>/dev/null || true
  log "清理后可用: $(df -h / | tail -1 | awk '{print $4}')"
}

sd_ready() {
  source ~/miniconda3/etc/profile.d/conda.sh
  set +u
  conda activate hw3-2dgs
  set -u
  python -c "
import os, glob
dst = '$ROOT/external/models/sd-v1-5'
unet = glob.glob(dst + '/unet/*.safetensors') + glob.glob(dst + '/unet/*.bin')
ok = os.path.isfile(os.path.join(dst, 'model_index.json')) and unet and os.path.getsize(unet[0]) > 3.3e9
raise SystemExit(0 if ok else 1)
" 2>/dev/null
}

while ! weights_ready; do
  log "等待中 zero123=$(du -h "$ZERO" 2>/dev/null | cut -f1 || echo 0) midas=$(du -h "$MIDAS" 2>/dev/null | cut -f1 || echo 0)"
  sleep 120
done

log "权重就绪: zero123=$(du -h "$ZERO" | cut -f1) midas=$(du -h "$MIDAS" | cut -f1)"

clean_hf_cache_if_needed

if sd_ready; then
  log "SD1.5 已存在，跳过"
else
  while ! sd_ready; do
    log "拉取 SD1.5 ..."
    bash "$ROOT/scripts/fetch_sd15_local.sh" || true
    if sd_ready; then
      break
    fi
    log "SD1.5 未就绪，120s 后重试"
    sleep 120
  done
fi

if [[ -f "$ROOT/outputs/object_c/mesh.obj" ]]; then
  log "outputs/object_c/mesh.obj 已存在，跳过 Step 3"
  exit 0
fi

if pgrep -f "03_object_c_magic123.sh" >/dev/null 2>&1; then
  log "Step 3 已在运行，跳过"
  exit 0
fi

if [[ ! -f "$INPUT" ]]; then
  log "错误: 缺少 $INPUT"
  exit 1
fi

log "后台启动 Step 3 -> $STEP3_LOG"
nohup bash "$ROOT/scripts/03_object_c_magic123.sh" "$INPUT" >> "$STEP3_LOG" 2>&1 &
log "Step 3 PID=$!"
log "wait_for_step3 完成（Step 3 后台运行中）"
