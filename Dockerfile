FROM debian:bookworm-slim

# 避免安装过程中的交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 添加中文支持
RUN apt-get update && apt-get install -y locales && \
    echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
    
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# 更新软件包并安装必要的工具 - 使用多行提高缓存利用率
# 首先安装基本工具
RUN apt-get update && apt-get install -y \
    cups \
    cups-client \
    cups-filters \
    cups-pdf \
    cups-bsd \
    dbus \
    avahi-daemon \
    avahi-discover \
    libnss-mdns \
    usbutils \
    wget \
    curl \
    coreutils \
    procps \
    vim \
    nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 然后安装HP相关工具（单独一层方便以后替换）
RUN apt-get update && apt-get install -y \
    hplip \
    hplip-gui \
    hplip-data \
    printer-driver-all \
    python3-minimal \
    python3-pip \
    iproute2 \
    iputils-ping \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 创建目录结构（分层优化）
RUN mkdir -p /etc/cups \
    /var/run/dbus \
    /run/dbus \
    /run/avahi-daemon \
    /var/run/avahi-daemon \
    /opt/hp \
    /opt/scripts

# 配置CUPS允许远程访问
RUN echo "ServerAlias *" >> /etc/cups/cupsd.conf && \
    echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf

# 暴露CUPS所需端口
EXPOSE 631/tcp
EXPOSE 5353/udp

# 创建启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 注意：setup-hplip-plugin.sh现在通过卷挂载，不再直接复制到镜像中

ENTRYPOINT ["/entrypoint.sh"] 