#!/usr/bin/env bash
# 后台获取 Magic123（不阻塞 bootstrap / 流水线）
# 用法: nohup bash scripts/fetch_magic123.sh >> logs/fetch_magic123.log 2>&1 &
set -euo pipefail

cd ~/hw3
LOG="$HOME/hw3/logs/fetch_magic123.log"
mkdir -p logs
exec >>"$LOG" 2>&1

TARGET="$HOME/hw3/external/Magic123"
TMP="$HOME/hw3/external/.Magic123_fetch"

if [[ -f "$TARGET/README.md" ]]; then
  echo "=== [magic123] $(date) 已存在，跳过 ==="
  exit 0
fi

echo "=== [magic123] $(date) 开始 ==="
rm -rf "$TMP" "$HOME/hw3/external/Magic123.zip" "$HOME/hw3/external/Magic123-main"

try_git() {
  local url="$1"
  echo "=== [magic123] git clone: $url ==="
  rm -rf "$TMP"
  if git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 \
    -c http.lowSpeedLimit=500 -c http.lowSpeedTime=1200 \
    clone --depth 1 "$url" "$TMP"; then
    [[ -f "$TMP/README.md" ]] && return 0
  fi
  rm -rf "$TMP"
  return 1
}

try_zip() {
  local url="$1"
  local zip="$HOME/hw3/external/Magic123.zip"
  echo "=== [magic123] curl zip: $url ==="
  rm -f "$zip"
  if curl -fL --retry 3 --retry-delay 10 --connect-timeout 30 --max-time 7200 \
    -o "$zip" "$url"; then
    if unzip -t "$zip" >/dev/null 2>&1; then
      rm -rf "$TMP"
      unzip -q "$zip" -d "$HOME/hw3/external"
      mv "$HOME/hw3/external/Magic123-main" "$TMP"
      rm -f "$zip"
      [[ -f "$TMP/README.md" ]] && return 0
    fi
    echo "ZIP 校验失败，大小: $(du -h "$zip" | cut -f1)"
  fi
  rm -f "$zip" "$HOME/hw3/external/Magic123-main"
  rm -rf "$TMP"
  return 1
}

# 按成功率排序尝试（国内服务器优先镜像）
MIRRORS=(
  "git|https://gitclone.com/github.com/guochengqian/Magic123.git"
  "git|https://ghfast.top/https://github.com/guochengqian/Magic123.git"
  "git|https://github.com/guochengqian/Magic123.git"
  "zip|https://ghfast.top/https://github.com/guochengqian/Magic123/archive/refs/heads/main.zip"
  "zip|https://github.com/guochengqian/Magic123/archive/refs/heads/main.zip"
)

for entry in "${MIRRORS[@]}"; do
  kind="${entry%%|*}"
  url="${entry#*|}"
  if [[ "$kind" == "git" ]]; then
    try_git "$url" && break
  else
    try_zip "$url" && break
  fi
done

if [[ ! -f "$TMP/README.md" ]]; then
  echo "=== [magic123] $(date) 全部方式失败，物体 C 需稍后手动重试 ==="
  echo "  或从本机 rsync: rsync -avz external/Magic123 ubuntu@SERVER:~/hw3/external/"
  exit 1
fi

rm -rf "$TARGET"
mv "$TMP" "$TARGET"
echo "=== [magic123] $(date) 完成: $(du -sh "$TARGET" | cut -f1) ==="
