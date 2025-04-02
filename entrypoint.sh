#!/bin/bash
set -e

# 清理旧的PID文件
echo "清理旧的PID文件..."
rm -f /var/run/dbus/pid
rm -f /run/dbus/pid
rm -f /run/avahi-daemon/pid
rm -f /var/run/avahi-daemon/pid

# 创建必要的目录
mkdir -p /var/run/dbus
mkdir -p /run/dbus
mkdir -p /run/avahi-daemon
mkdir -p /var/run/avahi-daemon

# 启动dbus服务
echo "启动dbus服务..."
dbus-daemon --system || true

# 启动avahi服务（用于AirPrint发现）
echo "启动avahi服务..."
service avahi-daemon start || echo "Avahi daemon failed to start, but continuing..."

# 配置CUPS，允许远程访问
cat > /etc/cups/cupsd.conf << EOF
LogLevel warn
MaxLogSize 0
# Allow remote access
Port 631
Listen /run/cups/cups.sock
ServerAlias *
DefaultEncryption Never

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

# 等待CUPS完全启动
echo "等待CUPS服务启动..."
sleep 5

# 如果是首次运行，配置打印机
if [ ! -f /etc/cups/printers.conf ]; then
  echo "首次运行，配置HP CP1025打印机..."
  
  # 运行HPLIP插件安装脚本
  /opt/hp/setup-hplip-plugin.sh
  
  # 添加10秒延迟，确保CUPS完全启动
  sleep 10
  
  # 自动配置打印机（假设USB连接的是HP CP1025）
  echo "尝试自动配置打印机..."
  hp-setup -i --auto
  
  # 启用打印机共享
  echo "配置打印机共享..."
  lpadmin -p CP1025 -o printer-is-shared=true || echo "未能自动找到打印机，请手动配置"
  
  # 启用AirPrint
  echo "配置AirPrint..."
  /usr/sbin/cupsctl --share-printers
  /usr/sbin/cupsctl --remote-any
  /usr/sbin/cupsctl --remote-admin
fi

echo "CUPS服务已启动，请访问http://[容器IP]:631进行打印机配置"
echo "如果打印机需要手动配置，请使用 hp-setup 命令"

# 保持容器运行
tail -f /dev/null 