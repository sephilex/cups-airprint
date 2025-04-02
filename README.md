# OpenWrt CUPS打印服务器 (支持HP CP1025和AirPrint)

这个项目提供了一个在OpenWrt上运行的基于Debian的Docker容器，配置了CUPS打印服务器、HP打印机驱动以及AirPrint支持。它专为惠普HP Color LaserJet CP1025打印机设计，但也可以用于其他HP打印机。

## 功能特点

- 基于Debian的轻量级容器
- 预装CUPS打印服务器
- 集成HPLIP驱动和插件支持
- 支持AirPrint/Bonjour，可从iOS和macOS设备直接打印
- USB设备直通支持
- 持久化配置存储

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

3. 克隆或下载此仓库到您的OpenWrt设备

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

## 配置打印机

### 通过Web界面配置

1. 访问CUPS Web界面：`http://[您的OpenWrt设备IP]:631`

2. 导航到"Administration" > "Add Printer"

3. 系统应该已经自动检测到您的HP CP1025打印机。如果没有自动检测到：
   - 选择"Local Printers" > "HP Color LaserJet cp1025 (HP Color LaserJet cp1025)"
   - 按提示完成配置

4. 确保在打印机设置中启用了"Share This Printer"选项

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

## 注意事项

- 网络模式设置为"host"以支持Bonjour/mDNS服务发现
- 容器需要特权模式才能访问USB设备
- 如果遇到权限问题，请检查USB设备权限

## 许可

本项目以MIT许可发布。 