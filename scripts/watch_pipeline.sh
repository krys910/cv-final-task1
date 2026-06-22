#!/usr/bin/env bash
# 每 10 分钟由 watch_loop 调用；检查 pipeline 状态并在卡壳时自动修复
set -uo pipefail

ROOT="${HOME}/hw3"
LOG="${ROOT}/logs/watch_pipeline.log"
STATE="${ROOT}/logs/.watch_state"
POST_TORCH="${ROOT}/scripts/hw3_post_torch.sh"
STEP3_LOG="${ROOT}/logs/step03_object_c.log"
M123="${ROOT}/external/Magic123"
ZERO="${M123}/pretrained/zero123/105000.ckpt"
CLIP_CACHE="/data/clip-cache/ViT-L-14.pt"
CLIP_LINK="${HOME}/.cache/clip/ViT-L-14.pt"
CLIP_MIN=$((850 * 1000 * 1000))
TORCH_WHEEL="/data/wheels/torch-2.0.1+cu118-cp310-cp310-linux_x86_64.whl"
TORCH_WHEEL_MIN=$((2200 * 1000 * 1000))
MESH="${ROOT}/outputs/object_c/mesh.obj"

mkdir -p "${ROOT}/logs" "$(dirname "${CLIP_LINK}")" /data/clip-cache
touch "${LOG}"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "${LOG}"
}

conda_py() {
  source "${HOME}/miniconda3/etc/profile.d/conda.sh"
  set +u
  conda activate hw3-2dgs
  set -u
}

file_size() { stat -c%s "$1" 2>/dev/null || echo 0; }

torch_ok() {
  conda_py
  python -c "import torch; assert torch.__version__.startswith('2.0'); assert torch.cuda.is_available()" 2>/dev/null
}

ext_ok() {
  conda_py
  for m in gridencoder raymarching freqencoder shencoder; do
    python -c "import ${m}" 2>/dev/null || return 1
  done
}

clip_ok() {
  local sz
  sz=$(file_size "${CLIP_CACHE}")
  [[ -f "${CLIP_CACHE}" ]] && [[ "${sz}" -ge "${CLIP_MIN}" ]]
}

step3_running() {
  pgrep -f "${M123}/main.py" >/dev/null 2>&1 || pgrep -f "03_object_c_magic123.sh" >/dev/null 2>&1
}

gpu_util() {
  nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' '
}

last_iter() {
  grep -hoE 'iter [0-9]+|global_step[=: ]*[0-9]+|step [0-9]+/[0-9]+' "${STEP3_LOG}" "${M123}"/out/magic123-object_c-coarse/hw3/log*.txt 2>/dev/null | tail -1 || true
}

