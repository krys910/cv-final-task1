#!/usr/bin/env python3
"""使用 rembg 去除单图背景，供 Magic123 使用。"""

import argparse
from pathlib import Path

from PIL import Image


def main():
    parser = argparse.ArgumentParser(description="Remove image background")
    parser.add_argument("--input", required=True, help="Input photo path")
    parser.add_argument("--output", required=True, help="Output RGBA PNG path")
    args = parser.parse_args()

    inp = Path(args.input)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(inp).convert("RGBA")

    try:
        from rembg import remove

        result = remove(img)
    except ImportError:
        print("rembg 未安装，复制原图（请手动抠图）")
        result = img

    result.save(out)
    print(f"Saved: {out}")


if __name__ == "__main__":
    main()
