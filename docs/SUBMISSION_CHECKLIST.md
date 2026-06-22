# 提交清单

**截止**：2026 年 6 月 23 日 23:59

## 实验完成状态

| 步骤 | 状态 | 产物 |
|------|------|------|
| 物体 A (2DGS) | ✅ | `outputs/object_a/point_cloud.ply` 33MB |
| 物体 B (threestudio) | ✅ | `outputs/object_b/mesh.obj` 12MB |
| 物体 C (Magic123) | ✅ | `outputs/object_c/mesh.obj` 4.3MB |
| 背景 counter (2DGS) | ✅ | `outputs/background/point_cloud.ply` 148MB |
| Step 5 融合 | ✅ | `fused_scene.ply` + `walkthrough.mp4` 11MB |

## 必须提交

- [x] **PDF 报告** — `report/HW3_technical_report.pdf`（或 `bash scripts/build_report_pdf.sh` 重新编译）
- [ ] **公开 GitHub 仓库** — 含 README、scripts、configs、report
- [ ] **网盘链接** — 权重 + 视频 + 大文件 PLY（写入 README）
- [x] **融合漫游视频** — 本地 `outputs/fused/walkthrough.mp4`；服务器同路径

## 报告必须包含（已写入源稿）

- [x] 三种方法几何/纹理/耗时对比 — `report/TECHNICAL_REPORT.md` §4
- [x] **异构表达统一方案** — `docs/FUSION_METHODOLOGY.md` + 报告 §3
- [x] 训练曲线 — `report/figures/wandb_curves.png` + [WandB 项目](https://wandb.ai/kryskatrina-fudan-university-school-of-management/cv-hw3)
- [x] 超参数表 — 报告 §2 各表
- [x] 融合截图 — `report/figures/fused_frame_*.png`

## 提交前请你填写

1. `report/TECHNICAL_REPORT.md` / `report/latex/main.tex` 中的 **[姓名] [学号]**
2. README 中的 **GitHub URL** 与 **网盘 URL**
3. 将大文件上传网盘后，在报告中替换视频链接

## 网盘打包（Google Drive）

本地目录 `drive_upload/hw3_outputs/` 包含作业要求的大文件：

| 路径 | 内容 |
|------|------|
| `object_a/point_cloud.ply` | 物体 A 2DGS |
| `object_b/mesh.obj` + 贴图 | 物体 B mesh |
| `object_c/mesh.obj` | 物体 C mesh |
| `background/point_cloud.ply` | 背景 counter |
| `fused/walkthrough.mp4` | 融合漫游视频（主提交） |
| `fused/fused_scene.ply` | 融合点云 |
| `fused_legacy/` | 旧版融合备份 |
| `HW3_technical_report.pdf` | 报告 PDF |

```bash
bash scripts/prepare_drive_upload.sh   # 从 outputs 同步
bash scripts/upload_to_gdrive.sh       # rclone 上传（需 VPN）
```

目标文件夹：https://drive.google.com/drive/folders/1-WuiJqW-zgrD1lmQ0A5e7zcUjujvDSbf

## 打包命令

```bash
# 代码 + 报告图（不含 outputs 大文件）
bash scripts/package_submission.sh

# 从服务器拉取视频与日志（可选）
bash scripts/sync_submission_assets.sh
```

## 生成 PDF

```bash
cd report/latex && pdflatex main.tex && pdflatex main.tex
# 或上传 main.tex + figures 到 Overleaf
```

## 勿提交 Git 的大文件

见 `.gitignore`：`data/`、`outputs/*.ply`、`external/`、checkpoint、`.wandb_api_key`

网盘应包含：`walkthrough.mp4`、各 `point_cloud.ply` / `mesh.obj`、可选 checkpoint。
