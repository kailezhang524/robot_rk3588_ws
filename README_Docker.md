# 本地构建 Docker 镜像并部署到 RK3588

```text
本地电脑负责：
1. 第一次完整构建基础镜像 docker_image:rk3588
2. 后续修改 src 后，基于基础镜像创建调试容器
3. 在调试容器中编译
4. commit 成新的调试镜像
5. save + gzip 导出镜像包

RK3588 负责：
1. 接收镜像包
2. docker load 导入镜像
3. docker run 运行镜像
```

RK3588 上只负责加载和运行镜像，不区分“基础镜像”还是“调试镜像”。

只要传过去的是一个完整镜像包，RK3588 就可以直接：

```bash
sudo docker load -i xxx.tar
sudo docker run ...
```

---

# 一、本地电脑操作：第一次构建基础镜像

## 1. 进入本地工作空间根目录

```bash
cd ~/robot_rk3588_ws
```

目录结构应为：

```text
robot_rk3588_ws/
├── Dockerfile
├── .dockerignore
└── src/
```

---

## 2. 拉取 arm64 ROS2 基础镜像

只需要执行一次。

```bash
docker pull --platform linux/arm64 ros:humble-ros-base-jammy
```

---

## 3. 构建 RK3588 使用的 arm64 基础镜像

```bash
docker buildx build \
  --platform linux/arm64 \
  -t docker_image:rk3588 \
  --load \
  --pull=false \
  --progress=plain \
  .
```
## 构建 amd64基础镜像
docker buildx build \
  --platform linux/amd64 \
  -t docker_image:amd64 \
  --load \
  --pull=false \
  --progress=plain \
  .
## 4. 本地验证基础镜像

```bash
docker run -it --rm \
  --platform linux/arm64 \
  --net=host \
  --ipc=host \
  docker_image:rk3588
```

进入容器后执行：

```bash
cd /root/robot_rk3588_ws
ls
```

正常结果应该有：

```text
build  install  log  src
```

验证 ROS2 环境：

```bash
source /opt/ros/humble/setup.bash
source install/setup.bash

ros2 pkg list | grep -E "fast|lio|pgo|localization|nano|quatro|livox|pcd"
```

退出容器：

```bash
exit
```

---

## 5. 本地导出基础镜像

```bash
docker save docker_image:rk3588 -o docker_image_rk3588.tar
gzip -f docker_image_rk3588.tar
```

得到：

```text
docker_image_rk3588.tar.gz
```

---

## 6. 拷贝基础镜像到 RK3588

```bash
scp docker_image_rk3588.tar.gz 用户名@RK3588_IP:/robotfs/data/docker_ws/
```

示例：

```bash
scp docker_image_rk3588.tar.gz jw@192.168.1.100:/robotfs/data/docker_ws/
```

---

# 二、本地电脑操作：之后只修改 src 时构建调试镜像

适用场景：

```text
本地电脑修改了 ~/robot_rk3588_ws/src
RK3588 不参与编译
不想每次重新 docker buildx build 完整镜像
```

调试镜像生成关系：

```text
docker_image:rk3588
        │
        └── robot_runtime 调试容器
                │
                ├── docker cp 新 src
                ├── colcon build
                │
                └── docker commit
                        │
                        └── docker_image:rk3588-debug-v1
```

---

# 1. 删除旧容器
sudo docker rm -f robot_runtime 2>/dev/null || true

# 2. 启动容器
sudo docker run -itd \
  --net=host \
  --ipc=host \
  --platform linux/arm64 \
  --name robot_runtime \
  docker_image:rk3588 \
  bash

# 3. 删除容器内旧 src
sudo docker exec robot_runtime bash -lc "rm -rf /root/robot_rk3588_ws/src"

# 4. 拷贝宿主机新的 src 到容器
sudo docker cp ~/robot_rk3588_ws/src robot_runtime:/root/robot_rk3588_ws/

# 5. 在容器里编译
sudo docker exec -it robot_runtime bash -lc "
cd /root/robot_rk3588_ws &&
source /opt/ros/humble/setup.bash &&
colcon build --symlink-install
"

# 6. 提交容器为新镜像
sudo docker commit robot_runtime docker_image:rk3588

# 7. 保存镜像
sudo docker save docker_image:rk3588 -o docker_image_rk3588.tar

# 8. 压缩
gzip -f docker_image_rk3588.tar

得到：

```text
docker_image_rk3588.tar.gz
```

---

## 8. 拷贝调试镜像到 RK3588

示例：

```bash
scp docker_image_rk3588.tar.gz jw@192.168.1.100:/robotfs/data/docker_ws/
```


# 三、RK3588 操作：加载并运行镜像


```text
gunzip 解压
↓
docker load 导入
↓
docker run 运行
```

示例镜像包可以是：

```text
docker_image_rk3588.tar.gz
docker_image_rk3588_debug_v1.tar.gz
docker_image_rk3588_debug_v2.tar.gz
```

---

## 1. 进入镜像目录

```bash
cd /robotfs/data/docker_ws
```

---

## 2. 解压镜像包

基础镜像示例：

