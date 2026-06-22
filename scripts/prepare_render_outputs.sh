#!/usr/bin/env bash
# 融合 + 漫游渲染 + 报告截图 + 可选同步 drive_upload
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SYNC_DRIVE=0
PY_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --sync-drive) SYNC_DRIVE=1 ;;
    *) PY_ARGS+=("$arg") ;;
  esac
done

if [[ -f .venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

python -c "import plyfile, cv2, yaml, numpy, trimesh" 2>/dev/null || {
  pip install -q plyfile opencv-python pyyaml numpy trimesh
}

echo "=== Step 5: fuse + render ==="
# 渲染前备份当前 quality 产出，避免覆盖后无法恢复
if [[ -f "$ROOT/outputs/fused/walkthrough.mp4" ]]; then
  mkdir -p "$ROOT/outputs/fused_quality"
  cp -f "$ROOT/outputs/fused/walkthrough.mp4" "$ROOT/outputs/fused_quality/" 2>/dev/null || true
  cp -f "$ROOT/outputs/fused/fused_scene.ply" "$ROOT/outputs/fused_quality/" 2>/dev/null || true
fi
if ((${#PY_ARGS[@]})); then
  python scripts/05_fuse_and_render.py "${PY_ARGS[@]}"
else
  python scripts/05_fuse_and_render.py
fi

FRAMES_DIR="$ROOT/outputs/fused/frames"
FIGURES_DIR="$ROOT/report/figures"
mkdir -p "$FIGURES_DIR"

echo "=== Copy report figures ==="
for idx in 0000 0030 0060 0090; do
  src="$FRAMES_DIR/frame_${idx}.png"
  dst="$FIGURES_DIR/fused_frame_${idx}.png"
  cp "$src" "$dst"
  echo "  $dst"
done

if [[ "$SYNC_DRIVE" -eq 1 ]]; then
  DRIVE_FUSED="$ROOT/drive_upload/hw3_outputs/fused"
  mkdir -p "$DRIVE_FUSED"
  cp "$ROOT/outputs/fused/walkthrough.mp4" "$DRIVE_FUSED/"
  if [[ -f "$ROOT/outputs/fused/fused_scene.ply" ]]; then
    cp "$ROOT/outputs/fused/fused_scene.ply" "$DRIVE_FUSED/"
  fi
  echo "=== Synced to $DRIVE_FUSED ==="
fi

echo ""
echo "Done."
echo "  Video:    outputs/fused/walkthrough.mp4"
echo "  Figures:  report/figures/fused_frame_{0000,0030,0060,0090}.png"
[[ "$SYNC_DRIVE" -eq 1 ]] && echo "  Drive:    drive_upload/hw3_outputs/fused/"
