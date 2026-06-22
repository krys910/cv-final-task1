#!/usr/bin/env bash
# 将 outputs 中的大文件同步到 drive_upload/hw3_outputs，供 Google Drive 上传
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/drive_upload/hw3_outputs"

echo "=== 同步网盘提交物到 $DEST ==="

mkdir -p \
  "$DEST/object_a" \
  "$DEST/object_b" \
  "$DEST/object_c/magic123_data" \
  "$DEST/background" \
  "$DEST/fused" \
  "$DEST/fused_legacy"

copy_if_exists() {
  local src="$1" dst="$2"
  if [[ -f "$src" ]]; then
    cp -f "$src" "$dst"
    echo "  ✓ $(basename "$dst")"
  else
    echo "  ✗ 缺失: $src"
  fi
}

echo "[object_a]"
copy_if_exists "$ROOT/outputs/object_a/point_cloud.ply" "$DEST/object_a/point_cloud.ply"

echo "[object_b]"
for f in mesh.obj model.mtl texture_kd.jpg; do
  copy_if_exists "$ROOT/outputs/object_b/$f" "$DEST/object_b/$f"
done

echo "[object_c]"
copy_if_exists "$ROOT/outputs/object_c/mesh.obj" "$DEST/object_c/mesh.obj"
for f in main.png depth.png rgba.png; do
  copy_if_exists "$ROOT/outputs/object_c/magic123_data/$f" "$DEST/object_c/magic123_data/$f"
done

echo "[background]"
copy_if_exists "$ROOT/outputs/background/point_cloud.ply" "$DEST/background/point_cloud.ply"

echo "[fused - quality]"
copy_if_exists "$ROOT/outputs/fused/walkthrough.mp4" "$DEST/fused/walkthrough.mp4"
copy_if_exists "$ROOT/outputs/fused/fused_scene.ply" "$DEST/fused/fused_scene.ply"

echo "[fused_legacy]"
LEGACY="$ROOT/outputs/fused_legacy_20260617"
if [[ -d "$LEGACY" ]]; then
  copy_if_exists "$LEGACY/walkthrough.mp4" "$DEST/fused_legacy/walkthrough.mp4"
  copy_if_exists "$LEGACY/fused_scene.ply" "$DEST/fused_legacy/fused_scene.ply"
else
  echo "  (无 fused_legacy_20260617，跳过)"
fi

echo "[report PDF]"
copy_if_exists "$ROOT/report/HW3_technical_report.pdf" "$DEST/HW3_technical_report.pdf"

cat > "$DEST/README.txt" <<'EOF'
HW3 题目一 — 网盘提交物
========================

目录说明：
  object_a/point_cloud.ply       物体 A（COLMAP + 2DGS）
  object_b/mesh.obj + 贴图       物体 B（threestudio + SDS）
  object_c/mesh.obj              物体 C（Magic123）
  background/point_cloud.ply     背景 counter 场景（2DGS）
  fused/walkthrough.mp4          融合漫游视频（quality 版，主提交）
  fused/fused_scene.ply          融合点云（伪高斯，建议配合视频观看）
  fused_legacy/                  旧版融合备份（稀疏点云）
  HW3_technical_report.pdf       技术报告 PDF

查看建议：
  - 视频：直接播放 fused/walkthrough.mp4
  - PLY：SuperSplat / MeshLab；fused_scene 为稀疏伪高斯，非完整 2DGS 渲染

代码仓库见 GitHub README 中的链接。
EOF

echo ""
echo "=== 生成压缩包（可选手动上传）==="
ARCHIVE="$ROOT/drive_upload/hw3_outputs_$(date +%Y%m%d).tar.gz"
tar -czf "$ARCHIVE" -C "$ROOT/drive_upload" hw3_outputs
echo "压缩包: $ARCHIVE ($(du -sh "$ARCHIVE" | cut -f1))"

echo ""
echo "=== 目录总大小 ==="
du -sh "$DEST"
echo ""
echo "上传到 Google Drive："
echo "  bash scripts/upload_to_gdrive.sh"
echo "  或浏览器打开: https://drive.google.com/drive/folders/1-WuiJqW-zgrD1lmQ0A5e7zcUjujvDSbf"
