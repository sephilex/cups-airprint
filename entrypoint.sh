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
    # 首先检查CUPS套接字是否存在并有正确权限
    echo "检查CUPS套接字..."
    for socket_path in "/var/run/cups/cups.sock" "/run/cups/cups.sock"; do
        if [ -S "$socket_path" ]; then
            echo "发现CUPS套接字: $socket_path，设置权限..."
            chmod 777 "$socket_path" || echo "无法设置$socket_path权限"
            ls -la "$socket_path"
        fi
    done
    
    # 使用curl测试CUPS是否响应
    if curl -s --connect-timeout 3 http://localhost:631/ > /dev/null; then
        echo "CUPS已响应HTTP请求，应用AirPrint设置..."
        
        # 直接修改CUPS配置文件
        echo "直接修改CUPS配置文件..."
        grep -q "BrowseProtocols" /etc/cups/cupsd.conf || echo "BrowseProtocols all" >> /etc/cups/cupsd.conf
        grep -q "BrowseLocalProtocols" /etc/cups/cupsd.conf || echo "BrowseLocalProtocols dnssd" >> /etc/cups/cupsd.conf
        grep -q "Browsing On" /etc/cups/cupsd.conf || echo "Browsing On" >> /etc/cups/cupsd.conf
        
        # 重启CUPS使配置生效
        echo "重启CUPS使新配置生效..."
        killall -9 cupsd 2>/dev/null || true
        sleep 2
        /usr/sbin/cupsd
        sleep 3
        
        # 设置共享选项（不使用cupsctl）
        echo "设置打印机共享选项..."
        
        # 为所有打印机启用共享
        echo "确保所有打印机都启用了共享..."
        if lpstat -v 2>/dev/null; then
            lpstat -v 2>/dev/null | awk -F ":" '{print $1}' | awk '{print $NF}' | while read printer; do
                echo "设置打印机 $printer 为共享..."
                lpadmin -p "$printer" -o printer-is-shared=true || echo "设置打印机 $printer 共享失败，但继续..."
            done
        else
            echo "没有发现已配置的打印机，稍后可能需要手动配置"
        fi
        
        # 尝试更可靠的方式设置CUPS选项
        echo "使用备用方法配置CUPS共享选项..."
        curl -s -X POST "http://localhost:631/admin/?OP=config-server" \
            -d "share_printers=1" \
            -d "remote_admin=1" \
            -d "remote_any=1" \
            -d "user_cancel_any=1" \
            -d "preserve_job_history=1" \
            -d "preserve_job_files=1" \
            -d "SubmitSimple=Change+Settings" >/dev/null || echo "通过Web接口配置CUPS失败"
        
        # 创建或更新客户端配置
        echo "# CUPS客户端配置" > /etc/cups/client.conf
        echo "ServerName localhost" >> /etc/cups/client.conf
        
        echo "AirPrint基本设置完成。"
    else
        echo "CUPS未响应HTTP请求，使用备用配置方法..."
        
        # 备用配置方法 - 直接编辑配置
        echo "备用方法: 直接编辑CUPS配置..."
        
        # 检查CUPS是否在运行，如果没有则重新启动
        if ! pgrep cupsd > /dev/null; then
            echo "CUPS未运行，尝试重新启动..."
            /usr/sbin/cupsd -f &
            CUPSD_PID=$!
            sleep 5
        fi
        
        # 配置环境变量，避免连接错误
        export CUPS_SERVER=localhost
        export IPP_PORT=631
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
    
    # 确保Avahi配置正确
    echo "检查Avahi配置..."
    if [ -f /etc/avahi/avahi-daemon.conf ]; then
        # 备份原始配置
        cp /etc/avahi/avahi-daemon.conf /etc/avahi/avahi-daemon.conf.bak
        
        # 修改配置以支持CUPS打印机发现
        echo "配置Avahi以支持CUPS打印机发现..."
        cat > /etc/avahi/avahi-daemon.conf << EOF
[server]
#host-name=iStoreOS
domain-name=local
use-ipv4=yes
use-ipv6=yes
enable-dbus=yes
#disallow-other-stacks=no
allow-point-to-point=yes
#publish-aaaa-on-ipv4=yes
#publish-a-on-ipv6=yes

[wide-area]
enable-wide-area=yes

[publish]
#disable-publishing=no
#disable-user-service-publishing=no
#add-service-cookie=no
publish-addresses=yes
publish-hinfo=yes
publish-workstation=yes
publish-domain=yes
#publish-dns-servers=192.168.1.1
#publish-resolv-conf-dns-servers=yes
publish-aaaa-on-ipv4=yes
publish-a-on-ipv6=yes

