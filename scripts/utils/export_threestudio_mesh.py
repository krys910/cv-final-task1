#!/usr/bin/env python3
"""从 threestudio checkpoint 导出 Mesh（launch.py --export + 复制 obj/mtl/贴图）。"""

from __future__ import annotations

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml


def resolve_trial_dir(exp_dir: Path) -> Path:
    """解析 trial 目录（支持 tag 或 tag@timestamp）。"""
    exp_dir = exp_dir.resolve()
    if (exp_dir / "ckpts").is_dir():
        return exp_dir

    tag = exp_dir.name.split("@")[0]
    parent = exp_dir.parent
    candidates = sorted(
        parent.glob(f"{tag}@*"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError(f"未找到 trial 目录: {parent}/{tag}@*")
    return candidates[0]


def find_checkpoint(trial_dir: Path) -> Path:
    ckpt_dir = trial_dir / "ckpts"
    if not ckpt_dir.is_dir():
        raise FileNotFoundError(f"缺少 ckpts 目录: {ckpt_dir}")

    for name in ("last.ckpt",):
        p = ckpt_dir / name
        if p.is_file():
            return p

    ckpts = sorted(ckpt_dir.glob("*.ckpt"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not ckpts:
        raise FileNotFoundError(f"未找到 checkpoint: {ckpt_dir}")
    return ckpts[0]


def read_parsed_config(trial_dir: Path) -> dict:
    cfg_path = trial_dir / "configs" / "parsed.yaml"
    if not cfg_path.is_file():
        raise FileNotFoundError(f"缺少 parsed.yaml: {cfg_path}")
    with cfg_path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def find_exported_mesh(trial_dir: Path) -> Path:
    save_dir = trial_dir / "save"
    export_dirs = sorted(
        save_dir.glob("it*-export"),
        key=lambda p: int(re.search(r"it(\d+)-export", p.name).group(1)),
        reverse=True,
    )
    for export_dir in export_dirs:
        obj = export_dir / "model.obj"
        if obj.is_file() and obj.stat().st_size > 0:
            return obj
    raise FileNotFoundError(f"未在 {save_dir} 找到已导出的 model.obj")


def run_threestudio_export(
    threestudio_dir: Path,
    trial_dir: Path,
    ckpt: Path,
) -> None:
    rel_ckpt = os.path.relpath(ckpt.resolve(), threestudio_dir.resolve())
    parsed_cfg = trial_dir / "configs" / "parsed.yaml"
    if not parsed_cfg.is_file():
        raise FileNotFoundError(f"缺少 parsed.yaml: {parsed_cfg}")

    cmd = [
        sys.executable,
        "launch.py",
        "--config",
        str(parsed_cfg.resolve()),
        "--export",
        "--gpu",
        "0",
        f"resume={rel_ckpt}",
        "system.exporter.save_video=false",
    ]
    print("=== threestudio export ===")
    print(" ".join(cmd))
    subprocess.run(cmd, cwd=threestudio_dir, check=True)


def copy_mesh_assets(src_obj: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    export_dir = src_obj.parent

    shutil.copy2(src_obj, output)
    print(f"Copied {src_obj} -> {output}")

    # 同步 mtl / 贴图，并将 model.obj 重命名为 mesh.obj 时修正 mtl 引用
    mtl_src = export_dir / "model.mtl"
    if mtl_src.is_file():
        mtl_dst = output.parent / "mesh.mtl"
        shutil.copy2(mtl_src, mtl_dst)
        print(f"Copied {mtl_src} -> {mtl_dst}")

    for extra in export_dir.iterdir():
        if extra.name in {"model.obj", "model.mtl"}:
            continue
        if extra.suffix.lower() in {".jpg", ".jpeg", ".png"} and extra.is_file():
            dst = output.parent / extra.name
            shutil.copy2(extra, dst)
            print(f"Copied {extra} -> {dst}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--exp_dir", required=True, help="trial 目录或 tag 前缀路径")
    parser.add_argument("--output", required=True, help="输出 mesh.obj 路径")
    parser.add_argument(
        "--threestudio",
        default=None,
        help="threestudio 根目录，默认 <project>/external/threestudio",
    )
    parser.add_argument(
        "--skip-export",
        action="store_true",
        help="若 save/it*-export/model.obj 已存在则跳过 launch.py --export",
    )
    args = parser.parse_args()

    output = Path(args.output).resolve()
    trial_dir = resolve_trial_dir(Path(args.exp_dir))
    parsed = read_parsed_config(trial_dir)

    if args.threestudio:
        threestudio_dir = Path(args.threestudio).resolve()
    else:
        threestudio_dir = Path(__file__).resolve().parents[2] / "external" / "threestudio"

    try:
        src_obj = find_exported_mesh(trial_dir)
        print(f"Found existing export: {src_obj}")
    except FileNotFoundError:
        if args.skip_export:
            raise
        ckpt = find_checkpoint(trial_dir)
        print(f"Using checkpoint: {ckpt}")
        run_threestudio_export(threestudio_dir, trial_dir, ckpt)
        src_obj = find_exported_mesh(trial_dir)

    copy_mesh_assets(src_obj, output)
    print(f"完成: {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
