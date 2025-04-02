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
# 注意：以下指令在某些CUPS版本中不受支持，已注释掉
# BrowseRemoteProtocols dnssd
# BrowseWebIF Yes
# BrowseAddress @LOCAL

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

# 首先检查CUPS配置是否有效
/usr/sbin/cupsd -t
if [ $? -ne 0 ]; then
    echo "CUPS配置测试失败，尝试使用默认配置..."
    cp /etc/cups/cupsd.conf /etc/cups/cupsd.conf.backup
    cat > /etc/cups/cupsd.conf << EOF
# 最小化CUPS配置
LogLevel warn
MaxLogSize 0
Port 631
Listen /run/cups/cups.sock
ServerAlias *
DefaultEncryption Never
<Location />
  Order allow,deny
  Allow all
</Location>
<Location /admin>
  Order allow,deny
  Allow all
</Location>
<Location /printers>
  Order allow,deny
  Allow all
</Location>
EOF
fi

# 确保CUPS目录存在且权限正确
mkdir -p /var/spool/cups/tmp
mkdir -p /run/cups
mkdir -p /var/log/cups
touch /var/log/cups/access_log
touch /var/log/cups/error_log
chmod -R 755 /var/spool/cups
chmod -R 755 /etc/cups
chmod -R 755 /run/cups
chmod -R 755 /var/log/cups

# 创建CUPS客户端配置
echo "# CUPS客户端配置" > /etc/cups/client.conf
echo "ServerName localhost" >> /etc/cups/client.conf

# 启动CUPS
echo "尝试启动CUPS（后台模式）..."
/usr/sbin/cupsd
sleep 3

# 检查CUPS是否运行
if pgrep cupsd > /dev/null; then
    echo "CUPS服务成功启动"
    CUPS_RUNNING=true
else
    echo "CUPS服务启动失败，尝试直接前台运行..."
    # 先确保没有其他实例在运行
    killall -9 cupsd 2>/dev/null || true
    sleep 1
    # 尝试前台模式
    /usr/sbin/cupsd -f -c /etc/cups/cupsd.conf &
    CUPSD_PID=$!
    sleep 5
    # 再次检查
    if ps -p $CUPSD_PID > /dev/null; then
        echo "CUPS服务在前台模式下成功启动"
        CUPS_RUNNING=true
    else
        echo "CUPS服务启动失败，AirPrint将无法工作"
        CUPS_RUNNING=false
    fi
fi

# 等待CUPS完全启动
echo "等待CUPS服务完全初始化..."
sleep 5

# 修复/var/run/cups/cups.sock权限
if [ -S /var/run/cups/cups.sock ] || [ -S /run/cups/cups.sock ]; then
    echo "发现CUPS套接字，确保正确权限..."
    chmod 777 /var/run/cups/cups.sock 2>/dev/null || true
    chmod 777 /run/cups/cups.sock 2>/dev/null || true
else
    echo "警告: 未找到CUPS套接字，这可能导致客户端工具连接失败"
fi

# 启用AirPrint基本设置
echo "配置AirPrint基本设置..."
if [ "$CUPS_RUNNING" = true ]; then
    # 使用curl测试CUPS是否响应
    if curl -s --connect-timeout 3 http://localhost:631/ > /dev/null; then
        echo "CUPS已响应，应用AirPrint设置..."
        # 直接使用lpadmin命令替代cupsctl
        echo "使用替代方法配置CUPS共享设置..."
        
        # 设置共享选项
        lpadmin -o printer-is-shared=true || echo "设置默认共享选项失败"
        
        # 为所有打印机启用共享
        echo "确保所有打印机都启用了共享..."
        lpstat -v 2>/dev/null | awk -F ":" '{print $1}' | awk '{print $NF}' | while read printer; do
            echo "设置打印机 $printer 为共享..."
            lpadmin -p "$printer" -o printer-is-shared=true || echo "设置打印机 $printer 共享失败，但继续..."
        done
        
        # 尝试更可靠的方式设置CUPS选项
        echo "使用备用方法尝试配置CUPS..."
        curl -s -X POST http://localhost:631/admin/?OP=config-server -d "share_printers=1" -d "remote_admin=1" -d "remote_any=1" -d "SubmitSimple=Change+Settings" >/dev/null || echo "通过Web接口配置CUPS失败"
        
        # 尝试低级别方式直接编辑配置文件
        echo "ServerName localhost" >> /etc/cups/client.conf
    else
        echo "CUPS未响应HTTP请求，跳过AirPrint设置"
    fi