[reflector]
#enable-reflector=no
#reflect-ipv=no

[rlimits]
#rlimit-as=
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
EOF
        
        # 使用更可靠的方式重启Avahi
        echo "更新Avahi配置..."
        
        # 首先检查Avahi是否在运行
        if pgrep avahi-daemon >/dev/null; then
            echo "Avahi正在运行，尝试优雅停止..."
            # 尝试使用-k选项停止，但不等待返回值
            /usr/sbin/avahi-daemon -k >/dev/null 2>&1 &
            stop_pid=$!
            
            # 等待最多3秒
            timeout=3
            while pgrep avahi-daemon >/dev/null && [ $timeout -gt 0 ]; do
                sleep 1
                timeout=$((timeout-1))
            done
            
            # 如果进程仍在运行，强制终止它
            if pgrep avahi-daemon >/dev/null; then
                echo "Avahi优雅停止超时，使用强制方法..."
                killall -9 avahi-daemon 2>/dev/null || true
                sleep 1
            fi
        fi
        
        # 现在启动Avahi，使用后台方式
        echo "启动Avahi服务（使用改进的方法）..."
        # 使用nohup启动，完全分离子进程
        nohup /usr/sbin/avahi-daemon -D >/dev/null 2>&1 &
        
        # 等待它启动并检查状态
        sleep 3
        if pgrep avahi-daemon >/dev/null; then
            echo "Avahi服务成功启动"
        else
            echo "Avahi启动可能失败，尝试备用方法..."
            /usr/sbin/avahi-daemon -D --no-chroot >/dev/null 2>&1 &
            sleep 2
            if pgrep avahi-daemon >/dev/null; then
                echo "Avahi使用备用方法成功启动"
            else
                echo "警告: 无法重启Avahi服务，AirPrint可能无法工作"
            fi
        fi
        
    else
        echo "未找到Avahi配置文件，使用默认设置"
    fi
    
    # 尝试安装avahi-browse工具
    if ! command -v avahi-browse > /dev/null; then
        echo "找不到avahi-browse命令，尝试安装..."
        # 使用静默方式安装，避免不必要的错误输出
        apt-get update -qq 2>/dev/null || true
        apt-get install -y --no-install-recommends avahi-utils 2>/dev/null || echo "安装avahi-utils失败，但继续..."
    fi
    
    # 确保CUPS与Avahi集成
    echo "确保CUPS与Avahi集成..."
    
    # 检查cups-browsed服务
    if command -v cups-browsed > /dev/null; then
        echo "启动cups-browsed服务..."
        # 以非阻塞方式启动
        cups-browsed 2>/dev/null &
        # 不检查退出状态，继续执行
    else
        echo "未找到cups-browsed，尝试安装..."
        apt-get update -qq 2>/dev/null || true
        apt-get install -y --no-install-recommends cups-browsed 2>/dev/null || echo "安装cups-browsed失败，但继续..."
        
        if command -v cups-browsed > /dev/null; then
            echo "启动cups-browsed服务..."
            cups-browsed 2>/dev/null &
        fi
    fi
    
    # 尝试使用avahi-browse显示已发布的服务
    if command -v avahi-browse > /dev/null; then
        echo "发布的mDNS服务:"
        AVAHI_BROWSE_OUTPUT=$(timeout 5 avahi-browse -a -t 2>/dev/null || echo "")
        if [ -n "$AVAHI_BROWSE_OUTPUT" ]; then
            echo "$AVAHI_BROWSE_OUTPUT"
        else
            echo "未检测到任何mDNS服务，尝试手动发布打印机..."
            
            # 添加sleep以确保系统服务稳定
            sleep 2
            
            # 强制发布测试服务和当前打印机
            if command -v avahi-publish > /dev/null; then
                # 发布测试服务（后台）
                echo "发布AirPrint测试服务..."
                nohup avahi-publish -s "CUPS-Printer-Service" _ipp._tcp 631 "printer=test" "pdl=application/postscript" "note=AirPrint" >/dev/null 2>&1 &
                
                # 检查是否有配置的打印机
                if lpstat -v 2>/dev/null | grep -q printer; then
                    echo "发现打印机，发布为Bonjour服务..."
                    # 对每个打印机创建一个单独的服务发布进程
                    lpstat -v 2>/dev/null | awk -F ":" '{print $1}' | awk '{print $NF}' | while read printer; do
                        echo "为打印机 '$printer' 发布AirPrint服务..."
                        # 不使用wait避免阻塞脚本
                        nohup avahi-publish -s "${printer}" _ipp._tcp 631 "printer=${printer}" "product=(HP Color LaserJet)" "pdl=application/pdf,application/postscript" "note=AirPrint Printer" "txtvers=1" "ty=HP Color LaserJet" "priority=60" "usb_MFG=HP" >/dev/null 2>&1 &
                    done
                else
                    echo "没有找到已配置的打印机，只发布测试服务"
                fi
            else
                echo "找不到avahi-publish命令，无法手动发布服务"
            fi
        fi
    else
        echo "找不到avahi-browse命令，跳过服务检查"
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
echo ""
echo "在iPhone上使用AirPrint:"
echo "- 配置打印机后，重启容器确保AirPrint服务正确发布"
echo "- 打开照片或文档，点击分享图标，然后选择'打印'"
echo "- 如果看不到打印机，请检查iPhone是否与打印机在同一网络"
echo "- 确保防火墙允许UDP 5353和TCP 631端口"
echo "================================================="

