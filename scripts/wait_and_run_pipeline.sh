#!/usr/bin/env bash
# 等待 bootstrap 完成后自动启动流水线
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_LOG="$ROOT/bootstrap_fast.log"
PIPE_LOG="$ROOT/logs/pipeline.log"
WAIT_LOG="$ROOT/logs/wait_bootstrap.log"

mkdir -p "$ROOT/logs"

echo "[$(date '+%F %T')] 等待 bootstrap 完成 ..." | tee -a "$WAIT_LOG"

for i in $(seq 1 360); do
  if grep -q "=== \[fast\] 完成 ===" "$BOOT_LOG" 2>/dev/null; then
    echo "[$(date '+%F %T')] bootstrap 已完成，启动流水线" | tee -a "$WAIT_LOG"
    exec /bin/bash "$ROOT/scripts/run_full_pipeline.sh" >> "$PIPE_LOG" 2>&1
  fi
  if ! pgrep -f "server_bootstrap_fast.sh|bootstrap_step45|clone_magic123_and_continue|install_2dgs_submodules" >/dev/null && \
     ! pgrep -f "conda env create -f environment.yml" >/dev/null && \
     ! pgrep -f "wget.*360_v2.zip" >/dev/null; then
    if grep -q "Error\|failed\|FAILED" "$BOOT_LOG" 2>/dev/null && \
       ! grep -q "=== \[fast\] 完成 ===" "$BOOT_LOG" 2>/dev/null; then
      echo "[$(date '+%F %T')] bootstrap 可能失败，请检查 $BOOT_LOG" | tee -a "$WAIT_LOG"
      exit 1
    fi
  fi
  sleep 60
done

echo "[$(date '+%F %T')] 等待超时（6小时）" | tee -a "$WAIT_LOG"
exit 1
