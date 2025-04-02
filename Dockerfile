FROM debian:bookworm-slim

# 避免安装过程中的交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 更新软件包并安装必要的工具
RUN apt-get update && apt-get install -y \
    cups \
    cups-client \
    cups-filters \
    cups-pdf \
    cups-bsd \
    printer-driver-all \
    hplip \
    hplip-gui \
    hplip-data \
    avahi-daemon \
    avahi-discover \
    libnss-mdns \
    dbus \
    python3-minimal \
    python3-pip \
    usbutils \
    wget \
    iproute2 \
    iputils-ping \
    curl \
    coreutils \
    procps \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 安装HPLIP的插件
RUN mkdir -p /opt/hp/
COPY setup-hplip-plugin.sh /opt/hp/
RUN chmod +x /opt/hp/setup-hplip-plugin.sh

# 创建CUPS配置目录并设置权限
RUN mkdir -p /etc/cups
RUN mkdir -p /var/run/dbus
RUN mkdir -p /run/dbus
RUN mkdir -p /run/avahi-daemon
RUN mkdir -p /var/run/avahi-daemon

# 配置CUPS允许远程访问
RUN echo "ServerAlias *" >> /etc/cups/cupsd.conf && \
    echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf

# 暴露CUPS所需端口
EXPOSE 631/tcp
EXPOSE 5353/udp

# 创建启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"] 