# 即使CUPS服务失败，也保持容器运行以便于调试
echo "容器将保持运行以便进行故障排除..."

# 针对AirPrint服务检测的最终检查
echo "执行最终AirPrint服务检查..."
if pgrep avahi-daemon > /dev/null && pgrep cupsd > /dev/null; then
    echo "CUPS和Avahi服务都在运行"
    
    # 检查打印机是否已配置
    if lpstat -v 2>/dev/null | grep -q printer; then
        echo "发现已配置的打印机，确保它们发布为AirPrint服务..."
        
        # 强制重启Avahi以确保服务发现正常工作
        echo "强制重启Avahi以刷新mDNS缓存..."
        killall -9 avahi-daemon 2>/dev/null || true
        sleep 2
        nohup /usr/sbin/avahi-daemon -D >/dev/null 2>&1 &
        sleep 3
        
        # 确保CUPS配置文件正确
        echo "再次检查CUPS配置..."
        grep -q "BrowseLocalProtocols dnssd" /etc/cups/cupsd.conf || \
            echo "BrowseLocalProtocols dnssd" >> /etc/cups/cupsd.conf
        grep -q "Browsing On" /etc/cups/cupsd.conf || \
            echo "Browsing On" >> /etc/cups/cupsd.conf
        
        # 检查cups.sock权限
        for socket_path in "/var/run/cups/cups.sock" "/run/cups/cups.sock"; do
            if [ -S "$socket_path" ]; then
                echo "设置$socket_path权限为777..."
                chmod 777 "$socket_path" 2>/dev/null || true
            fi
        done
        
        # 强制为所有打印机启用共享
        echo "强制为所有打印机启用共享..."
        lpstat -v 2>/dev/null | awk -F ":" '{print $1}' | awk '{print $NF}' | while read printer; do
            if [ -n "$printer" ] && [ "$printer" != "的设备：usb" ]; then
                echo "确保打印机 '$printer' 已启用并共享..."
                cupsenable "$printer" 2>/dev/null || true
                lpadmin -p "$printer" -o printer-is-shared=true 2>/dev/null || true
                
                # 手动发布此打印机
                if command -v avahi-publish > /dev/null; then
                    echo "手动发布打印机 '$printer' 为AirPrint服务..."
                    nohup avahi-publish -s "${printer}" _ipp._tcp 631 "printer=${printer}" \
                        "product=(HP Color LaserJet)" \
                        "pdl=application/pdf,application/postscript" \
                        "note=AirPrint Printer" \
                        "txtvers=1" \
                        "ty=HP Color LaserJet" \
                        "priority=60" \
                        "usb_MFG=HP" \
                        "rp=printers/${printer}" \
                        "URF=none" \
                        "adminurl=http://$(hostname):631/printers/${printer}" \
                        >/dev/null 2>&1 &
                fi
            fi
        done
        
        echo "AirPrint配置和服务发布已完成。如果iPhone仍无法发现打印机，请使用以下命令检查:"
        echo "1. docker exec -it cups-airprint avahi-browse -at _ipp._tcp"
        echo "2. docker exec -it cups-airprint netstat -tulpn | grep '631\\|5353'"
    else
        echo "未发现已配置的打印机，请先配置打印机"
        echo "可通过Web界面或使用hp-setup命令配置打印机"
    fi
else
    echo "警告: 一个或多个关键服务未运行"
    if ! pgrep cupsd > /dev/null; then
        echo "CUPS服务未运行，请在容器内执行: /usr/sbin/cupsd"
    fi
    if ! pgrep avahi-daemon > /dev/null; then
        echo "Avahi服务未运行，请在容器内执行: /usr/sbin/avahi-daemon -D"
    fi
fi

# 保持容器运行
tail -f /dev/null 