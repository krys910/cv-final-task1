# HW3 题目一：基于 2DGS 与 AIGC 的多源资产生成与真实场景融合

## 作业目标

完成一条完整的 3D 视觉链路：

1. 用三种不同技术路径生成三个独立 3D 物体（A/B/C）
2. 用 2DGS 重建 Mip-NeRF 360 背景场景
3. 将三个物体融合进背景并输出多视角漫游视频
4. 撰写质量对比与技术报告

## 项目结构

```
hw3/
├── README.md                 # 本文件：总流程与提交说明
├── docs/
│   └── TASK_BREAKDOWN.md     # 任务拆解、时间规划、踩坑指南
├── configs/
│   └── scene_layout.yaml     # 三物体在背景中的位姿与尺度
├── scripts/
│   ├── 01_object_a_colmap_2dgs.sh
│   ├── 02_object_b_threestudio.sh
│   ├── 03_object_c_magic123.sh
│   ├── 04_background_2dgs.sh
│   ├── 05_fuse_and_render.py
│   └── utils/
│       ├── remove_bg.py
│       └── mesh_to_gaussians.py
├── report/
│   └── TECHNICAL_REPORT.md   # 可直接转 LaTeX 的技术报告
├── data/                     # 本地数据（不提交大文件）
│   ├── object_a/images/
│   ├── object_c/input.png
│   └── background/           # Mip-NeRF 360 场景
└── outputs/                  # 各阶段输出
    ├── object_a/
    ├── object_b/
    ├── object_c/
    ├── background/
    └── fused/
```

## 快速开始

### 1. 环境准备

```bash
# 建议使用 AutoDL / 本地 GPU 服务器
conda create -n hw3-2dgs python=3.10 -y
conda activate hw3-2dgs

# 克隆依赖仓库（首次运行）
bash scripts/setup_repos.sh
```

详见 `environment.yml`。

### 2. 按顺序执行

| 步骤 | 脚本 | 输入 | 输出 |
|------|------|------|------|
| 物体 A | `bash scripts/01_object_a_colmap_2dgs.sh` | 手机环绕拍摄 50–100 张图 | `outputs/object_a/point_cloud.ply` |
| 物体 B | `bash scripts/02_object_b_threestudio.sh` | 文本 prompt | `outputs/object_b/mesh.obj` |
| 物体 C | `bash scripts/03_object_c_magic123.sh` | 单张抠图 | `outputs/object_c/mesh.obj` |
| 背景 | `bash scripts/04_background_2dgs.sh counter` | Mip-NeRF 360 **counter** | `outputs/background/point_cloud.ply` |
| 融合 | `python scripts/05_fuse_and_render.py` | 上述全部输出 | `outputs/fused/walkthrough.mp4` |

**融合方案（作业重点）**：Mesh（B/C）→ 表面采样伪高斯 → 与 2DGS PLY 代码级拼接。详见 [`docs/FUSION_METHODOLOGY.md`](docs/FUSION_METHODOLOGY.md)。

### 3. 提交物

| 项目 | 状态 | 说明 |
|------|------|------|
| PDF 报告 | ✅ 已生成 | `report/HW3_technical_report.pdf` |
| GitHub | 见下方命令 | 代码 + 脚本 + 报告（不含大 PLY/mp4） |
| 网盘 | 见下方命令 | PLY + 视频 + PDF |
| 融合视频 | ✅ | `outputs/fused/walkthrough.mp4` |

**一键准备网盘目录**（同步 outputs → `drive_upload/hw3_outputs/`）：

```bash
bash scripts/prepare_drive_upload.sh
bash scripts/upload_to_gdrive.sh   # 需 VPN + rclone 授权
```

**推送到 GitHub**：

```bash
brew install gh && gh auth login    # 首次
bash scripts/push_to_github.sh
```

- GitHub: `https://github.com/krys910/cv-final-task1`
- 网盘: `https://drive.google.com/drive/folders/1-WuiJqW-zgrD1lmQ0A5e7zcUjujvDSbf`

清单：[`docs/SUBMISSION_CHECKLIST.md`](docs/SUBMISSION_CHECKLIST.md) · 实验记录：[`docs/EXPERIMENT_SUMMARY.md`](docs/EXPERIMENT_SUMMARY.md)

```bash
python scripts/utils/plot_training_curves.py   # 训练曲线图
bash scripts/package_submission.sh             # 打包代码
```

**截止时间**：2026 年 6 月 23 日 23:59

## 推荐硬件

| 任务 | 最低显存 | 预计耗时 |
|------|----------|----------|
| COLMAP + 2DGS (物体 A) | 8 GB | 30–60 min |
| threestudio (物体 B) | 16 GB | 1–3 h |
| Magic123 (物体 C) | 16 GB | 30–90 min |
| 2DGS 背景 (counter) | 24 GB | 2–4 h |
| 融合渲染 | 8 GB | 10–30 min |

可在 Google Colab Pro、Kaggle GPU 或 AutoDL 上分阶段运行。
