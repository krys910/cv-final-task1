#!/usr/bin/env bash
# 预下载 rembg u2net 模型（Step 3 抠图用，~176MB）
set -euo pipefail

DEST="${U2NET_HOME:-$HOME/.u2net}/u2net.onnx"
LOG="${1:-$HOME/hw3/logs/fetch_rembg_u2net.log}"
mkdir -p "$(dirname "$LOG")" "$(dirname "$DEST")"

exec >>"$LOG" 2>&1
echo "=== [u2net] $(date) 开始 -> $DEST ==="

if [[ -f "$DEST" ]] && [[ "$(stat -c%s "$DEST")" -gt 100000000 ]]; then
  echo "=== 已存在 $(du -h "$DEST" | cut -f1) ==="
  exit 0
fi

URLS=(
  "https://ghfast.top/https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx"
  "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx"
)

for url in "${URLS[@]}"; do
  echo "=== try: $url ==="
  if curl -fL --retry 5 --retry-delay 20 --connect-timeout 60 --max-time 7200 \
    -C - -o "$DEST.part" "$url" && mv "$DEST.part" "$DEST"; then
    echo "=== [u2net] $(date) 完成 $(du -h "$DEST" | cut -f1) ==="
    exit 0
  fi
  rm -f "$DEST.part"
  sleep 15
done

echo "=== [u2net] $(date) 失败 ==="
exit 1
