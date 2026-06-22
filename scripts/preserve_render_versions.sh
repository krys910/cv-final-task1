#!/usr/bin/env bash
# 保留两套融合渲染产出：quality（当前）与 legacy（服务器首版风格）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

QUALITY_DIR="$ROOT/outputs/fused_quality"
LEGACY_DIR="$ROOT/outputs/fused_legacy_20260617"
DIST="$ROOT/dist/hw3_submission_20260617"
FIGURES="$ROOT/report/figures"

if [[ -f .venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

echo "=== 1. 快照 quality 版（outputs/fused → outputs/fused_quality）==="
mkdir -p "$QUALITY_DIR"
for item in walkthrough.mp4 fused_scene.ply; do
  if [[ -f "$ROOT/outputs/fused/$item" ]]; then
    cp -f "$ROOT/outputs/fused/$item" "$QUALITY_DIR/"
    echo "  $item"
  fi
done
if [[ -d "$ROOT/outputs/fused/frames" ]]; then
  mkdir -p "$QUALITY_DIR/frames"
  cp -f "$ROOT/outputs/fused/frames/"*.png "$QUALITY_DIR/frames/" 2>/dev/null || true
  echo "  frames/ ($(ls "$QUALITY_DIR/frames" 2>/dev/null | wc -l | tr -d ' ') png)"
fi

echo "=== 2. 恢复 legacy 视频与报告截图（来自 6/17 打包）==="
mkdir -p "$LEGACY_DIR" "$FIGURES"
if [[ -f "$DIST/walkthrough.mp4" ]]; then
  cp -f "$DIST/walkthrough.mp4" "$LEGACY_DIR/walkthrough.mp4"
  echo "  walkthrough.mp4 (dist 原版 11MB)"
else
  echo "  警告: 未找到 $DIST/walkthrough.mp4"
fi
mkdir -p "$LEGACY_DIR/report_frames"
for idx in 0000 0030 0060 0090; do
  src="$DIST/figures/fused_frame_${idx}.png"
  if [[ ! -f "$src" ]]; then
    src="$DIST/hw3/report/figures/fused_frame_${idx}.png"
  fi
  if [[ -f "$src" ]]; then
    cp -f "$src" "$FIGURES/fused_frame_legacy_${idx}.png"
    cp -f "$src" "$LEGACY_DIR/report_frames/fused_frame_${idx}.png"
    echo "  fused_frame_legacy_${idx}.png"
  fi
done

echo "=== 3. 生成 legacy PLY + 120 帧（灰度融合 + 稀疏渲染）==="
python scripts/05_fuse_and_render.py --config configs/scene_layout_legacy.yaml

echo "=== 4. 若 dist 有原版视频，保留为权威 legacy mp4 ==="
if [[ -f "$DIST/walkthrough.mp4" ]]; then
  cp -f "$DIST/walkthrough.mp4" "$LEGACY_DIR/walkthrough.mp4"
fi

echo "=== 5. 同步 drive_upload 两套 ==="
mkdir -p "$ROOT/drive_upload/hw3_outputs/fused" "$ROOT/drive_upload/hw3_outputs/fused_legacy"
cp -f "$QUALITY_DIR/walkthrough.mp4" "$ROOT/drive_upload/hw3_outputs/fused/" 2>/dev/null || true
cp -f "$QUALITY_DIR/fused_scene.ply" "$ROOT/drive_upload/hw3_outputs/fused/" 2>/dev/null || true
cp -f "$LEGACY_DIR/walkthrough.mp4" "$ROOT/drive_upload/hw3_outputs/fused_legacy/" 2>/dev/null || true
cp -f "$LEGACY_DIR/fused_scene.ply" "$ROOT/drive_upload/hw3_outputs/fused_legacy/" 2>/dev/null || true

echo ""
echo "完成。目录说明见 outputs/README_RENDER_VERSIONS.md"
echo "  quality: $QUALITY_DIR"
echo "  legacy:  $LEGACY_DIR"
echo "  active:  outputs/fused/ (与 quality 同步，供默认脚本使用)"
