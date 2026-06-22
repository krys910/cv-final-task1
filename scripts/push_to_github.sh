#!/usr/bin/env bash
# 初始化 Git 并推送到 GitHub（需已安装 gh 并完成 gh auth login）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GITHUB_USER="${GITHUB_USER:-kryskatrina}"
REPO_NAME="${REPO_NAME:-cv-hw3}"
VISIBILITY="${VISIBILITY:-public}"

if ! command -v gh >/dev/null 2>&1; then
  echo "未安装 GitHub CLI。请先运行: brew install gh && gh auth login"
  exit 1
fi

if [[ ! -d .git ]]; then
  git init -b main
fi

git add -A
if git diff --cached --quiet; then
  echo "无新变更可提交"
else
  git commit -m "$(cat <<'EOF'
HW3: 2DGS + AIGC 多源资产融合项目

含脚本、配置、报告与文档；大体积 outputs 见 Google Drive。
EOF
)"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  gh repo create "$REPO_NAME" --public --source=. --remote=origin --push \
    --description "CV HW3: 2DGS + AIGC multi-asset scene fusion"
else
  git push -u origin main
fi

echo ""
echo "GitHub: https://github.com/${GITHUB_USER}/${REPO_NAME}"
