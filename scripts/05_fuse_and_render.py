#!/usr/bin/env python3
"""
场景融合与漫游渲染主脚本。

流程:
1. 读取 configs/scene_layout.yaml
2. 加载背景 2DGS PLY
3. 变换并合并物体 A (2DGS)
4. 将物体 B/C Mesh 转为伪高斯并合并
5. 调用 2DGS render 或 Open3D 离屏渲染生成漫游视频
"""

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "utils"))

from mesh_to_gaussians import (  # noqa: E402
    apply_transform,
    euler_to_matrix,
    load_2dgs_ply,
    merge_gaussian_dicts,
    sample_mesh_to_gaussians,
    write_ply,
)


def transform_2dgs(data: dict, scale: float, rot: np.ndarray, trans: np.ndarray) -> dict:
    out = dict(data)
    out["xyz"] = apply_transform(data["xyz"], scale, rot, trans)
    if "normals" in data:
        n = apply_transform(data["normals"], scale, rot, np.zeros(3))
        norms = np.linalg.norm(n, axis=1, keepdims=True) + 1e-8
        out["normals"] = n / norms
    return out


def verify_fusion_inputs(cfg: dict) -> None:
    """Step 5 硬性要求 A/B/C 与背景全部就绪。"""
    required = [
        ("background", cfg["background"]["path"]),
        ("object_a", cfg["objects"]["object_a"]["path"]),
        ("object_b", cfg["objects"]["object_b"]["path"]),
        ("object_c", cfg["objects"]["object_c"]["path"]),
    ]
    missing = []
    for name, rel in required:
        p = Path(rel)
        if not p.is_absolute():
            p = ROOT / p
        if not p.is_file():
            missing.append(f"{name} ({p})")
    if missing:
        msg = "Step 5 融合前置条件不满足，缺少:\n  - " + "\n  - ".join(missing)
        msg += "\n请先完成 Step 2 (object_b/mesh.obj) 与 Step 3 (object_c/mesh.obj)，不可跳过。"
        raise FileNotFoundError(msg)


def build_fused_scene_from_cfg(cfg: dict) -> Path:
    verify_fusion_inputs(cfg)
    legacy_gray = bool(cfg.get("fusion", {}).get("legacy_gray", False))
    parts = []

    bg_path = Path(cfg["background"]["path"])
    if not bg_path.is_absolute():
        bg_path = ROOT / bg_path
    print(f"Loading background: {bg_path}")
    bg = load_2dgs_ply(bg_path, legacy_gray=legacy_gray)
    if "rgb" not in bg:
        bg["rgb"] = np.full((len(bg["xyz"]), 3), 128, dtype=np.uint8)
    parts.append(bg)

    for name, obj in cfg["objects"].items():
        obj_path = Path(obj["path"])
        if not obj_path.is_absolute():
            obj_path = ROOT / obj_path
        scale = float(obj.get("scale", 1.0))
        trans = np.array(obj.get("translation", [0, 0, 0]), dtype=np.float32)
        rot = euler_to_matrix(*obj.get("rotation_euler", [0, 0, 0]))

        print(f"Processing {name} ({obj.get('format', '?')}): {obj_path}")
        if obj.get("format") == "2dgs":
            data = load_2dgs_ply(obj_path, legacy_gray=legacy_gray)
            if "rgb" not in data:
                data["rgb"] = np.full((len(data["xyz"]), 3), 200, dtype=np.uint8)
            parts.append(transform_2dgs(data, scale, rot, trans))
        elif obj.get("format") == "mesh":
            data = sample_mesh_to_gaussians(obj_path)
            parts.append(transform_2dgs(data, scale, rot, trans))
        else:
            raise ValueError(f"Unknown format for {name}")

    fused = merge_gaussian_dicts(parts)
    out_dir = Path(cfg["render"]["output_dir"])
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    fused_ply = out_dir / "fused_scene.ply"
    write_ply(fused, fused_ply)
    print(f"Fused scene: {len(fused['xyz'])} points -> {fused_ply}")
    return fused_ply


def build_fused_scene(config_path: Path) -> Path:
    with open(config_path) as f:
        cfg = yaml.safe_load(f)
    return build_fused_scene_from_cfg(cfg)


