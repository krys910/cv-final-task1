#!/usr/bin/env python3
"""将本地训练日志中的 loss 回放到 WandB（需 ~/.wandb_api_key 或 WANDB_API_KEY）。"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path


def load_api_key() -> None:
    if os.environ.get("WANDB_API_KEY"):
        return
    key_path = Path.home() / ".wandb_api_key"
    if key_path.is_file():
        os.environ["WANDB_API_KEY"] = key_path.read_text().strip()


def parse_magic123(log_path: Path) -> list[tuple[int, float, dict]]:
    rows = []
    pat = re.compile(r"Train \[Step\] (\d+)/\d+, loss=([\d.]+)(.*)")
    loss_pat = re.compile(r"loss_(\w+)=([\d.]+)")
    for line in log_path.read_text(errors="ignore").splitlines():
        m = pat.search(line)
        if not m:
            continue
        step = int(m.group(1))
        total = float(m.group(2))
        metrics = {"train/loss": total}
        for lm in loss_pat.finditer(m.group(3)):
            metrics[f"train/loss_{lm.group(1)}"] = float(lm.group(2))
        rows.append((step, total, metrics))
    return rows


def parse_2dgs(log_path: Path) -> list[tuple[int, float, dict]]:
    rows = []
    pat = re.compile(r"Training progress:.*?(\d+)/(\d+).*?Loss=([\d.]+)")
    for line in log_path.read_text(errors="ignore").splitlines():
        m = pat.search(line)
        if not m:
            continue
        step = int(m.group(1))
        max_steps = int(m.group(2))
        loss = float(m.group(3))
        metrics = {"train/loss": loss, "config/max_steps": max_steps}
        rows.append((step, loss, metrics))
    return rows


PARSERS = {
    "magic123": parse_magic123,
    "2dgs": parse_2dgs,
}


def detect_format(log_path: Path) -> str | None:
    sample = log_path.read_text(errors="ignore")[:100_000]
    if "Training progress:" in sample and "Loss=" in sample:
        return "2dgs"
    if "Train [Step]" in sample:
        return "magic123"
    return None


@dataclass
class RunSpec:
    name: str
    log: Path | None
    fmt: str | None
    config: dict | None = None
    synthetic: bool = False


def default_runs(root: Path) -> list[RunSpec]:
    logs = root / "logs"
    return [
        RunSpec("object_a_2dgs", logs / "step01_train.log", "2dgs"),
        RunSpec("object_c_coarse", logs / "step03_object_c.log", "magic123"),
        RunSpec("object_c_fine_256", logs / "step03_fine.log", "magic123"),
        RunSpec("background_2dgs", None, None),
        RunSpec(
            "object_b_threestudio",
            logs / "export_launch.log",
            None,
            config={
                "method": "threestudio DreamFusion-SD",
                "max_steps": 10000,
                "prompt": "a cute ceramic mug with blue stripes, studio lighting, high quality 3D object",
                "mesh_export_mb": 12.2,
                "note": "export_launch.log has no step-by-step loss; config-only placeholder run",
                "source_log": str(logs / "export_launch.log"),
            },
            synthetic=True,
        ),
    ]


def replay_run(
    run_name: str,
    log: Path | None,
    fmt: str | None,
    project: str,
    entity: str | None,
    resume: str,
    config: dict | None = None,
    synthetic: bool = False,
) -> tuple[str, int, str]:
    import wandb

    init_kwargs: dict = {
        "project": project,
        "name": run_name,
        "resume": resume,
    }
    if entity:
        init_kwargs["entity"] = entity

    if synthetic:
        cfg = dict(config or {})
        cfg["replay_type"] = "config_only"
        wandb.init(**init_kwargs, config=cfg)
        wandb.finish()
        return run_name, 0, "config_only"

    if log is None or not log.is_file():
        return run_name, 0, "skipped (missing log)"

    fmt = fmt or detect_format(log)
    if fmt is None:
        return run_name, 0, "skipped (unknown format / no loss lines)"

    parser_fn = PARSERS.get(fmt)
    if parser_fn is None:
        return run_name, 0, f"skipped (unknown parser {fmt})"

    rows = parser_fn(log)
    if not rows:
        return run_name, 0, "skipped (no loss rows parsed)"

    cfg = {"source_log": str(log), "log_format": fmt}
    if config:
        cfg.update(config)
    wandb.init(**init_kwargs, config=cfg)
    for step, _, metrics in rows:
        wandb.log(metrics, step=step)
    wandb.finish()
    return run_name, len(rows), "replayed"


def main() -> None:
    parser = argparse.ArgumentParser(description="Replay local training logs to WandB")
    parser.add_argument("--log", help="Single log file path")
    parser.add_argument("--run-name", help="WandB run name (required with --log)")
    parser.add_argument(
        "--format",
        choices=["auto", "magic123", "2dgs"],
        default="auto",
        help="Log format (default: auto-detect)",
    )
    parser.add_argument("--project", default="cv-hw3")
    parser.add_argument(
        "--entity",
        default="kryskatrina-fudan-university-school-of-management",
    )
    parser.add_argument("--resume", default="allow", choices=["allow", "must", "never"])
    parser.add_argument(
        "--suffix",
        default="",
        help="Append to run names (e.g. _replay) to avoid collisions",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Replay all HW3 runs defined in this script",
    )
    parser.add_argument(
        "--logs-dir",
        default="logs",
        help="Logs directory relative to project root (--all)",
    )
    args = parser.parse_args()

    try:
        import wandb  # noqa: F401
    except ImportError:
        raise SystemExit("pip install wandb")

    load_api_key()
    root = Path(__file__).resolve().parents[2]

    if args.all:
        runs = default_runs(root)
        if args.logs_dir != "logs":
            logs = root / args.logs_dir
            runs = [
                RunSpec(
                    r.name,
                    logs / r.log.name if r.log else None,
                    r.fmt,
                    r.config,
                    r.synthetic,
                )
                for r in runs
            ]
        results = []
        for spec in runs:
            name = f"{spec.name}{args.suffix}"
            if spec.name == "background_2dgs":
                bg_log = root / args.logs_dir / "step04_background.log"
                if bg_log.is_file():
                    spec = RunSpec(name.replace(args.suffix, ""), bg_log, "2dgs")
                    name = f"{spec.name}{args.suffix}"
                else:
                    results.append((name, 0, "skipped (no background loss log)"))
                    print(f"[skip] {name}: no background loss log found")
                    continue
            run_name, n, status = replay_run(
                name,
                spec.log,
                spec.fmt,
                args.project,
                args.entity or None,
                args.resume,
                spec.config,
                spec.synthetic,
            )
            results.append((run_name, n, status))
            print(f"[{status}] {run_name}: {n} steps")
        print("\n=== Summary ===")
        for run_name, n, status in results:
            print(f"  {run_name}: {n} steps ({status})")
        return

    if not args.log or not args.run_name:
        parser.error("--log and --run-name required unless --all")

    log = Path(args.log)
    if not log.is_absolute():
        log = root / log
    fmt = None if args.format == "auto" else args.format
    run_name = f"{args.run_name}{args.suffix}"
    _, n, status = replay_run(
        run_name,
        log,
        fmt,
        args.project,
        args.entity or None,
        args.resume,
    )
    if status.startswith("skipped"):
        raise SystemExit(f"{status}: {log}")
    print(f"Replayed {n} steps to WandB run '{run_name}' ({status})")


if __name__ == "__main__":
    main()
