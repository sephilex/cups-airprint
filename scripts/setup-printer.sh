#!/bin/bash
# 打印机设置辅助脚本
set -e

echo "===== 打印机设置辅助工具 ====="
echo "1. 检查USB打印机连接"
echo "2. 安装HPLIP插件"
echo "3. 运行hp-setup向导"
echo "4. 启用打印机共享"
echo "5. 查看打印机状态"
echo "0. 退出"
echo "============================"

read -p "请选择操作 [0-5]: " choice

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
        lpadmin -p "$printer" -o printer-is-shared=true
        echo "已启用打印机共享"
        # 启用AirPrint设置
        /usr/sbin/cupsctl --share-printers
        /usr/sbin/cupsctl --remote-any
        /usr/sbin/cupsctl --remote-admin
        ;;
    5)
        echo "打印机状态..."
        lpstat -v
        lpstat -t
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