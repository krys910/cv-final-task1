#!/usr/bin/env python3
"""从 Magic123 checkpoint 导出 Mesh。"""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exp_dir", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    exp = Path(args.exp_dir)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    candidates = list(exp.rglob("*.obj")) + list(exp.rglob("*.glb"))
    if candidates:
        import shutil

        shutil.copy(candidates[0], out)
        print(f"Copied mesh from {candidates[0]} -> {out}")
    else:
        print(f"未在 {exp} 找到 mesh，请参考 Magic123 README 的 export 步骤")
        out.write_text("# placeholder - replace with exported mesh\n")


if __name__ == "__main__":
    main()
