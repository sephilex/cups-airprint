#!/bin/bash
set -e

PLUGIN_VERSION="3.25.2"
PLUGIN_URL="https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/hplip-${PLUGIN_VERSION}-plugin.run"
PLUGIN_PATH="/tmp/hplip-plugin.run"

echo "准备下载并安装HPLIP插件..."

# 检查插件是否已安装
if hp-plugin -i 2>&1 | grep -q "Plugin is installed"; then
    echo "HPLIP插件已安装"
    exit 0
fi

# 下载插件
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
cat /tmp/plugin_answers.txt | sh "$PLUGIN_PATH" || { echo "HPLIP插件安装失败，但将继续..."; }

echo "清理临时文件..."
rm -f "$PLUGIN_PATH" /tmp/plugin_answers.txt

echo "HPLIP插件安装完成" 