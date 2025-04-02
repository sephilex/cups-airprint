#!/bin/bash
set -e

# 清理旧的PID文件
echo "清理旧的PID文件..."
rm -f /var/run/dbus/pid
rm -f /run/dbus/pid
rm -f /run/avahi-daemon/pid
rm -f /var/run/avahi-daemon/pid
rm -f /var/hp-setup.lock
rm -f /var/hp-plugin.lock
rm -f /var/lib/hp/hplip.lock
rm -f ~/.hplip/hplip.lock

# 创建必要的目录
mkdir -p /var/run/dbus
mkdir -p /run/dbus
mkdir -p /run/avahi-daemon
mkdir -p /var/run/avahi-daemon

# 显示系统信息
echo "系统环境信息..."
uname -a
cat /etc/os-release

# 启动dbus服务
echo "启动dbus服务..."
dbus-daemon --system || true

# 启动avahi服务（用于AirPrint发现）
echo "启动avahi服务..."
if [ -x /usr/sbin/avahi-daemon ]; then
    echo "直接启动avahi-daemon..."
    /usr/sbin/avahi-daemon -D || echo "Avahi daemon failed to start with -D flag, trying alternate method..."
    
    # 检查是否启动成功
    if ! pgrep avahi-daemon > /dev/null; then
        echo "尝试使用第二种方法启动avahi-daemon..."
        /usr/sbin/avahi-daemon --daemonize || echo "Avahi daemon also failed with --daemonize flag"
        
        # 再次检查
        if ! pgrep avahi-daemon > /dev/null; then
            echo "尝试使用第三种方法启动avahi-daemon..."
            /usr/sbin/avahi-daemon -D --no-chroot || echo "All avahi-daemon start methods failed"
        fi
    fi
    
    # 最终检查
    if pgrep avahi-daemon > /dev/null; then
        echo "Avahi daemon successfully started"
    else
        echo "WARNING: Avahi daemon failed to start, AirPrint may not work properly"
    fi
else
    echo "Avahi daemon executable not found at /usr/sbin/avahi-daemon"
    # 尝试寻找avahi-daemon可执行文件
    AVAHI_PATH=$(find / -name avahi-daemon -type f -executable 2>/dev/null | head -1)
    if [ -n "$AVAHI_PATH" ]; then
        echo "Found avahi-daemon at $AVAHI_PATH, attempting to start..."
        $AVAHI_PATH -D || echo "Failed to start avahi-daemon from $AVAHI_PATH"
    else
        echo "Could not find avahi-daemon executable anywhere, AirPrint will not work"
    fi
fi

# 配置CUPS，允许远程访问
cat > /etc/cups/cupsd.conf << EOF
LogLevel warn
MaxLogSize 0
# Allow remote access
Port 631
Listen /run/cups/cups.sock
ServerAlias *
DefaultEncryption Never

# 启用Bonjour/AirPrint服务发现
BrowseLocalProtocols dnssd
BrowseRemoteProtocols dnssd
BrowseWebIF Yes
BrowseAddress @LOCAL

# 设置网络访问权限
<Location />
  Order allow,deny
  Allow all
</Location>
<Location /admin>
  Order allow,deny
  Allow all
</Location>
<Location /admin/conf>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow all
</Location>
<Location /printers>
  Order allow,deny
  Allow all
</Location>
<Policy default>
  JobPrivateAccess default
  JobPrivateValues default
  SubscriptionPrivateAccess default
  SubscriptionPrivateValues default
  <Limit Create-Job Print-Job Print-URI Validate-Job>
    Order allow,deny
    Allow all
  </Limit>
  <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Current-Job Suspend-Current-Job Resume-Job Cancel-My-Jobs Close-Job CUPS-Move-Job CUPS-Get-Document>
    Order allow,deny
    Allow all
  </Limit>
  <Limit CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Get-Devices>
    AuthType Default
    Require user @SYSTEM
    Order allow,deny
    Allow all
  </Limit>
  <Limit Pause-Printer Resume-Printer Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs Deactivate-Printer Activate-Printer Restart-Printer Shutdown-Printer Startup-Printer Promote-Job Schedule-Job-After Cancel-Jobs CUPS-Accept-Jobs CUPS-Reject-Jobs>
    AuthType Default
    Require user @SYSTEM
    Order allow,deny
    Allow all
  </Limit>
  <Limit CUPS-Authenticate-Job>
    Order allow,deny
    Allow all
  </Limit>
  <Limit All>
    Order allow,deny
    Allow all
  </Limit>
</Policy>
EOF

# 启动CUPS服务
echo "启动CUPS服务..."
/usr/sbin/cupsd -f &
CUPSD_PID=$!

# 等待CUPS完全启动
echo "等待CUPS服务启动..."
sleep 5

# 启用AirPrint基本设置
echo "配置AirPrint基本设置..."
/usr/sbin/cupsctl --share-printers
/usr/sbin/cupsctl --remote-any
/usr/sbin/cupsctl --remote-admin

# 确保所有打印机都启用了共享
echo "确保所有打印机都启用了共享..."
lpstat -v 2>/dev/null | awk -F ":" '{print $1}' | awk '{print $NF}' | while read printer; do
    echo "设置打印机 $printer 为共享..."
    lpadmin -p "$printer" -o printer-is-shared=true || echo "设置打印机 $printer 共享失败，但继续..."
done

# 验证服务状态
echo "验证服务状态..."
echo "检查CUPS状态:"
lpstat -t || echo "无法获取CUPS状态"

echo "检查Avahi状态:"
if pgrep avahi-daemon > /dev/null; then
    echo "Avahi daemon 正在运行"
    # 尝试使用avahi-browse显示已发布的服务
    if command -v avahi-browse > /dev/null; then
        echo "发布的mDNS服务:"
        avahi-browse -a -t || echo "无法列出mDNS服务"
    else
        echo "找不到avahi-browse命令，无法列出mDNS服务"
    fi
else
    echo "警告: Avahi daemon 未运行，AirPrint将不可用"
fi

echo "================================================="
echo "基础服务已启动。请按以下步骤手动配置打印机："
echo "1. 进入容器: docker exec -it cups-airprint bash"
echo "2. 安装HPLIP插件: /opt/hp/setup-hplip-plugin.sh"
echo "3. 检查USB打印机: lsusb | grep -i hp"
echo "4. 配置打印机: hp-setup -i"
echo "5. 或访问Web界面: http://[容器IP]:631"
echo "================================================="

# 保持容器运行
wait $CUPSD_PID || tail -f /dev/null 