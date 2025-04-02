# OpenWrt CUPS打印服务器 (支持HP CP1025和AirPrint)

这个项目提供了一个在OpenWrt上运行的基于Debian的Docker容器，配置了CUPS打印服务器、HP打印机驱动以及AirPrint支持。它专为惠普HP Color LaserJet CP1025打印机设计，但也可以用于其他HP打印机。

## 功能特点

- 基于Debian Bookworm的轻量级容器
- 预装CUPS打印服务器
- 集成HPLIP 3.25.2驱动和最新插件支持
- 支持AirPrint/Bonjour，可从iOS和macOS设备直接打印
- USB设备直通支持
- 持久化配置存储
- 自动清理PID文件，解决容器重启问题

## 系统要求

- 运行OpenWrt的路由器
- Docker和Docker Compose支持
- 至少256MB可用RAM
- 至少100MB可用存储空间
- USB接口（用于连接打印机）

## 安装步骤

### 准备工作

1. 在OpenWrt上安装Docker和Docker Compose：

```bash
opkg update
opkg install docker dockerd docker-compose
```

2. 启动Docker服务：

```bash
/etc/init.d/dockerd enable
/etc/init.d/dockerd start
```

3. 下载此仓库到您的OpenWrt设备：

```bash
mkdir -p /root/cups-airprint
cd /root
wget -O cups-airprint.zip https://github.com/sephilex/cups-airprint/archive/refs/heads/main.zip
unzip cups-airprint.zip -d /tmp
cp -r /tmp/cups-airprint-main/* /root/cups-airprint/
rm cups-airprint.zip
rm -rf /tmp/cups-airprint-main
```

### 部署容器

1. 将打印机通过USB连接到OpenWrt设备

2. 检查打印机连接状态：

```bash
lsusb | grep -i hp
```

3. 使用Docker Compose构建并启动容器：

```bash
cd cups-airprint
docker-compose up -d
```

4. 初始启动可能需要几分钟，因为需要下载和安装HP插件
5. 使用以下命令查看容器日志：

```bash
docker logs -f cups-airprint
```

## 配置打印机

### 通过Web界面配置

1. 访问CUPS Web界面：`http://[您的OpenWrt设备IP]:631`

2. 使用以下登录凭据（如需要）：
   - 用户名：root
   - 密码：（默认无密码）

3. 导航到"Administration" > "Add Printer"

4. 系统应该已经自动检测到您的HP CP1025打印机。如果没有自动检测到：
   - 选择"Local Printers" > "HP Color LaserJet cp1025"
   - 推荐选择 **HP LaserJet cp1025, hpcups 3.21.2, requires proprietary plugin** 驱动
   - 按提示完成配置

5. 确保在打印机设置中启用了"Share This Printer"选项

### 通过命令行配置

如果需要手动配置，可以进入容器：

```bash
docker exec -it cups-airprint bash
```

然后使用HP的设置工具：

```bash
hp-setup -i
```

按照提示完成配置。

## 从macOS使用打印机

1. 打开"系统设置" > "打印机与扫描仪"
2. 点击"+"添加打印机
3. 在网络打印机列表中，您应该能看到自动发现的"HP Color LaserJet cp1025"
4. 选择该打印机并点击"添加"

## 从iOS/iPadOS使用打印机

1. 在应用中选择打印选项
2. 您的打印机应该自动出现在AirPrint打印机列表中
3. 选择打印机并完成打印

## 故障排除

### 打印机未被发现

1. 检查USB连接：
```bash
lsusb | grep -i hp
```

2. 检查Avahi服务是否正常运行：
```bash
docker exec cups-airprint service avahi-daemon status
```

3. 检查CUPS服务状态：
```bash
docker exec cups-airprint lpstat -t
```

### 打印问题

1. 检查打印队列：
```bash
docker exec cups-airprint lpq
```

2. 查看CUPS日志：
```bash
docker exec cups-airprint tail -f /var/log/cups/error_log
```

### 容器问题

1. 查看容器日志：
```bash
docker logs cups-airprint
```

2. 重启容器：
```bash
docker-compose restart
```

3. 如果容器卡在下载HPLIP插件阶段，您可以手动下载插件并复制到容器中：
```bash
# 在您的macOS上下载插件
wget https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/hplip-3.25.2-plugin.run

# 将插件复制到OpenWrt
scp hplip-3.25.2-plugin.run root@<OpenWrt设备IP>:/tmp/

# 将插件复制到容器
docker cp /tmp/hplip-3.25.2-plugin.run cups-airprint:/tmp/hplip-plugin.run

# 在容器内运行安装
docker exec -it cups-airprint bash
chmod +x /tmp/hplip-plugin.run
sh /tmp/hplip-plugin.run
```

## 注意事项

- 网络模式设置为"host"以支持Bonjour/mDNS服务发现
- 容器需要特权模式才能访问USB设备
- 如果遇到权限问题，请检查USB设备权限
- 本容器基于Debian Bookworm，使用最新的CUPS和HPLIP驱动

## 许可

本项目以MIT许可发布。 