else
    echo "CUPS未运行，跳过AirPrint设置"
fi

# 验证服务状态
echo "验证服务状态..."
echo "检查CUPS状态:"
if [ "$CUPS_RUNNING" = true ]; then
    lpstat -t 2>/dev/null || echo "无法获取CUPS状态，但服务可能仍在运行"
    
    echo "尝试使用更可靠的方法检查CUPS状态:"
    if curl -s --connect-timeout 3 http://localhost:631/printers/ > /dev/null; then
        echo "CUPS Web界面可访问，服务正常运行"
    else
        echo "警告: CUPS Web界面不可访问，可能存在问题"
        # 尝试重新启动CUPS
        echo "尝试重新启动CUPS..."
        killall -9 cupsd 2>/dev/null || true
        sleep 2
        /usr/sbin/cupsd -f &
        CUPSD_PID=$!
        sleep 5
        if curl -s --connect-timeout 3 http://localhost:631/ > /dev/null; then
            echo "CUPS重启后可访问"
        else
            echo "CUPS重启后仍不可访问，可能存在底层问题"
        fi
    fi
else
    echo "CUPS未运行，无法获取状态"
fi

echo "检查Avahi状态:"
if pgrep avahi-daemon > /dev/null; then
    echo "Avahi daemon 正在运行"
    # 尝试安装avahi-browse工具
    if ! command -v avahi-browse > /dev/null; then
        echo "找不到avahi-browse命令，尝试安装..."
        apt-get update -y && apt-get install -y --no-install-recommends avahi-utils 2>/dev/null || echo "安装avahi-utils失败，但继续..."
    fi
    
    # 尝试使用avahi-browse显示已发布的服务
    if command -v avahi-browse > /dev/null; then
        echo "发布的mDNS服务:"
        AVAHI_BROWSE_OUTPUT=$(avahi-browse -a -t 2>/dev/null)
        if [ -n "$AVAHI_BROWSE_OUTPUT" ]; then
            echo "$AVAHI_BROWSE_OUTPUT"
        else
            echo "未检测到任何mDNS服务，可能需要等待打印机配置完成"
            # 强制发布一个测试服务
            if command -v avahi-publish > /dev/null; then
                echo "尝试发布测试服务..."
                avahi-publish -s "CUPS-Test-Service" _ipp._tcp 631 "printer=test" &
            fi
        fi
    else
        echo "仍然找不到avahi-browse命令，无法列出mDNS服务"
    fi
else
    echo "警告: Avahi daemon 未运行，AirPrint将不可用"
    echo "尝试重新启动Avahi服务..."
    if [ -x /usr/sbin/avahi-daemon ]; then
        /usr/sbin/avahi-daemon -k 2>/dev/null || true
        sleep 2
        /usr/sbin/avahi-daemon -D
        sleep 2
        if pgrep avahi-daemon > /dev/null; then
            echo "Avahi daemon 重启成功"
        else
            echo "Avahi daemon 重启失败"
        fi
    fi
fi

echo "================================================="
echo "基础服务已启动。请按以下步骤手动配置打印机："
echo "1. 进入容器: docker exec -it cups-airprint bash"
echo "2. 安装HPLIP插件: /opt/hp/setup-hplip-plugin.sh"
echo "3. 检查USB打印机: lsusb | grep -i hp"
echo "4. 配置打印机: hp-setup -i 或使用 /opt/scripts/setup-printer.sh"
echo "5. 或访问Web界面: http://[容器IP]:631"
echo "================================================="

# 保持容器运行
if [ "$CUPS_RUNNING" = true ] && [ -n "$CUPSD_PID" ]; then
    echo "监控CUPS进程状态..."
    wait $CUPSD_PID || echo "CUPS进程已终止，容器将继续运行"
fi

# 即使CUPS服务失败，也保持容器运行以便于调试
echo "容器将保持运行以便进行故障排除..."
tail -f /dev/null 