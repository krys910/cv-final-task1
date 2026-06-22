#!/usr/bin/env bash
# 从云服务器同步提交用素材到本地
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${HW3_HOST:-ubuntu@36.103.199.63}"
PASS="${HW3_SSH_PASS:-}"
SSH_OPTS=(-o StrictHostKeyChecking=no)

ssh_cmd() {
  if [[ -n "$PASS" ]]; then
    sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" "$HOST" "$@"
  else
    ssh "${SSH_OPTS[@]}" "$HOST" "$@"
  fi
}

mkdir -p "$ROOT/outputs/fused" "$ROOT/logs" "$ROOT/report/figures"

echo "=== 融合视频与帧 ==="
for f in walkthrough.mp4; do
  if [[ -n "$PASS" ]]; then
    sshpass -p "$PASS" scp "${SSH_OPTS[@]}" "$HOST:~/hw3/outputs/fused/$f" "$ROOT/outputs/fused/"
  else
    scp "${SSH_OPTS[@]}" "$HOST:~/hw3/outputs/fused/$f" "$ROOT/outputs/fused/"
  fi
done
for i in 0000 0030 0060 0090; do
  if [[ -n "$PASS" ]]; then
    sshpass -p "$PASS" scp "${SSH_OPTS[@]}" "$HOST:~/hw3/outputs/fused/frames/frame_${i}.png" \
      "$ROOT/report/figures/fused_frame_${i}.png" 2>/dev/null || true
  fi
done

echo "=== 训练日志（曲线用）==="
for f in step01_train.log step03_object_c.log step03_fine.log; do
  ssh_cmd "cat ~/hw3/logs/$f" > "$ROOT/logs/$f" 2>/dev/null || echo "skip $f"
done

echo "=== 生成曲线图 ==="
"$ROOT/.venv/bin/python" "$ROOT/scripts/utils/plot_training_curves.py" 2>/dev/null \
  || python3 "$ROOT/scripts/utils/plot_training_curves.py"

echo "完成。请检查 outputs/fused/ 与 report/figures/"
