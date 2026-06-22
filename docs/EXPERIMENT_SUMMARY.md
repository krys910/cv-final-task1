# 实验完成记录（HW3 题目一）

**服务器**：ubuntu@36.103.199.63 · RTX 4090 24GB  
**完成日期**：2026-06-17

## 产物清单

| 模块 | 输出路径 | 大小 | 状态 |
|------|----------|------|------|
| 物体 A | `outputs/object_a/point_cloud.ply` | 33 MB | ✅ |
| 物体 B | `outputs/object_b/mesh.obj` + `texture_kd.jpg` | 12.2 MB | ✅ |
| 物体 C | `outputs/object_c/mesh.obj` | 4.3 MB | ✅ |
| 背景 counter | `outputs/background/point_cloud.ply` | 148 MB | ✅ |
| 融合场景 | `outputs/fused/fused_scene.ply` | 23 MB (874,568 pts) | ✅ |
| 漫游视频 | `outputs/fused/walkthrough.mp4` | 11 MB, 120 帧 | ✅ |

## 训练配置摘要

### 物体 A — COLMAP + 2DGS
- 图像约 41 视角
- 2DGS iterations: **10,000**
- 输出：33 MB point cloud

### 物体 B — threestudio DreamFusion-SD
- Prompt: ceramic mug（见 `02_object_b_threestudio.sh`）
- `trainer.max_steps=10000`
- 隐式场 → `export_threestudio_mesh.py` → mesh.obj

### 物体 C — Magic123
- **Coarse**：5000 steps（`step03_object_c.log`）
- **Fine DMTet-256**：5000 steps（`step03_fine.log`），最终 loss ≈ 0.0015
- 从 coarse checkpoint 初始化，workspace: `magic123-object_c-dmtet256`

### 背景 — Mip-NeRF 360 **counter** + 2DGS
- 30k iterations
- 148 MB PLY

### Step 5 融合
- B/C mesh 各采样 50k → 伪高斯
- Sim(3) 见 `configs/scene_layout.yaml`
- 渲染：headless numpy 轨道相机 + ffmpeg

## 耗时（实测/估计）

| 阶段 | 耗时 |
|------|------|
| 物体 A | ~45 min |
| 物体 B | ~1.5 h |
| 物体 C coarse+fine | ~2.5 h |
| 背景 counter | ~2–3 h |
| 融合+视频 | ~3 min |

## 日志与曲线

| 日志 | 用途 |
|------|------|
| `logs/step01_train.log` | 物体 A 2DGS loss |
| `logs/step03_object_c.log` | Magic123 coarse |
| `logs/step03_fine.log` | Magic123 fine 256 |
| `logs/step05_fuse.log` | 融合 |

生成曲线图：

```bash
python scripts/utils/plot_training_curves.py
# → report/figures/wandb_curves.png
```

WandB 回放（服务器，需 API key）：

```bash
python scripts/utils/replay_wandb_from_logs.py \
  --log logs/step03_fine.log --run-name object_c_fine_256
```

## 融合方案文档

详见 **`docs/FUSION_METHODOLOGY.md`**（作业评分重点）。

## 提交用日志包（服务器 `~/hw3/logs/`）

| Step | 主日志 | 备注 |
|------|--------|------|
| 01 | `step01_train.log` | 2DGS 10k iter 完成 |
| 02 | `export_launch.log` + `external/threestudio/.../cmd.txt` | 无独立 `step02_*.log`，以 ckpt + 导出日志佐证 |
| 03 | `step03_object_c.log`, `step03_fine.log` | coarse/fine 各 5000 step |
| 04 | `scripts/04_background_2dgs.sh` + PLY 时间戳 | 无 `step04_*.log` |
| 05 | `step05_fuse.log` | 融合 + 视频完成 |

WandB：训练时未实时同步；已回放至 [cv-hw3](https://wandb.ai/kryskatrina-fudan-university-school-of-management/cv-hw3)。本地曲线见 `report/figures/wandb_curves.png`。


1. 填写 `report/TECHNICAL_REPORT.md` 中的姓名/学号
2. 编译 `report/latex/main.tex` → PDF
3. 上传大文件到 Google Drive / 百度网盘，更新 `README.md` 链接
4. `git push` 到公开 GitHub 仓库
