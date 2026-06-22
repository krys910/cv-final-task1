# 云服务器部署指南（counter 场景）

## 连接

```bash
ssh ubuntu@36.103.199.63
```

## 推荐执行顺序

```bash
# 1. 系统依赖
sudo apt update
sudo apt install -y git wget unzip ffmpeg colmap

# 2. 上传本机项目（在 Mac 上执行）
rsync -avz --exclude '.venv' --exclude 'external' --exclude 'outputs' \
  "/Users/katrina/Desktop/计算机视觉/hw3/" \
  ubuntu@36.103.199.63:~/hw3/

# 3. 服务器上：环境 + 仓库
cd ~/hw3
bash scripts/setup_repos.sh
conda env create -f environment.yml   # 或 pip install 见 README

# 4. 下载 counter 场景（仅一个场景，不必下 11GB 整包）
# 若整包已有可只保留 counter/ 目录
mkdir -p data/background
cd data/background
wget -c http://storage.googleapis.com/gresearch/refraw360/360_v2.zip
unzip 360_v2.zip counter -d .   # 或 unzip 后只保留 counter/

# 5. 流水线
bash scripts/01_object_a_colmap_2dgs.sh
bash scripts/02_object_b_threestudio.sh "a light blue plastic mug with handle, matte finish, studio lighting, high quality 3D object"
bash scripts/03_object_c_magic123.sh data/object_c/photo.jpg
bash scripts/04_background_2dgs.sh counter
python scripts/05_fuse_and_render.py
```

## 安全提示

- 勿将 SSH 密码写入 Git 仓库
- 实验完成后建议修改服务器密码
