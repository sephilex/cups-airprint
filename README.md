# OpenWrt CUPS打印服务器 (支持HP CP1025和AirPrint)

这个项目提供了一个在OpenWrt上运行的基于Debian的Docker容器，配置了CUPS打印服务器、HP打印机驱动以及AirPrint支持。它专为惠普HP Color LaserJet CP1025打印机设计，但也可以用于其他HP打印机。

## 功能特点

- 基于Debian Bookworm的轻量级容器
- 预装CUPS打印服务器
- 支持HPLIP 3.25.2驱动和插件
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

4. 容器将仅启动CUPS和Avahi服务，其他操作需要手动完成

### 手动配置打印机

#### 步骤1: 进入容器

```bash
docker exec -it cups-airprint bash
```

#### 步骤2: 安装HPLIP插件

```bash
/opt/hp/setup-hplip-plugin.sh
```

#### 步骤3: 检测打印机

```bash
lsusb | grep -i hp
hp-probe -b usb -x
```

#### 步骤4: 设置打印机

```bash
hp-setup -i
```
按照提示完成配置。

#### 步骤5: 启用打印机共享

```bash
# 查看已配置的打印机
lpstat -v

# 启用共享（替换打印机名称）
lpadmin -p <打印机名称> -o printer-is-shared=true
```

### 通过Web界面配置

1. 访问CUPS Web界面：`http://[您的OpenWrt设备IP]:631`

2. 使用以下登录凭据（如需要）：
   - 用户名：root
   - 密码：（默认无密码）

3. 导航到"Administration" > "Add Printer"

4. 选择您的HP CP1025打印机并按提示完成配置

5. 确保在打印机设置中启用了"Share This Printer"选项

## 故障排除

### 检查服务状态

```bash
# 查看容器日志
docker logs cups-airprint

# 进入容器
docker exec -it cups-airprint bash

# 检查CUPS状态
lpstat -t

# 检查Avahi状态
service avahi-daemon status
```

### 常见问题

1. **插件安装失败**：
   ```bash
   # 手动安装插件
   cd /tmp
   wget https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/hplip-3.25.2-plugin.run
   chmod +x hplip-3.25.2-plugin.run
   sh hplip-3.25.2-plugin.run
   ```

2. **打印机未被识别**：
   ```bash
   # 清理锁文件
   rm -f /var/hp-setup.lock
   rm -f /var/hp-plugin.lock
   rm -f /var/lib/hp/hplip.lock
   
   # 重新尝试
   hp-setup -i
   ```

3. **CUPS无法启动**：
   ```bash
   # 检查错误日志
   cat /var/log/cups/error_log
   ```

## 从macOS使用打印机

1. 打开"系统设置" > "打印机与扫描仪"
2. 点击"+"添加打印机
3. 在网络打印机列表中，您应该能看到自动发现的"HP Color LaserJet cp1025"
4. 选择该打印机并点击"添加"

## 从iOS/iPadOS使用打印机

1. 在应用中选择打印选项
2. 您的打印机应该自动出现在AirPrint打印机列表中
3. 选择打印机并完成打印

## 注意事项

- 网络模式设置为"host"以支持Bonjour/mDNS服务发现
- 容器需要特权模式才能访问USB设备
- 本容器基于Debian Bookworm，使用最新的CUPS和HPLIP驱动

## 许可

本项目以MIT许可发布。 