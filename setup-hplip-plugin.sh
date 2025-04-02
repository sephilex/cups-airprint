#!/bin/bash
set -e

PLUGIN_VERSION="3.25.2"
PLUGIN_URL="https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/hplip-${PLUGIN_VERSION}-plugin.run"
PLUGIN_PATH="/tmp/hplip-plugin.run"

echo "准备安装HPLIP插件..."

# 清除可能存在的锁文件
echo "清理可能存在的锁文件..."
rm -f /var/hp-plugin.lock
rm -f /var/lib/hp/hplip.lock
rm -f ~/.hplip/hplip.lock
rm -f /tmp/hp-plugin.lock

echo "查看HPLIP版本信息..."
hp-info -v || echo "hp-info命令失败，但将继续..."

echo "下载HPLIP插件 ${PLUGIN_VERSION}..."
if ! wget -q -O "$PLUGIN_PATH" "$PLUGIN_URL"; then
    echo "插件下载失败，尝试使用备用链接..."
    PLUGIN_URL="https://developers.hp.com/sites/default/files/hplip-${PLUGIN_VERSION}-plugin.run"
    wget -q -O "$PLUGIN_PATH" "$PLUGIN_URL" || { echo "无法下载HPLIP插件"; exit 1; }
fi

# 修改权限
chmod +x "$PLUGIN_PATH"

# 创建自动应答文件以实现非交互式安装
cat > /tmp/plugin_answers.txt << EOF
y
y
n
EOF

# 安装插件
echo "安装HPLIP插件..."
cat /tmp/plugin_answers.txt | sh "$PLUGIN_PATH" || {
    echo "HPLIP插件自动安装失败，请尝试手动安装:"
    echo "sh $PLUGIN_PATH"
    echo "插件已下载到 $PLUGIN_PATH，可以直接运行"
    exit 1
}

echo "清理临时文件和锁文件..."
rm -f /tmp/plugin_answers.txt
rm -f /var/hp-plugin.lock
rm -f /var/lib/hp/hplip.lock
rm -f ~/.hplip/hplip.lock

echo "HPLIP插件安装完成"
echo ""
echo "下一步："
echo "1. 检查打印机连接: lsusb | grep -i hp"
echo "2. 查看可用打印设备: hp-probe -b usb -x"
echo "3. 设置打印机: hp-setup -i"
echo "4. 查看已配置的打印机: lpstat -v"
echo "5. 启用打印机共享: lpadmin -p [打印机名称] -o printer-is-shared=true" 