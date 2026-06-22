#!/usr/bin/env bash
# 从服务器拉取已打包的 Drive 上传目录（不含 wandb/日志）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${HW3_HOST:-ubuntu@36.103.199.63}"
PASS="${HW3_SSH_PASS:-}"
DEST="$ROOT/drive_upload"

ssh_cmd() {
  if [[ -n "$PASS" ]]; then sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$HOST" "$@"
  else ssh -o StrictHostKeyChecking=no "$HOST" "$@"
  fi
}
scp_cmd() {
  if [[ -n "$PASS" ]]; then sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$@"
  else scp -o StrictHostKeyChecking=no "$@"
  fi
}

mkdir -p "$DEST"
echo "=== 在服务器打包（若尚未打包）==="
ssh_cmd 'bash -s' <<'REMOTE'
set -e
mkdir -p ~/hw3/drive_upload/hw3_outputs/{object_a,object_b,object_c,background,fused}
cp ~/hw3/outputs/object_a/point_cloud.ply ~/hw3/drive_upload/hw3_outputs/object_a/
cp ~/hw3/outputs/object_b/* ~/hw3/drive_upload/hw3_outputs/object_b/
cp ~/hw3/outputs/object_c/mesh.obj ~/hw3/drive_upload/hw3_outputs/object_c/
cp -r ~/hw3/outputs/object_c/magic123_data ~/hw3/drive_upload/hw3_outputs/object_c/
cp ~/hw3/outputs/background/point_cloud.ply ~/hw3/drive_upload/hw3_outputs/background/
cp ~/hw3/outputs/fused/fused_scene.ply ~/hw3/outputs/fused/walkthrough.mp4 ~/hw3/drive_upload/hw3_outputs/fused/
cd ~/hw3/drive_upload && tar -czf hw3_outputs.tar.gz hw3_outputs
ls -lh hw3_outputs.tar.gz
REMOTE

echo "=== 下载到本地 $DEST ==="
scp_cmd "$HOST:~/hw3/drive_upload/hw3_outputs.tar.gz" "$DEST/"
cd "$DEST" && tar -xzf hw3_outputs.tar.gz
echo "完成: $DEST/hw3_outputs/"
find "$DEST/hw3_outputs" -type f -exec ls -lh {} \;
