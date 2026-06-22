#!/usr/bin/env bash
# 即时修复：杀冲突进程，启动 post_torch 单路径
set -uo pipefail
ROOT="${HOME}/hw3"
LOG="${ROOT}/logs/immediate_fix.log"
exec >>"${LOG}" 2>&1
log() { echo "[$(date '+%F %T')] $*"; }

log "=== 即时修复开始 ==="

# 杀所有 pip install torch（单路径用 wheel）
for pid in $(pgrep -f "pip install torch" 2>/dev/null || true); do
  log "KILL pip install torch pid=$pid"
  kill "$pid" 2>/dev/null || true
done
sleep 2
for pid in $(pgrep -f "pip install torch" 2>/dev/null || true); do
  kill -9 "$pid" 2>/dev/null || true
done

# 杀直接启动 Step3 但环境未就绪的进程
source "${HOME}/miniconda3/etc/profile.d/conda.sh"
set +u; conda activate hw3-2dgs; set -u
for pid in $(pgrep -f "03_object_c_magic123.sh" 2>/dev/null || true); do
  if ! python -c "import torch, gridencoder" 2>/dev/null; then
    log "KILL premature Step3 pid=$pid"
    kill "$pid" 2>/dev/null || true
  fi
done

wheel_valid() {
  local w="$1"
  [[ -f "$w" ]] || return 1
  local sz
  sz=$(stat -c%s "$w" 2>/dev/null || echo 0)
  [[ "$sz" -ge 2200000000 ]] || return 1
  unzip -t "$w" >/dev/null 2>&1
}

# torch wheel 完整且校验通过才停 aria2
W="/data/wheels/torch-2.0.1+cu118-cp310-cp310-linux_x86_64.whl"
if wheel_valid "$W"; then
  for pid in $(pgrep aria2c 2>/dev/null || true); do
    log "STOP aria2 (wheel validated) pid=$pid"
    kill "$pid" 2>/dev/null || true
  done
  rm -f /data/wheels/*.aria2 2>/dev/null || true
else
  wsz=$(stat -c%s "$W" 2>/dev/null || echo 0)
  log "torch wheel 未就绪/未校验 (${wsz} bytes)，保留 aria2"
  if ! pgrep -af "aria2c.*torch.*whl" >/dev/null 2>&1; then
    log "RESTART aria2 torch download"
    nohup aria2c -x16 -s16 -c -d /data/wheels \
      -o torch-2.0.1+cu118-cp310-cp310-linux_x86_64.whl \
      "https://download.pytorch.org/whl/cu118/torch-2.0.1%2Bcu118-cp310-cp310-linux_x86_64.whl" \
      >> "${ROOT}/logs/torch_aria2.log" 2>&1 &
  fi
fi

# 杀 CLIP 网络下载（只用 zero123 提取）
for pid in $(pgrep -f "aria2c.*ViT-L|fetch_clip" 2>/dev/null || true); do
  log "KILL CLIP download pid=$pid"
  kill "$pid" 2>/dev/null || true
done

# 删除损坏的小 CLIP 文件
C="/data/clip-cache/ViT-L-14.pt"
csz=$(stat -c%s "$C" 2>/dev/null || echo 0)
if [[ -f "$C" ]] && [[ "$csz" -lt 850000000 ]]; then
  log "REMOVE corrupt CLIP (${csz} bytes)"
  rm -f "$C" "$C.tmp" 2>/dev/null || true
fi

chmod +x "${ROOT}/scripts/hw3_post_torch.sh" "${ROOT}/scripts/watch_pipeline.sh"

# 启动 post_torch（wheel 校验通过且未运行）
if wheel_valid "$W" && ! pgrep -f 'bash.*hw3_post_torch\.sh' >/dev/null 2>&1; then
  log "START hw3_post_torch.sh"
  nohup bash "${ROOT}/scripts/hw3_post_torch.sh" >> "${ROOT}/logs/post_torch.log" 2>&1 &
elif ! wheel_valid "$W"; then
  log "post_torch 等待 torch wheel 下载完成"
elif pgrep -f 'bash.*hw3_post_torch\.sh' >/dev/null 2>&1; then
  log "post_torch already running"
fi

# 确保 watch loop 唯一
loops=$(pgrep -f 'while true.*watch_pipeline' 2>/dev/null | wc -l)
if [[ "$loops" -eq 0 ]]; then
  log "START watch loop"
  nohup bash -c 'while true; do bash ~/hw3/scripts/watch_pipeline.sh; sleep 600; done' >> ~/hw3/logs/watch_loop.log 2>&1 &
elif [[ "$loops" -gt 1 ]]; then
  log "DEDUP watch loops"
  pgrep -f 'while true.*watch_pipeline' | tail -n +2 | xargs -r kill 2>/dev/null || true
fi

log "=== 即时修复完成 ==="
