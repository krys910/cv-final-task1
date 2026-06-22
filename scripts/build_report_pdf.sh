#!/usr/bin/env bash
# 编译中文 PDF 报告（需 xelatex + ctex）
set -euo pipefail
cd "$(dirname "$0")/../latex"
if ! command -v xelatex >/dev/null; then
  echo "请安装 MacTeX 或使用 Overleaf 打开 main.tex"
  exit 1
fi
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
echo "PDF: $(pwd)/main.pdf"
