#!/usr/bin/env bash
# 物体 A: COLMAP 位姿估计 + 2DGS 重建
# 用法: bash scripts/01_object_a_colmap_2dgs.sh [图像目录]
set -euo pipefail
export QT_QPA_PLATFORM=offscreen

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/utils/wandb_env.sh"
IMAGE_DIR="${1:-$ROOT/data/object_a/images}"
WORK="$ROOT/outputs/object_a"
COLMAP="$WORK/colmap"
DGS="$ROOT/external/2d-gaussian-splatting"

mkdir -p "$WORK" "$COLMAP/sparse" "$COLMAP/images"

if [[ ! -d "$IMAGE_DIR" ]] || [[ -z "$(ls -A "$IMAGE_DIR" 2>/dev/null)" ]]; then
  echo "错误: 请将手机拍摄的多视角图片放入 $IMAGE_DIR"
  exit 1
fi

echo "=== Step 1: 准备图像 ==="
cp -n "$IMAGE_DIR"/* "$COLMAP/images/" 2>/dev/null || cp "$IMAGE_DIR"/* "$COLMAP/images/"
echo "图像数量: $(ls -1 "$COLMAP/images" | wc -l)"

echo "=== Step 2: COLMAP SfM ==="
rm -f "$COLMAP/database.db"
rm -rf "$COLMAP/sparse/"*

colmap feature_extractor \
  --database_path "$COLMAP/database.db" \
  --image_path "$COLMAP/images" \
  --ImageReader.single_camera 1 \
  --SiftExtraction.use_gpu 0 \
  --SiftExtraction.max_image_size 2000

# 环绕视频抽帧：顺序匹配比 exhaustive 更稳
colmap sequential_matcher \
  --database_path "$COLMAP/database.db" \
  --SiftMatching.use_gpu 0 \
  --SequentialMatching.overlap 15 \
  --SequentialMatching.quadratic_overlap 1

colmap mapper \
  --database_path "$COLMAP/database.db" \
  --image_path "$COLMAP/images" \
  --output_path "$COLMAP/sparse" \
  --Mapper.multiple_models 0 \
  --Mapper.min_num_matches 15

if [[ ! -f "$COLMAP/sparse/0/cameras.bin" ]]; then
  echo "错误: COLMAP 重建失败，未生成 sparse/0/cameras.bin"
  exit 1
fi

echo "=== Step 3: COLMAP 重建统计 ==="
if [[ -f "$COLMAP/sparse/0/images.txt" ]]; then
  grep "^# Number of images:" "$COLMAP/sparse/0/images.txt" || true
  grep "^# Number of points:" "$COLMAP/sparse/0/points3D.txt" || true
else
  colmap model_converter \
    --input_path "$COLMAP/sparse/0" \
    --output_path "$COLMAP/sparse/0" \
    --output_type TXT
  grep "^# Number of images:" "$COLMAP/sparse/0/images.txt" || true
fi

echo "=== Step 3b: 去畸变 → PINHOLE（2DGS 仅支持 undistorted）==="
UNDIST="$COLMAP/undistorted"
rm -rf "$UNDIST"
colmap image_undistorter \
  --image_path "$COLMAP/images" \
  --input_path "$COLMAP/sparse/0" \
  --output_path "$UNDIST" \
  --output_type COLMAP
# image_undistorter 输出 sparse/*.bin，2DGS 需要 sparse/0/
mkdir -p "$UNDIST/sparse/0"
if [[ -f "$UNDIST/sparse/cameras.bin" ]]; then
  mv "$UNDIST/sparse/"*.bin "$UNDIST/sparse/0/"
fi
if [[ ! -f "$UNDIST/sparse/0/cameras.bin" ]]; then
  echo "错误: 去畸变失败，未生成 $UNDIST/sparse/0/cameras.bin"
  exit 1
fi

echo "=== Step 4: 2DGS 训练（数据: colmap/undistorted）==="
cd "$DGS"
python train.py -s "$UNDIST" -m "$WORK/model" --iterations 10000

echo "=== Step 5: 导出点云 ==="
python render.py -m "$WORK/model" --skip_train --skip_test
cp "$WORK/model/point_cloud/iteration_10000/point_cloud.ply" "$WORK/point_cloud.ply"

echo "完成: $WORK/point_cloud.ply"
