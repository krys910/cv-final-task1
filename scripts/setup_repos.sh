#!/usr/bin/env bash
# 克隆作业所需第三方仓库到 external/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT="$ROOT/external"
mkdir -p "$EXT"
cd "$EXT"

clone_if_missing() {
  local dir="$1"
  local url="$2"
  if [[ ! -d "$dir" ]]; then
    echo "Cloning $url -> $dir"
    git clone --depth 1 "$url" "$dir"
  else
    echo "Already exists: $dir"
  fi
}

clone_if_missing "2d-gaussian-splatting" "https://github.com/hbb1/2d-gaussian-splatting.git"
clone_if_missing "threestudio" "https://github.com/threestudio-project/threestudio.git"
clone_if_missing "Magic123" "https://github.com/guochengqian/Magic123.git"

echo ""
echo "Next steps:"
echo "  1. Install 2DGS submodules: cd external/2d-gaussian-splatting && pip install -r requirements.txt"
echo "  2. Install threestudio: cd external/threestudio && pip install -e ."
echo "  3. Follow Magic123 README for its environment"
echo "  4. Install COLMAP: brew install colmap  (macOS)  or apt install colmap (Linux)"
