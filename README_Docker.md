## 本地构建完整运行 Docker 镜像，在 RK3588 上运行
## 一、正式发布
# 0）本地电脑进入工作空间根目录
cd ~/robot_rk3588_ws

# 1）确认目录结构
# robot_rk3588_ws/
# ├── Dockerfile
# ├── .dockerignore
# └── src/

# 2）拉取 arm64 ROS2 基础镜像一次
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

# RK3588 上导入并运行 Docker 镜像
## 配置 Docker 存储驱动
## 1） 查看内核是否支持 overlayfs
cat /proc/filesystems | grep overlay
输出：nodev   overlay 说明当前内核支持 overlayfs，可以优先使用 `overlay2`。不支持安装fuse-overlayfs，不建议vfs驱动太耗内存
## 2） 配置 Docker 使用 overlay2，data-root找个内存大的区域
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "data-root": "/robotfs/data/docker",
  "storage-driver": "overlay2",
  "iptables": false,
  "ip6tables": false,
  "bridge": "none",
  "ip-forward": false,
  "ip-masq": false,
  "features": {
    "containerd-snapshotter": false
  }
}
EOF
## 3） 重启 Docker 服务
sudo systemctl daemon-reload
sudo systemctl reset-failed docker
sudo systemctl restart containerd
sudo systemctl restart docker
sudo docker version 如果能看到 Server: Docker Engine，说明 Docker 服务已经启动成功

## 导入 Docker 镜像
# 1）把 slam_humble_runtime_rk3588.tar.gz 拷贝到 RK3588 后，进入所在目录
cd /robotfs/data/docker_ws

# 2）解压镜像包
sudo gunzip -f slam_humble_runtime_rk3588.tar.gz

# 3）导入 Docker 镜像 （一次）
sudo docker load -i slam_humble_runtime_rk3588.tar

# 4）确认镜像存在
sudo docker images | grep slam_humble_runtime

# 查看所有 dangling 镜像
sudo docker images -f "dangling=true"

# 清理 dangling 镜像（释放空间）
sudo docker image prune

# 5）创建数据保存目录，只需要执行一次
mkdir -p ~/docker_ws/slam_data

# 6）运行容器
--net=host 的意思是：容器直接使用宿主机 RK3588 的网络环境
sudo docker run -it --rm \
  --name slam_runtime \
  --net=host \
  --ipc=host \
  --privileged \
  -e ROS_DOMAIN_ID=0 \
  -e DISPLAY=$DISPLAY \
  -e XAUTHORITY=/tmp/.Xauthority \
  -v /dev:/dev \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v ~/.Xauthority:/tmp/.Xauthority:ro \
  -v ~/docker_ws/slam_data:/root/slam_data \
  slam_humble_runtime:rk3588
# 7）进入容器后
cd /root/robot_rk3588_ws
source /opt/ros/humble/setup.bash
source install/setup.bash
# 8）启动程序

## 二、调试阶段 不需要每次重建完整镜像
# 1）删除旧的调试容器
docker rm -f slam_debug_build
# 2）启动一个临时容器，不挂载 src
docker run -it \
  --platform linux/arm64 \
  --name slam_debug_build \
  slam_humble_runtime:rk3588

exit
# 3）把本地修改后的 src 复制进容器
docker cp ~/robot_rk3588_ws/src slam_debug_build:/root/robot_rk3588_ws/

docker start -ai slam_debug_build
# 4）容器内
cd /root/robot_rk3588_ws
source /opt/ros/humble/setup.bash
source install/setup.bash
# 5）编译
colcon build --packages-up-to pgo_sc \
  --cmake-args -DCMAKE_BUILD_TYPE=Release

source install/setup.bash
exit
# 6）宿主机 导出镜像
docker commit slam_debug_build slam_humble_runtime:rk3588-debug

docker save slam_humble_runtime:rk3588-debug -o slam_humble_runtime_rk3588_debug.tar
gzip -f slam_humble_runtime_rk3588_debug.tar
# 7）RK3588上执行
cd /robotfs/data/docker_ws
gunzip -f slam_humble_runtime_rk3588_debug.tar.gz

sudo docker load -i slam_humble_runtime_rk3588_debug.tar

sudo docker run -it --rm \
  --name slam_runtime \
  --net=host \
  --ipc=host \
  --privileged \
  -v /dev:/dev \
  -v /robotfs/data/docker_ws/slam_data:/root/slam_data \
  slam_humble_runtime:rk3588-debug

  # 进入已运行的容器，开启新的bash会话
sudo docker exec -it slam_runtime bash