def render_walkthrough_from_cfg(cfg: dict, fused_ply: Path):
    r = cfg["render"]
    out_dir = Path(r["output_dir"])
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir
    frames_dir = out_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    # 融合产物是「伪高斯」合并 PLY，不是 2DGS 训练 checkpoint。
    try:
        print("Trying Open3D orbit renderer...")
        _open3d_orbit_render(fused_ply, frames_dir, r)
    except Exception as exc:
        print(f"Open3D unavailable ({exc}), using headless numpy renderer...")
        _numpy_orbit_render(fused_ply, frames_dir, r)

    video_path = out_dir / "walkthrough.mp4"
    _frames_to_video(frames_dir, video_path, fps=int(r.get("fps", 30)))
    print(f"Video: {video_path}")


def render_walkthrough(config_path: Path, fused_ply: Path):
    with open(config_path) as f:
        cfg = yaml.safe_load(f)
    render_walkthrough_from_cfg(cfg, fused_ply)


def _parse_bg_color(r: dict) -> np.ndarray:
    bg = r.get("bg_color", [32, 32, 36])
    return np.array(bg, dtype=np.uint8)


def _disk_offsets(radius: int) -> np.ndarray:
    """Integer (dx, dy) offsets inside a filled disk."""
    if radius <= 0:
        return np.zeros((1, 2), dtype=np.int32)
    span = np.arange(-radius, radius + 1, dtype=np.int32)
    dx, dy = np.meshgrid(span, span)
    mask = dx * dx + dy * dy <= radius * radius
    return np.stack([dx[mask], dy[mask]], axis=1)


def _numpy_orbit_render(ply_path: Path, frames_dir: Path, r: dict):
    """Headless orbit renderer (works on servers without GLFW/OSMesa)."""
    from plyfile import PlyData

    try:
        import cv2
    except ImportError:
        cv2 = None

    ply = PlyData.read(str(ply_path))
    v = ply["vertex"].data
    xyz = np.stack([v["x"], v["y"], v["z"]], axis=1).astype(np.float64)
    rgb = np.stack([v["red"], v["green"], v["blue"]], axis=1).astype(np.uint8)

    n = len(xyz)
    max_pts = int(r.get("max_points", 400_000))
    point_radius = int(r.get("point_radius", 2))
    bg_color = _parse_bg_color(r)
    if n > max_pts:
        rng = np.random.default_rng(42)
        idx = rng.choice(n, max_pts, replace=False)
        xyz, rgb = xyz[idx], rgb[idx]

    center = xyz.mean(axis=0)
    xyz = xyz - center

    num_frames = int(r.get("num_frames", 120))
    w, h = int(r["resolution"][0]), int(r["resolution"][1])
    radius = float(r.get("radius", 3.0))
    height = float(r.get("height", 0.5))
    fov = float(r.get("fov", 60))
    focal = w / (2 * np.tan(np.deg2rad(fov) / 2))
    disk_off = _disk_offsets(point_radius)

    for i in range(num_frames):
        angle = 2 * np.pi * i / num_frames
        cam = np.array([radius * np.sin(angle), height, radius * np.cos(angle)], dtype=np.float64)
        forward = -cam
        forward /= np.linalg.norm(forward) + 1e-8
        world_up = np.array([0.0, 1.0, 0.0])
        right = np.cross(forward, world_up)
        right /= np.linalg.norm(right) + 1e-8
        up = np.cross(right, forward)

        rel = xyz - cam
        x_cam = rel @ right
        y_cam = rel @ up
        z_cam = rel @ forward
        mask = z_cam > 0.05
        x_cam, y_cam, z_cam = x_cam[mask], y_cam[mask], z_cam[mask]
        colors = rgb[mask]

        u = (focal * x_cam / z_cam + w / 2).astype(np.int32)
        v_ = (h / 2 - focal * y_cam / z_cam).astype(np.int32)
        margin = point_radius + 1
        inside = (u >= -margin) & (u < w + margin) & (v_ >= -margin) & (v_ < h + margin)
        u, v_, colors, z_cam = u[inside], v_[inside], colors[inside], z_cam[inside]

        img = np.broadcast_to(bg_color, (h, w, 3)).copy()
        order = np.argsort(-z_cam)
        u, v_, colors = u[order], v_[order], colors[order]

        if cv2 is not None and point_radius > 0:
            for dx, dy in disk_off:
                uu = u + int(dx)
                vv = v_ + int(dy)
                valid = (uu >= 0) & (uu < w) & (vv >= 0) & (vv < h)
                if not np.any(valid):
                    continue
                img[vv[valid], uu[valid]] = colors[valid]
            cv2.imwrite(str(frames_dir / f"frame_{i:04d}.png"), cv2.cvtColor(img, cv2.COLOR_RGB2BGR))
        else:
            depth = np.full((h, w), np.inf, dtype=np.float64)
            for ui, vi, col, z in zip(u, v_, colors, z_cam[order]):
                if 0 <= ui < w and 0 <= vi < h and z < depth[vi, ui]:
                    depth[vi, ui] = z
                    img[vi, ui] = col
            if cv2 is not None:
                cv2.imwrite(str(frames_dir / f"frame_{i:04d}.png"), cv2.cvtColor(img, cv2.COLOR_RGB2BGR))
            else:
                from PIL import Image

                Image.fromarray(img).save(frames_dir / f"frame_{i:04d}.png")

        if (i + 1) % 20 == 0:
            print(f"  rendered frame {i + 1}/{num_frames}")


