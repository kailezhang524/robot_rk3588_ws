## 本地构建完整运行 Docker 镜像，在 RK3588 上运行

# 0）本地电脑进入工作空间根目录
cd ~/robot_rk3588_ws

# 1）确认目录结构
# robot_rk3588_ws/
# ├── Dockerfile
# ├── .dockerignore
# └── src/

# 2）拉取 arm64 ROS2 基础镜像
docker pull --platform linux/arm64 ros:humble-ros-base-jammy

# 3）构建 arm64 完整运行镜像
# --platform linux/arm64：构建给 RK3588/aarch64 用
# --pull=false：优先使用本地已有基础镜像
# --progress=plain：显示完整构建日志，方便排错
docker buildx build \
  --platform linux/arm64 \
  -t slam_humble_runtime:rk3588 \
  --load \
  --pull=false \
  --progress=plain \
  .

# 4）本地验证镜像
docker run -it --rm \
  --platform linux/arm64 \
  slam_humble_runtime:rk3588

# 进入容器后执行：
cd /root/robot_rk3588_ws
ls
# 正常结果应该有：
# build  install  log  src

source /opt/ros/humble/setup.bash
source install/setup.bash
ros2 pkg list | grep -E "fast|lio|pgo|localization|nano|quatro|livox|pcd"

# 验证结束后退出容器
exit

# 5）导出镜像给 RK3588
docker save slam_humble_runtime:rk3588 -o slam_humble_runtime_rk3588.tar
gzip -f slam_humble_runtime_rk3588.tar

# 得到：
# slam_humble_runtime_rk3588.tar.gz
##################RK3588 上导入并运行
# 1）把 slam_humble_runtime_rk3588.tar.gz 拷贝到 RK3588 后，进入所在目录
cd ~

# 2）解压镜像包
gunzip -f slam_humble_runtime_rk3588.tar.gz

# 3）导入 Docker 镜像 （一次）
docker load -i slam_humble_runtime_rk3588.tar

# 4）确认镜像存在
docker images | grep slam_humble_runtime

# 5）创建数据保存目录，只需要执行一次
mkdir -p ~/slam_data

# 6）运行容器
docker run -it --rm \
  --name slam_runtime \
  --net=host \
  --ipc=host \
  --privileged \
  -v /dev:/dev \
  -v ~/slam_data:/root/slam_data \
  slam_humble_runtime:rk3588
# 7）进入容器后
cd /root/robot_rk3588_ws
source /opt/ros/humble/setup.bash
source install/setup.bash
# 8）启动程序