progress_stuck() {
  # 参数: key value — 若 30 分钟内 value 不变则视为卡住
  local key="$1" val="$2"
  local now prev prev_ts
  now=$(date +%s)
  prev=""
  prev_ts=""
  if [[ -f "${STATE}" ]]; then
    prev=$(grep "^${key}=" "${STATE}" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    prev_ts=$(grep "^${key}_ts=" "${STATE}" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  fi
  grep -v "^${key}=" "${STATE}" 2>/dev/null | grep -v "^${key}_ts=" > "${STATE}.tmp" 2>/dev/null || true
  mv "${STATE}.tmp" "${STATE}" 2>/dev/null || true
  echo "${key}=${val}" >> "${STATE}"
  echo "${key}_ts=${now}" >> "${STATE}"
  if [[ -n "${prev}" && "${prev}" == "${val}" && -n "${prev_ts}" ]]; then
    if (( now - prev_ts > 1800 )); then
      return 0
    fi
  fi
  return 1
}

extract_clip_from_zero123() {
  if ! torch_ok; then
    log "CLIP 提取跳过: torch 未就绪"
    return 1
  fi
  log "AUTO-FIX: 从 zero123 提取 CLIP 权重"
  rm -f "${CLIP_CACHE}" "${CLIP_CACHE}.tmp" 2>/dev/null || true
  conda_py
  python - <<'PY' >> "${LOG}" 2>&1
import os, torch
zero = "/data/ubuntu/hw3-pretrained/zero123/105000.ckpt"
if not os.path.isfile(zero):
    zero = os.path.expanduser("~/hw3/external/Magic123/pretrained/zero123/105000.ckpt")
out = "/data/clip-cache/ViT-L-14.pt"
os.makedirs(os.path.dirname(out), exist_ok=True)
sd = torch.load(zero, map_location="cpu")["state_dict"]
clip_sd = {k[len("cond_stage_model.model."):]: v for k, v in sd.items() if k.startswith("cond_stage_model.model.")}
if len(clip_sd) < 100:
    raise SystemExit(f"zero123 CLIP keys too few: {len(clip_sd)}")
torch.save(clip_sd, out + ".tmp")
os.replace(out + ".tmp", out)
print(f"CLIP OK: {out} ({os.path.getsize(out)} bytes, {len(clip_sd)} keys)")
PY
  ln -sfn "${CLIP_CACHE}" "${CLIP_LINK}"
}

restart_post_torch() {
  if [[ ! -x "${POST_TORCH}" ]]; then
    log "WARN: ${POST_TORCH} 不存在，跳过重启"
    return 1
  fi
  if pgrep -f "hw3_post_torch.sh" >/dev/null 2>&1; then
    log "post_torch 已在运行，不重复启动"
    return 0
  fi
  log "AUTO-FIX: 后台重启 hw3_post_torch.sh"
  nohup bash "${POST_TORCH}" >> "${ROOT}/logs/post_torch.log" 2>&1 &
}

kill_competing_torch_downloads() {
  # 单路径：aria2 wheel + post_torch；杀掉所有 pip install torch
  if pgrep -af "aria2c.*torch.*whl" >/dev/null 2>&1 || [[ ! -f "${TORCH_WHEEL}" ]] || ! unzip -t "${TORCH_WHEEL}" >/dev/null 2>&1; then
    local pids
    pids=$(pgrep -f "pip install torch" 2>/dev/null || true)
    if [[ -n "${pids}" ]]; then
      log "AUTO-FIX: 杀掉 pip install torch（单路径 aria2 wheel）: ${pids}"
      kill ${pids} 2>/dev/null || true
    fi
  fi
  # wheel 未就绪时确保 aria2 单实例运行
  if [[ ! -f "${TORCH_WHEEL}" ]] || ! unzip -t "${TORCH_WHEEL}" >/dev/null 2>&1; then
    local acount
    acount=$(pgrep -c -f "aria2c.*torch.*whl" 2>/dev/null || echo 0)
    if [[ "${acount}" -eq 0 ]]; then
      log "AUTO-FIX: 启动 aria2 torch 下载"
      nohup aria2c -x16 -s16 -c -d /data/wheels \
        -o torch-2.0.1+cu118-cp310-cp310-linux_x86_64.whl \
        "https://download.pytorch.org/whl/cu118/torch-2.0.1%2Bcu118-cp310-cp310-linux_x86_64.whl" \
        >> "${ROOT}/logs/torch_aria2.log" 2>&1 &
    elif [[ "${acount}" -gt 1 ]]; then
      log "AUTO-FIX: 杀掉重复 aria2"
      pgrep -f "aria2c.*torch.*whl" | tail -n +2 | xargs -r kill 2>/dev/null || true
    fi
  fi
}

# --- 主检查 ---
log "=== watch_pipeline 巡检 ==="

# 1) aria2 torch 下载进度
aria2_pct="none"
if pgrep -af "aria2c.*torch" >/dev/null 2>&1; then
  wsz=$(file_size "${TORCH_WHEEL}")
  if [[ "${wsz}" -gt 0 ]]; then
    aria2_pct="$(( wsz * 100 / TORCH_WHEEL_MIN ))%"
  else
    aria2_pct="0%"
  fi
  log "aria2 torch 下载: ${aria2_pct} ($(numfmt --to=iec "${wsz}" 2>/dev/null || echo "${wsz}B"))"
  if progress_stuck "aria2_torch" "${wsz}"; then
    log "WARN: aria2 torch 30min 无进展"
    kill_competing_torch_downloads
  fi
else
  log "aria2 torch: 未运行"
fi

# 2) post_torch
if pgrep -f 'bash.*hw3_post_torch\.sh' >/dev/null 2>&1; then
  log "hw3_post_torch.sh: 运行中"
  pt_line=$(tail -1 "${ROOT}/logs/post_torch.log" 2>/dev/null || echo "")
  if progress_stuck "post_torch_line" "${pt_line}"; then
    log "WARN: post_torch 30min 无日志进展"
  fi
else
  log "hw3_post_torch.sh: 未运行"
fi

kill_competing_torch_downloads

# 3) torch + extensions
if torch_ok; then
  tv=$(conda_py && python -c "import torch; print(torch.__version__)" 2>/dev/null)
  log "torch: OK (${tv})"
else
  log "torch: 未就绪"
fi

if ext_ok; then
  log "CUDA 扩展: 全部可 import"
else
  log "CUDA 扩展: 未全部就绪"
fi

# 4) CLIP
if clip_ok; then
  log "CLIP: OK ($(du -h "${CLIP_CACHE}" | cut -f1))"
  ln -sfn "${CLIP_CACHE}" "${CLIP_LINK}" 2>/dev/null || true
else
  log "CLIP: 缺失或不完整"
  sz=$(file_size "${CLIP_CACHE}")
  if [[ -f "${CLIP_CACHE}" ]] && [[ "${sz}" -lt "${CLIP_MIN}" ]]; then
    log "WARN: CLIP 文件损坏 (${sz} bytes)，将重新提取"
    rm -f "${CLIP_CACHE}" 2>/dev/null || true
  fi
  if [[ -f "${ZERO}" ]] && [[ "$(file_size "${ZERO}")" -gt $((10*1000*1000*1000)) ]]; then
    if ! pgrep -f 'fetch_clip|aria2c.*ViT-L' >/dev/null 2>&1; then
      extract_clip_from_zero123 || log "CLIP 提取失败"
    else
      log "CLIP 相关任务进行中，不重复启动"
    fi
  fi
fi

# 5) Step 3
if [[ -f "${MESH}" ]]; then
  log "Step3: 完成 mesh.obj 已存在"
elif step3_running; then
  gu=$(gpu_util)
  li=$(last_iter)
  log "Step3: 运行中 GPU=${gu}% iter=${li:-unknown}"
  if [[ "${gu}" == "0" ]] && progress_stuck "step3_iter" "${li:-none}"; then
    log "WARN: Step3 30min GPU=0 且 iter 无进展"
  fi
else
  log "Step3: 未运行"
  if torch_ok && ext_ok && clip_ok; then
    if [[ -x "${POST_TORCH}" ]]; then
      restart_post_torch
    elif [[ ! -f "${MESH}" ]] && ! pgrep -f "wait_for_step3" >/dev/null 2>&1; then
      log "AUTO-FIX: 启动 wait_for_step3_and_run.sh"
      nohup bash "${ROOT}/scripts/wait_for_step3_and_run.sh" >> "${ROOT}/logs/wait_step03.log" 2>&1 &
    fi
  elif torch_ok && ext_ok && ! clip_ok; then
    log "Step3 等待 CLIP 就绪"
  elif torch_ok && ! ext_ok; then
    restart_post_torch
  fi
fi

# 6) wandb
if [[ -f "${HOME}/.wandb_api_key" ]]; then
  wr=$(ls -1t "${ROOT}/wandb"/run-* 2>/dev/null | head -1 || ls -1t "${ROOT}/logs/wandb"/run-* 2>/dev/null | head -1 || echo "none")
  log "wandb: key OK, latest run=${wr}"
else
  log "wandb: 无 API key"
fi

# 7) 最近错误
err=$(grep -hiE 'error|traceback|failed|killed|terminated' "${ROOT}/logs/post_torch.log" "${STEP3_LOG}" 2>/dev/null | tail -3 || true)
if [[ -n "${err}" ]]; then
  log "最近错误: ${err}"
fi

log "=== 巡检结束 ==="
