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
├── README.md                 # 本文件：项目总览
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

## 推荐硬件

| 任务 | 最低显存 | 预计耗时 |
|------|----------|----------|
| COLMAP + 2DGS (物体 A) | 8 GB | 30–60 min |
| threestudio (物体 B) | 16 GB | 1–3 h |
| Magic123 (物体 C) | 16 GB | 30–90 min |
| 2DGS 背景 (counter) | 24 GB | 2–4 h |
| 融合渲染 | 8 GB | 10–30 min |

可在 Google Colab Pro、Kaggle GPU 或 AutoDL 上分阶段运行。
