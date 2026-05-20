FROM ros:humble-ros-base-jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble

# 中文 UTF-8 环境，避免 Python/Tkinter/终端中文乱码
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
SHELL ["/bin/bash", "-c"]

# 1. 基础工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    vim \
    xterm \
    xfce4-terminal \
    nano \
    unzip \
    lsb-release \
    gnupg2 \
    ca-certificates \
    locales \
    tzdata \
    fontconfig \
    fonts-noto-cjk \
    fonts-wqy-zenhei \
    fonts-wqy-microhei \
    python3-pip \
    python3-tk \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-vcstool \
    net-tools \
    iputils-ping \
    iproute2 \
    netcat \
    dnsutils \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone \
    && locale-gen zh_CN.UTF-8 \
    && update-locale LANG=zh_CN.UTF-8 \
    && fc-cache -fv \
    && rm -rf /var/lib/apt/lists/*

# 2. ROS2 基础依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-rclcpp \
    ros-humble-rclcpp-components \
    ros-humble-std-msgs \
    ros-humble-sensor-msgs \
    ros-humble-nav-msgs \
    ros-humble-geometry-msgs \
    ros-humble-visualization-msgs \
    ros-humble-std-srvs \
    ros-humble-tf2 \
    ros-humble-tf2-ros \
    ros-humble-tf2-eigen \
    ros-humble-tf2-geometry-msgs \
    ros-humble-tf2-sensor-msgs \
    ros-humble-ament-cmake-auto \
    ros-humble-laser-geometry \
    ros-humble-message-filters \
    ros-humble-ament-cmake \
    ros-humble-ament-index-cpp \
    ros-humble-rosbag2-cpp \
    ros-humble-rosbag2-storage \
    ros-humble-rosbag2-storage-default-plugins \
    ros-humble-rosidl-default-generators \
    ros-humble-rosidl-default-runtime \
    ros-humble-pcl-ros \
    ros-humble-pcl-conversions \
    ros-humble-pcl-msgs \
    ros-humble-sophus \
    ros-humble-rviz2 \
    ros-humble-teleop-twist-keyboard \
    ros-humble-teleop-twist-joy \
    ros-humble-key-teleop \
    ros-humble-rclpy \
    ros-humble-ament-index-python \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    mesa-utils \
    x11-apps \
    && rm -rf /var/lib/apt/lists/*

# 3. 第三方基础库
# 注意：这里不安装 libgtsam-dev，后面源码安装 GTSAM 4.1.1
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcl-dev \
    libeigen3-dev \
    libopencv-dev \
    libboost-all-dev \
    libtbb-dev \
    libyaml-cpp-dev \
    libgoogle-glog-dev \
    libgflags-dev \
    libomp-dev \
    && rm -rf /var/lib/apt/lists/*

# 4. Nav2 相关依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-navigation2 \
    ros-humble-nav2-bringup \
    ros-humble-nav2-map-server \
    ros-humble-nav2-costmap-2d \
    ros-humble-nav2-controller \
    ros-humble-nav2-planner \
    ros-humble-nav2-bt-navigator \
    ros-humble-nav2-util \
    ros-humble-nav2-lifecycle-manager \
    ros-humble-dwb-core \
    ros-humble-dwb-critics \
    ros-humble-dwb-plugins \
    && rm -rf /var/lib/apt/lists/*

# 5. 源码安装 GTSAM 4.1.1
# 重点：
# -DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF
# 避免本地构建 arm64 镜像时生成和 RK3588 不兼容的 CPU 指令
WORKDIR /opt
COPY gtsam-4.1.1.zip /opt/gtsam.zip

RUN unzip gtsam.zip && \
    cd gtsam-4.1.1 && \
    mkdir build && cd build && \
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF \
      -DGTSAM_USE_SYSTEM_EIGEN=ON \
      -DGTSAM_BUILD_TESTS=OFF \
      -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
      -DGTSAM_BUILD_UNSTABLE=OFF && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd /opt && \
    rm -rf gtsam.zip gtsam-4.1.1


# 6. 安装 Livox-SDK2
WORKDIR /opt
COPY Livox-SDK2 /opt/Livox-SDK2

RUN cd /opt/Livox-SDK2 && \
    rm -rf build && \
    mkdir build && cd build && \
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    rm -rf /opt/Livox-SDK2

# 7. 安装 TEASER++
WORKDIR /opt
COPY pmc /opt/pmc
COPY tinyply /opt/tinyply
COPY spectra /opt/spectra
COPY TEASER-plusplus /opt/TEASER-plusplus

RUN cd /opt/TEASER-plusplus && \
    rm -rf build && \
    mkdir build && cd build && \
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DENABLE_DIAGNOSTIC_PRINT=OFF && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# 8. 创建你的工作空间
WORKDIR /root/robot_rk3588_ws

# 9. 复制算法包源码到镜像
# 你的宿主机目录需要是：
# robot_rk3588_ws/
# ├── Dockerfile
# └── src/
COPY src ./src

# 10. 先单独编译 nano_gicp
RUN source /opt/ros/humble/setup.bash && \
    colcon build \
      --packages-select nano_gicp \
      --cmake-args \
      -DCMAKE_BUILD_TYPE=Release

# 11. 再单独编译 quatro，开启 TBB
RUN source /opt/ros/humble/setup.bash && \
    source /root/robot_rk3588_ws/install/setup.bash && \
    colcon build \
      --packages-select quatro \
      --cmake-args \
      -DCMAKE_BUILD_TYPE=Release \
      -DQUATRO_TBB=ON

# 12. 再编译整个工作空间
RUN source /opt/ros/humble/setup.bash && \
    source /root/robot_rk3588_ws/install/setup.bash && \
    colcon build --symlink-install \
      --parallel-workers 8 \
      --cmake-args \
      -DCMAKE_BUILD_TYPE=Release \
      -DROS_EDITION=ROS2 \
      -DHUMBLE_ROS=humble \
      -DBUILD_TESTING=OFF

# 13. 自动 source 环境
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc && \
    echo "source /root/robot_rk3588_ws/install/setup.bash" >> /root/.bashrc

WORKDIR /root/robot_rk3588_ws

CMD ["/bin/bash"]