```bash
sudo gunzip -f docker_image_rk3588.tar.gz
```

调试镜像示例：

```bash
sudo gunzip -f docker_image_rk3588_debug_v1.tar.gz
```

---

## 3. 导入镜像

基础镜像示例：

```bash
sudo docker load -i docker_image_rk3588.tar
```

调试镜像示例：

```bash
sudo docker load -i docker_image_rk3588_debug_v1.tar
```

确认镜像存在：

```bash
sudo docker images | grep docker_image
```

可能看到：

```text
docker_image    rk3588
docker_image    rk3588-debug-v1
docker_image    rk3588-debug-v2
```

## 4. 查看并清理 dangling 镜像

```bash
sudo docker images -f "dangling=true"
```

```bash
sudo docker image prune -f
```

---

## 5. 创建数据保存目录

```bash
sudo mkdir -p /robotfs/data/docker_ws/robot_data
```

挂载关系：

```text
RK3588 宿主机：
/robotfs/data/docker_ws/robot_data

容器内：
/root/robot_data
```

---

## 6. 删除旧运行容器

删除的是旧容器，不是镜像。

```bash
sudo docker rm -f robot_runtime 2>/dev/null || true
```

---

## 7. 运行镜像容器

把最后一行的镜像名替换成你当前要运行的镜像。

运行基础镜像：

```bash
sudo docker run -it \
  --name robot_runtime \
  --net=host \
  --ipc=host \
  --privileged \
  -e ROS_DOMAIN_ID=0 \
  -e DISPLAY=$DISPLAY \
  -e XAUTHORITY=/tmp/.Xauthority \
  -v /dev:/dev \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v ~/.Xauthority:/tmp/.Xauthority:ro \
  -v /robotfs/data/docker_ws/robot_data:/root/robot_data \
  docker_image:rk3588
```

运行调试镜像：

```bash
sudo docker run -it \
  --name robot_runtime \
  --net=host \
  --ipc=host \
  --privileged \
  -e ROS_DOMAIN_ID=0 \
  -e DISPLAY=$DISPLAY \
  -e XAUTHORITY=/tmp/.Xauthority \
  -v /dev:/dev \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v ~/.Xauthority:/tmp/.Xauthority:ro \
  -v ~/docker_ws/robot_data:/root/robot_data \
  docker_image:rk3588
```

进入容器后：

```bash
cd /root/robot_rk3588_ws

source /opt/ros/humble/setup.bash
source install/setup.bash
```

---

## 8. 之后再次进入容器

如果容器已经退出：

```bash
sudo docker start -ai robot_runtime
```

如果容器正在运行，想新开一个 bash：

```bash
sudo docker exec -it robot_runtime bash
```

---

# 四、常用清理命令

## 1. 查看镜像和容器

本地电脑：

```bash
docker images
docker ps -a
```

RK3588：

```bash
sudo docker images
sudo docker ps -a
```

---

## 2. 删除指定容器

本地电脑：

```bash
docker rm -f robot_runtime
```

RK3588：

```bash
sudo docker rm -f robot_runtime
```

---

## 3. 删除指定镜像

本地电脑：

```bash
docker rmi docker_image:rk3588-debug-v1
```

RK3588：

```bash
sudo docker rmi docker_image:rk3588-debug-v1
```

---

## 4. 清理 dangling 镜像

本地电脑：

```bash
docker image prune -f
```

RK3588：

```bash
sudo docker image prune -f
```

---

# 五、关键注意事项

## 1. RK3588 运行容器建议不要加 --rm

不建议：

```bash
sudo docker run -it --rm ...
```

因为 `--rm` 会导致容器退出后自动删除。

建议：

```bash
sudo docker run -it ...
```

这样下次可以直接：

```bash
sudo docker start -ai robot_runtime
```

---

## 2. 什么时候需要重新 docker buildx build

只有以下情况需要重新执行：

```bash
docker buildx build ...
```

包括：

```text
修改了 Dockerfile
新增或修改 apt 依赖
新增系统库或第三方库
基础环境变化
要重新生成正式基础镜像 docker_image:rk3588
```

如果只是修改 `src`，走调试镜像流程即可。
## 2. 配置 Docker 使用 overlay2
1. 检查内核是否支持 overlayfs

```bash
cat /proc/filesystems | grep overlay
```

如果输出类似：

```text
nodev   overlay
```

说明当前内核支持 `overlayfs`，可以使用 Docker 的 `overlay2` 存储驱动。

2. 配置 Docker 使用 overlay2

```bash
sudo mkdir -p /etc/docker
```

```bash
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
```

3. 重启 Docker 服务

```bash
sudo systemctl daemon-reload
sudo systemctl reset-failed docker
sudo systemctl restart containerd
sudo systemctl restart docker
```

检查 Docker 是否正常：

```bash
sudo docker version
```

查看 Docker 存储驱动和数据目录：

```bash
sudo docker info | grep -E "Docker Root Dir|Storage Driver"
```

期望结果类似：

```text
Storage Driver: overlay2
Docker Root Dir: /robotfs/data/docker
```
