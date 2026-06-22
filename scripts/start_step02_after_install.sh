#!/usr/bin/env bash
# tinycudann 安装完成后自动启动 Step 2（物体 B threestudio）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs/start_step02_after_install.log"
PROMPT="${1:-a light blue plastic mug with handle, matte finish, studio lighting, high quality 3D object}"

exec >>"$LOG" 2>&1
echo "=== [step02-wait] $(date) 等待 threestudio 安装完成 ==="

while pgrep -f "install_threestudio.sh" >/dev/null 2>&1; do
  sleep 30
done

source ~/miniconda3/etc/profile.d/conda.sh
conda activate hw3-2dgs

if ! python -c "from threestudio.utils.config import parse_structured" 2>/dev/null; then
  echo "错误: threestudio 仍未就绪，请检查 logs/install_threestudio.log"
  exit 1
fi

if pgrep -f "launch.py.*dreamfusion" >/dev/null 2>&1; then
  echo "Step 2 已在运行，跳过"
  exit 0
fi

echo "=== [step02-wait] $(date) 启动 Step 2 ==="
cd "$ROOT"
exec bash scripts/02_object_b_threestudio.sh "$PROMPT"
