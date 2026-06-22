#!/usr/bin/env bash
# 一次性：状态检查 + 修复 + 部署监控
set -uo pipefail

ROOT="${HOME}/hw3"
LOG="${ROOT}/logs/immediate_fix.log"
mkdir -p "${ROOT}/logs" "${ROOT}/scripts"

exec >>"${LOG}" 2>&1
echo "[$(date '+%F %T')] === immediate status + fix ==="

log() { echo "[$(date '+%F %T')] $*"; }

# --- STATUS ---
log "--- aria2 torch ---"
if pgrep -af "aria2c.*torch" >/dev/null; then
  W="/data/wheels/torch-2.0.1+cu118-cp310-cp310-linux_x86_64.whl"
  sz=$(stat -c%s "$W" 2>/dev/null || echo 0)
  pct=$(( sz * 100 / 2400000000 ))
  log "aria2 running, wheel ${sz} bytes (~${pct}%)"
else
  log "aria2 torch: not running"
fi

log "--- pip install torch (competing?) ---"
pgrep -af "pip install torch" || log "no pip torch install"

log "--- hw3_post_torch ---"
pgrep -af "hw3_post_torch" || log "post_torch not running"
test -f "${ROOT}/scripts/hw3_post_torch.sh" && log "post_torch script exists" || log "post_torch script MISSING"

log "--- Step3 ---"
pgrep -af "Magic123/main.py|03_object_c" || log "Step3 not running"

log "--- GPU ---"
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv 2>/dev/null || true

log "--- mesh.obj ---"
find "${ROOT}/outputs" -name mesh.obj -ls 2>/dev/null || log "no mesh.obj"

source "${HOME}/miniconda3/etc/profile.d/conda.sh"
set +u; conda activate hw3-2dgs; set -u
python -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())" 2>&1 || log "torch import fail"

log "--- wandb ---"
test -f ~/.wandb_api_key && log "wandb key ok" || log "no wandb key"
ls -lt "${ROOT}/wandb" 2>/dev/null | head -4 || true

# --- FIX: kill duplicate torch downloads ---
# Single path: aria2 wheel -> hw3_post_torch; kill pip install torch if aria2 active
if pgrep -af "aria2c.*torch.*whl" >/dev/null; then
  pids=$(pgrep -f "pip install torch" 2>/dev/null || true)
  if [[ -n "${pids}" ]]; then
    log "FIX: killing competing pip install torch: $pids"
    kill $pids 2>/dev/null || true
    sleep 2
  fi
fi

# Also kill stray bash wrappers that only run pip install torch 2.4
for pid in $(pgrep -f "pip install torch==2.4" 2>/dev/null || true); do
  log "FIX: kill pip torch 2.4 pid $pid"
  kill "$pid" 2>/dev/null || true
done

# --- Ensure post_torch running if torch wheel complete but not installed ---
W="/data/wheels/torch-2.0.1+cu118-cp310-cp310-linux_x86_64.whl"
wsz=$(stat -c%s "$W" 2>/dev/null || echo 0)
if [[ "$wsz" -ge 2200000000 ]] && ! python -c "import torch; assert torch.__version__.startswith('2.0')" 2>/dev/null; then
  if ! pgrep -f "hw3_post_torch" >/dev/null && [[ -x "${ROOT}/scripts/hw3_post_torch.sh" ]]; then
    log "FIX: wheel complete, starting post_torch"
    nohup bash "${ROOT}/scripts/hw3_post_torch.sh" >> "${ROOT}/logs/post_torch.log" 2>&1 &
  fi
fi

# --- Kill duplicate watch loops ---
watch_pids=$(pgrep -f "while true.*watch_pipeline" 2>/dev/null || true)
if [[ -n "$watch_pids" ]]; then
  count=$(echo "$watch_pids" | wc -l)
  if [[ "$count" -gt 1 ]]; then
    log "FIX: killing duplicate watch loops"
    echo "$watch_pids" | tail -n +2 | xargs -r kill 2>/dev/null || true
  fi
fi

chmod +x "${ROOT}/scripts/watch_pipeline.sh"

# Start watch loop if not running
if ! pgrep -f "while true.*watch_pipeline" >/dev/null; then
  log "Starting watch loop (10min interval)"
  nohup bash -c 'while true; do bash ~/hw3/scripts/watch_pipeline.sh; sleep 600; done' >> ~/hw3/logs/watch_loop.log 2>&1 &
  log "watch loop PID=$!"
else
  log "watch loop already running"
fi

# Run first watch now
bash "${ROOT}/scripts/watch_pipeline.sh"

echo "[$(date '+%F %T')] === immediate fix done ==="
