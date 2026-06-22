# 异构 3D 表达统一与融合渲染方案（作业重点）

## 1. 问题陈述

本作业涉及四类资产，表达形式**不一致**：

| 资产 | 工具链 | 原始表达 | 可否直接合并 |
|------|--------|----------|--------------|
| 背景 counter | Mip-NeRF 360 + 2DGS | **显式 2D Gaussian Splatting**（PLY） | — |
| 物体 A | COLMAP + 2DGS | **2DGS PLY** | ✅ 同格式 |
| 物体 B | threestudio + SDS | **隐式 NeRF/SDF 场** → 提取 **Mesh** | ❌ |
| 物体 C | Magic123 | **NeRF coarse** → **DMTet Mesh** | ❌ |

threestudio / Magic123 的输出是 Mesh 或隐式场，背景是 2DGS 点云，**无法在同一渲染器里直接绘制**。老师要求说明：如何统一表达并完成合并渲染。

## 2. 本作业采用方案：代码级「Mesh → 伪高斯 → PLY 拼接」

对应题目提示的第二种路径：**将生成模型采样为点云，再转为 Gaussian Splats，在代码层面完成拼接**。

### 2.1 流程图

```
背景 PLY (2DGS) ──────────────────────────────┐
物体 A PLY (2DGS) ── Sim(3) 变换 ─────────────┤
物体 B Mesh ── 表面采样 50k ── 伪高斯 PLY ────┼──► merge ──► fused_scene.ply ──► 轨道渲染 ──► walkthrough.mp4
物体 C Mesh ── 表面采样 50k ── 伪高斯 PLY ────┘
```

### 2.2 伪高斯构造（`scripts/utils/mesh_to_gaussians.py`）

对 threestudio / Magic123 导出的 `mesh.obj`：

1. `trimesh.sample.sample_surface` 在三角面上均匀采样 `N=50,000` 个点；
2. **位置** `xyz`：采样点世界坐标；
3. **颜色** `rgb`：从 Mesh 纹理/顶点色烘焙（无纹理时用灰色填充）；
4. **法线** `nx,ny,nz`：对应三角面法线，作为 2DGS 面片朝向的近似；
5. 写入与 2DGS 兼容的 PLY 顶点格式：`(x,y,z,nx,ny,nz,red,green,blue)`。

> 说明：完整 2DGS 还含有 opacity、scale、rotation 等参数；融合阶段用**带法线的彩色点云**近似伪高斯，满足「统一为可拼接的显式点表达」的作业要求，渲染采用点云轨道投影（`scripts/05_fuse_and_render.py` 中的 headless numpy 渲染器）。

### 2.3 坐标对齐（`configs/scene_layout.yaml`）

各物体相对背景坐标系的 **Sim(3)** 变换：

- `translation: [x, y, z]`
- `scale: 均匀缩放`
- `rotation_euler: [rx, ry, rz]`（弧度）

物体 A 为原生 2DGS，直接 `load_2dgs_ply` 后做同样变换；B/C 在采样后再变换。

### 2.4 合并（`merge_gaussian_dicts`）

将四部分 `xyz / normals / rgb` 沿点维度 `concatenate`，写出 `outputs/fused/fused_scene.ply`。

**本次实验规模**：874,568 个点（背景 + A + B/C 各 50k 采样）。

### 2.5 漫游视频

- 120 帧圆形轨道相机；
- 分辨率 1280×720，ffmpeg 合成 `walkthrough.mp4`；
- 服务器无显示器时自动回退 numpy 点云投影渲染（不依赖 Open3D GLFW）。

## 3. 备选方案：Blender 软件级合成

若追求照片级质量，可：

1. 将 B/C 导出带贴图 OBJ/GLB；
2. 在 Blender 中导入背景点云（Point Cloud Visualizer 等插件）与 Mesh；
3. 手动对齐位姿后做路径动画渲染。

**对比**：

| 维度 | 代码级伪高斯拼接 | Blender 合成 |
|------|------------------|--------------|
| 统一表达 | 显式 PLY，满足作业技术要求 | Mesh + 点云混合，非单一表达 |
| 可复现性 | 脚本一键 `05_fuse_and_render.py` | 依赖手工摆位 |
| 视觉质量 | 点云漫游，几何正确 | 通常更好 |
| 报告价值 | 体现「异构→同构」思路 | 可作为补充效果图 |

本仓库**主结果**采用代码级方案；Blender 可作为附录对比。

## 4. 实现入口

```bash
python scripts/05_fuse_and_render.py --config configs/scene_layout.yaml
```

产出：

- `outputs/fused/fused_scene.ply`
- `outputs/fused/walkthrough.mp4`
- `outputs/fused/frames/frame_*.png`

## 5. 报告撰写建议（对应评分点）

1. **为何不能直接用 Mesh 与 2DGS 同屏渲染**：渲染方程与数据结构不同；
2. **伪高斯定义**：采样点 + 法线 + 颜色的字段含义；
3. **与 Blender 方案的取舍**；
4. 附图：`fused_frame_*.png`、融合前后点云规模表、yaml 位姿表。