def _open3d_orbit_render(ply_path: Path, frames_dir: Path, r: dict):
    import open3d as o3d

    pcd = o3d.io.read_point_cloud(str(ply_path))
    vis = o3d.visualization.Visualizer()
    vis.create_window(width=int(r["resolution"][0]), height=int(r["resolution"][1]), visible=False)
    vis.add_geometry(pcd)

    num_frames = int(r.get("num_frames", 120))
    radius = float(r.get("radius", 3.0))
    height = float(r.get("height", 0.5))

    ctr = vis.get_view_control()
    for i in range(num_frames):
        angle = 2 * np.pi * i / num_frames
        ctr.set_lookat([0, 0, 0])
        ctr.set_front([np.sin(angle), -0.3, -np.cos(angle)])
        ctr.set_up([0, 1, 0])
        ctr.set_zoom(0.5)
        vis.poll_events()
        vis.update_renderer()
        vis.capture_screen_image(str(frames_dir / f"frame_{i:04d}.png"))
    vis.destroy_window()


def _frames_to_video(frames_dir: Path, out_video: Path, fps: int = 30):
    pattern = sorted(frames_dir.glob("frame_*.png"))
    if not pattern:
        print(f"No frames in {frames_dir}")
        return

    cmd = [
        "ffmpeg", "-y", "-framerate", str(fps),
        "-i", str(frames_dir / "frame_%04d.png"),
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        str(out_video),
    ]
    import shutil

    if shutil.which("ffmpeg"):
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return
        print("ffmpeg failed:", result.stderr)

    try:
        import cv2

        sample = cv2.imread(str(pattern[0]))
        h, w = sample.shape[:2]
        writer = cv2.VideoWriter(
            str(out_video), cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h),
        )
        for frame_path in pattern:
            writer.write(cv2.imread(str(frame_path)))
        writer.release()
        print(f"Video (OpenCV fallback): {out_video}")
    except Exception as exc:
        print(f"Video encode failed ({exc}); 请安装 ffmpeg 或手动合成帧序列")


def _apply_render_overrides(cfg: dict, args) -> None:
    r = cfg.setdefault("render", {})
    if args.max_points is not None:
        r["max_points"] = args.max_points
    if args.point_radius is not None:
        r["point_radius"] = args.point_radius
    if args.bg_color is not None:
        r["bg_color"] = args.bg_color


def main():
    parser = argparse.ArgumentParser(description="Fuse 3D assets and render walkthrough")
    parser.add_argument(
        "--config",
        default=str(ROOT / "configs" / "scene_layout.yaml"),
        help="Scene layout YAML",
    )
    parser.add_argument("--fuse-only", action="store_true", help="Only merge PLY, skip render")
    parser.add_argument("--max-points", type=int, default=None, help="Override render.max_points")
    parser.add_argument("--point-radius", type=int, default=None, help="Override render.point_radius")
    parser.add_argument(
        "--bg-color",
        type=int,
        nargs=3,
        metavar=("R", "G", "B"),
        default=None,
        help="Override render.bg_color",
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    with open(config_path) as f:
        cfg = yaml.safe_load(f)
    _apply_render_overrides(cfg, args)

    # Write overrides back to a temp approach: pass cfg through build/render
    fused_ply = build_fused_scene_from_cfg(cfg)
    if not args.fuse_only:
        render_walkthrough_from_cfg(cfg, fused_ply)


if __name__ == "__main__":
    main()
