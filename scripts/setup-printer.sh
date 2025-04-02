#!/bin/bash
# 打印机设置辅助脚本
set -e

echo "===== 打印机设置辅助工具 ====="
echo "1. 检查USB打印机连接"
echo "2. 安装HPLIP插件"
echo "3. 运行hp-setup向导"
echo "4. 启用打印机共享"
echo "5. 查看打印机状态"
echo "6. 重启Avahi和CUPS服务"
echo "7. 检查AirPrint服务发布情况"
echo "0. 退出"
echo "============================"

read -p "请选择操作 [0-7]: " choice

case $choice in
    1)
        echo "检查USB打印机连接..."
        lsusb | grep -i hp
        hp-probe -b usb -x
        ;;
    2)
        echo "安装HPLIP插件..."
        /opt/hp/setup-hplip-plugin.sh
        ;;
    3)
        echo "运行hp-setup向导..."
        # 清理锁文件
        rm -f /var/hp-setup.lock
        rm -f /var/lib/hp/hplip.lock
        rm -f ~/.hplip/hplip.lock
        # 运行设置
        hp-setup -i
        ;;
    4)
        echo "启用打印机共享..."
        # 显示当前打印机
        lpstat -v
        read -p "请输入打印机名称: " printer
        if [ -n "$printer" ]; then
            echo "设置打印机 '$printer' 为共享..."
            lpadmin -p "$printer" -o printer-is-shared=true
            echo "已启用打印机共享"
            
            # 使用更可靠的方式设置CUPS共享选项
            echo "配置CUPS全局共享设置..."
            curl -s -X POST "http://localhost:631/admin/?OP=config-server" \
                -d "share_printers=1" \
                -d "remote_admin=1" \
                -d "remote_any=1" \
                -d "user_cancel_any=1" \
                -d "preserve_job_history=1" \
                -d "preserve_job_files=1" \
                -d "SubmitSimple=Change+Settings" >/dev/null
            
            # 修改CUPS配置文件以确保AirPrint设置
            echo "确保CUPS配置支持AirPrint..."
            grep -q "BrowseProtocols" /etc/cups/cupsd.conf || echo "BrowseProtocols all" >> /etc/cups/cupsd.conf
            grep -q "BrowseLocalProtocols" /etc/cups/cupsd.conf || echo "BrowseLocalProtocols dnssd" >> /etc/cups/cupsd.conf
            grep -q "Browsing On" /etc/cups/cupsd.conf || echo "Browsing On" >> /etc/cups/cupsd.conf
            
            # 重启CUPS使配置生效
            echo "重启CUPS服务以应用配置..."
            killall -9 cupsd 2>/dev/null || true
            sleep 2
            /usr/sbin/cupsd
            
            echo "为打印机 '$printer' 手动创建AirPrint服务..."
            if command -v avahi-publish > /dev/null; then
                # 终止任何现有的avahi-publish进程
                killall avahi-publish 2>/dev/null || true
                
                # 以非阻塞方式启动新的发布进程
                nohup avahi-publish -s "${printer}" _ipp._tcp 631 "printer=${printer}" "product=(HP Color LaserJet)" "pdl=application/pdf,application/postscript" "note=AirPrint Printer" "txtvers=1" "ty=HP Color LaserJet" "priority=60" "usb_MFG=HP" >/dev/null 2>&1 &
                echo "AirPrint服务发布成功"
            else
                echo "警告: 找不到avahi-publish命令，无法手动发布服务"
            fi
            
            echo "提示: 如果iPhone仍然找不到打印机，请尝试选项6重启服务"
        else
            echo "未提供打印机名称，操作取消"
        fi
        ;;
    5)
        echo "打印机状态..."
        lpstat -v
        lpstat -t
        ;;
    6)
        echo "重启Avahi和CUPS服务..."
        # 重启Avahi
        echo "重启Avahi服务..."
        if pgrep avahi-daemon >/dev/null; then
            echo "停止现有Avahi服务..."
            killall -9 avahi-daemon 2>/dev/null || true
            sleep 2
        fi
        echo "启动Avahi服务..."
        nohup /usr/sbin/avahi-daemon -D >/dev/null 2>&1 &
        sleep 3
        
        # 重启CUPS
        echo "重启CUPS服务..."
        if pgrep cupsd >/dev/null; then
            echo "停止现有CUPS服务..."
            killall -9 cupsd 2>/dev/null || true
            sleep 2
        fi
        echo "启动CUPS服务..."
        /usr/sbin/cupsd
        sleep 3
        
        # 检查服务状态
        if pgrep avahi-daemon >/dev/null && pgrep cupsd >/dev/null; then
            echo "服务重启成功"
            
            # 手动发布所有打印机
            echo "手动发布所有打印机为AirPrint服务..."
            if command -v avahi-publish >/dev/null && lpstat -v 2>/dev/null | grep -q printer; then
                killall avahi-publish 2>/dev/null || true
                sleep 1
                lpstat -v 2>/dev/null | awk -F ":" '{print $1}' | awk '{print $NF}' | while read printer; do
                    if [ -n "$printer" ]; then
                        echo "发布打印机 '$printer'..."
                        nohup avahi-publish -s "${printer}" _ipp._tcp 631 "printer=${printer}" "product=(HP Color LaserJet)" "pdl=application/pdf,application/postscript" "note=AirPrint Printer" "txtvers=1" "ty=HP Color LaserJet" "priority=60" "usb_MFG=HP" >/dev/null 2>&1 &
                    fi
                done
                echo "所有打印机服务发布完成"
            fi
        else
            echo "服务重启失败"
        fi
        ;;
    7)
        echo "检查AirPrint服务发布情况..."
        if command -v avahi-browse >/dev/null; then
            echo "当前发布的mDNS服务:"
            avahi-browse -a -t
            
            echo "检查_ipp._tcp服务(打印机服务):"
            avahi-browse -t _ipp._tcp
        else
            echo "找不到avahi-browse工具，无法检查服务发布情况"
        fi
        ;;
    0)
        echo "退出脚本"
        exit 0
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac 