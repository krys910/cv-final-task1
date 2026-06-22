#!/usr/bin/env python3
"""
将带纹理 Mesh 采样为伪 2DGS 点云 (PLY)，便于与背景 2DGS 合并。

思路: 在 Mesh 表面均匀采样点，颜色来自顶点/纹理，法线作为高斯朝向。
这是作业要求的「代码级拼接」简化实现。
"""

import argparse
from pathlib import Path

import numpy as np
import trimesh
from plyfile import PlyData, PlyElement


def euler_to_matrix(rx: float, ry: float, rz: float) -> np.ndarray:
    cx, sx = np.cos(rx), np.sin(rx)
    cy, sy = np.cos(ry), np.sin(ry)
    cz, sz = np.cos(rz), np.sin(rz)
    rx_m = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry_m = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz_m = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return rz_m @ ry_m @ rx_m


def apply_transform(points: np.ndarray, scale: float, rot: np.ndarray, trans: np.ndarray) -> np.ndarray:
    return (points @ rot.T) * scale + trans


def sample_mesh_to_gaussians(mesh_path: Path, num_points: int = 50000) -> dict:
    mesh = trimesh.load(mesh_path, force="mesh", process=True)
    if not isinstance(mesh, trimesh.Trimesh):
        mesh = trimesh.util.concatenate(tuple(mesh.geometry.values()))

    points, face_idx = trimesh.sample.sample_surface(mesh, num_points)
    normals = mesh.face_normals[face_idx]

    if hasattr(mesh.visual, "uv") and mesh.visual.material is not None:
        try:
            colors = mesh.visual.to_color().vertex_colors
            if len(colors) == len(mesh.vertices):
                from trimesh.proximity import closest_point

                _, _, tri_idx = closest_point(mesh, points)
                colors = mesh.visual.to_color().face_colors[tri_idx][:, :3]
            else:
                colors = np.full((len(points), 3), 180, dtype=np.uint8)
        except Exception:
            colors = np.full((len(points), 3), 180, dtype=np.uint8)
    else:
        colors = np.full((len(points), 3), 180, dtype=np.uint8)

    return {"xyz": points.astype(np.float32), "normals": normals.astype(np.float32), "rgb": colors.astype(np.uint8)}


SH_C0 = 0.28209479177387814


def _f_dc_to_rgb(v) -> np.ndarray:
    """2DGS/3DGS DC spherical harmonics → uint8 RGB."""
    f_dc = np.stack([v["f_dc_0"], v["f_dc_1"], v["f_dc_2"]], axis=1).astype(np.float64)
    rgb = np.clip(0.5 + SH_C0 * f_dc, 0.0, 1.0)
    return (rgb * 255.0).astype(np.uint8)


def load_2dgs_ply(path: Path, *, legacy_gray: bool = False) -> dict:
    """Load 2DGS PLY. legacy_gray=True skips f_dc→RGB (old fusion used flat gray)."""
    ply = PlyData.read(str(path))
    v = ply["vertex"].data
    data = {"xyz": np.stack([v["x"], v["y"], v["z"]], axis=1).astype(np.float32)}
    for key in ("nx", "ny", "nz"):
        if key in v.dtype.names:
            data["normals"] = np.stack([v["nx"], v["ny"], v["nz"]], axis=1).astype(np.float32)
            break
    if all(c in v.dtype.names for c in ("red", "green", "blue")):
        data["rgb"] = np.stack([v["red"], v["green"], v["blue"]], axis=1).astype(np.uint8)
    elif not legacy_gray and all(c in v.dtype.names for c in ("f_dc_0", "f_dc_1", "f_dc_2")):
        data["rgb"] = _f_dc_to_rgb(v)
    return data


def merge_gaussian_dicts(parts: list[dict]) -> dict:
    xyz = np.concatenate([p["xyz"] for p in parts], axis=0)
    rgb = np.concatenate([p["rgb"] for p in parts], axis=0)
    if all("normals" in p for p in parts):
        normals = np.concatenate([p["normals"] for p in parts], axis=0)
    else:
        normals = np.zeros_like(xyz)
    return {"xyz": xyz, "normals": normals, "rgb": rgb}


def write_ply(data: dict, out_path: Path):
    n = len(data["xyz"])
    dtype = [
        ("x", "f4"), ("y", "f4"), ("z", "f4"),
        ("nx", "f4"), ("ny", "f4"), ("nz", "f4"),
        ("red", "u1"), ("green", "u1"), ("blue", "u1"),
    ]
    arr = np.empty(n, dtype=dtype)
    arr["x"], arr["y"], arr["z"] = data["xyz"].T
    arr["nx"], arr["ny"], arr["nz"] = data["normals"].T
    arr["red"], arr["green"], arr["blue"] = data["rgb"].T
    PlyData([PlyElement.describe(arr, "vertex")], text=False).write(str(out_path))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mesh", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--num_points", type=int, default=50000)
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--translation", type=float, nargs=3, default=[0, 0, 0])
    parser.add_argument("--rotation_euler", type=float, nargs=3, default=[0, 0, 0])
    args = parser.parse_args()

    data = sample_mesh_to_gaussians(Path(args.mesh), args.num_points)
    rot = euler_to_matrix(*args.rotation_euler)
    trans = np.array(args.translation, dtype=np.float32)
    data["xyz"] = apply_transform(data["xyz"], args.scale, rot, trans)
    data["normals"] = apply_transform(data["normals"], args.scale, rot, np.zeros(3))
    norms = np.linalg.norm(data["normals"], axis=1, keepdims=True) + 1e-8
    data["normals"] /= norms

    write_ply(data, Path(args.output))
    print(f"Wrote {len(data['xyz'])} pseudo-Gaussians -> {args.output}")


if __name__ == "__main__":
    main()
