#!/usr/bin/env bash
# 从环绕视频抽帧，供物体 A (COLMAP + 2DGS) 使用
# 用法: bash scripts/extract_frames.sh /path/to/cup_video.mp4 [fps]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIDEO="${1:?请提供视频路径，例如: bash scripts/extract_frames.sh ~/Movies/cup.mp4}"
FPS="${2:-2}"   # 每秒抽 2 帧，30s 视频约 60 张
OUT="$ROOT/data/object_a/images"

mkdir -p "$OUT"

if ! command -v ffmpeg &>/dev/null; then
  echo "请先安装 ffmpeg: brew install ffmpeg"
  exit 1
fi

# 清空旧图（可选）
read -p "清空 $OUT 已有图片? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -f "$OUT"/*
fi

ffmpeg -i "$VIDEO" -vf "fps=$FPS" -q:v 2 "$OUT/frame_%04d.jpg"

COUNT=$(ls -1 "$OUT"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "完成: 共 $COUNT 张 -> $OUT"
echo "建议数量: 50–100 张。过多可增大 fps 间隔，例如 fps=1 或每 15 帧抽 1 张"
