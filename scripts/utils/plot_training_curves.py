#!/usr/bin/env python3
"""从本地训练日志解析 loss 并生成报告用曲线图（WandB 离线回放的可视化替代）。"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import matplotlib.pyplot as plt


def parse_magic123(log_path: Path) -> tuple[list[int], list[float]]:
    steps, losses = [], []
    pat = re.compile(r"Train \[Step\] (\d+)/\d+, loss=([\d.]+)")
    for line in log_path.read_text(errors="ignore").splitlines():
        m = pat.search(line)
        if m:
            steps.append(int(m.group(1)))
            losses.append(float(m.group(2)))
    return steps, losses


def parse_2dgs(log_path: Path) -> tuple[list[int], list[float]]:
    steps, losses = [], []
    pat = re.compile(
        r"Training progress:.*?(\d+)/(\d+).*?Loss=([\d.]+)"
    )
    for line in log_path.read_text(errors="ignore").splitlines():
        m = pat.search(line)
        if m:
            steps.append(int(m.group(1)))
            losses.append(float(m.group(3)))
    return steps, losses


def downsample(xs: list, ys: list, max_pts: int = 400) -> tuple[list, list]:
    if len(xs) <= max_pts:
        return xs, ys
    idx = [int(i * (len(xs) - 1) / (max_pts - 1)) for i in range(max_pts)]
    return [xs[i] for i in idx], [ys[i] for i in idx]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--logs", default="logs", help="日志目录")
    parser.add_argument("--out", default="report/figures/wandb_curves.png")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    logs = root / args.logs
    out = root / args.out
    out.parent.mkdir(parents=True, exist_ok=True)

    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    fig.suptitle("Training Loss Curves (parsed from local logs)", fontsize=14)

    specs = [
        ("Object A (2DGS)", logs / "step01_train.log", parse_2dgs, axes[0, 0]),
        ("Object C coarse (Magic123)", logs / "step03_object_c.log", parse_magic123, axes[0, 1]),
        ("Object C fine DMTet-256", logs / "step03_fine.log", parse_magic123, axes[1, 0]),
    ]

    for title, path, parser_fn, ax in specs:
        if not path.exists():
            ax.set_title(f"{title}\n(missing log)")
            ax.axis("off")
            continue
        xs, ys = parser_fn(path)
        if not xs:
            ax.set_title(f"{title}\n(no data)")
            continue
        xs, ys = downsample(xs, ys)
        ax.plot(xs, ys, linewidth=1.2)
        ax.set_title(title)
        ax.set_xlabel("Step / Iteration")
        ax.set_ylabel("Loss")
        ax.grid(True, alpha=0.3)

    ax = axes[1, 1]
    ax.text(
        0.05,
        0.55,
        "Object B (threestudio / SDS)\n"
        "  10,000 steps, DreamFusion-SD\n"
        "  mesh.obj 12.2 MB exported\n"
        "  WandB not fully synced during train\n\n"
        "Background (2DGS counter)\n"
        "  30k iterations, 148 MB PLY\n"
        "  Same 2DGS pipeline as object A",
        fontsize=11,
        va="center",
        family="monospace",
    )
    ax.axis("off")
    ax.set_title("Object B & Background (notes)")

    plt.tight_layout()
    fig.savefig(out, dpi=150, bbox_inches="tight")
    print(f"Saved {out}")


if __name__ == "__main__":
    main()
