#!/usr/bin/env bash
# 将 hw3 重要产出上传到 Google Drive 指定文件夹
# 前置：本机可访问 Google（需 VPN），且已 rclone 授权一次
set -euo pipefail

DRIVE_FOLDER_ID="${DRIVE_FOLDER_ID:-1-WuiJqW-zgrD1lmQ0A5e7zcUjujvDSbf}"
REMOTE_NAME="${RCLONE_REMOTE:-hw3gdrive}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/drive_upload/hw3_outputs}"

if [[ ! -d "$SRC" ]]; then
  echo "缺少目录: $SRC"
  echo "可先运行: HW3_SSH_PASS='...' bash scripts/fetch_drive_bundle.sh"
  exit 1
fi

if ! rclone listremotes | grep -q "^${REMOTE_NAME}:"; then
  rclone config create "$REMOTE_NAME" drive scope drive config_is_local true
fi

echo "=== 请确保已开 VPN，将弹出浏览器完成 Google 授权（仅首次）==="
printf 'y\n' | rclone config reconnect "${REMOTE_NAME}:" || true

echo "=== 上传到 Drive 文件夹 $DRIVE_FOLDER_ID ==="
rclone copy "$SRC" "${REMOTE_NAME}:hw3_outputs" \
  --drive-root-folder-id "$DRIVE_FOLDER_ID" \
  --progress \
  --transfers 4

echo "=== 完成。请在浏览器打开你的 Drive 文件夹确认 ==="
echo "https://drive.google.com/drive/folders/${DRIVE_FOLDER_ID}"
