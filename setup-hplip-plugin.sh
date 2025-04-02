#!/bin/bash
set -e

PLUGIN_VERSION="3.25.2"
PLUGIN_URL="https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/hplip-${PLUGIN_VERSION}-plugin.run"
PLUGIN_PATH="/tmp/hplip-plugin.run"

echo "准备下载并安装HPLIP插件..."

# 检查HPLIP是否正常安装
echo "检查HPLIP安装状态..."
hp-doctor -i || echo "hp-doctor错误，但将继续"

# 使用timeout防止命令卡住，并添加调试输出
echo "运行hp-plugin检查插件状态..."
if timeout 30 sh -c "hp-plugin -i" > /tmp/hp-plugin-output.txt 2>&1; then
    cat /tmp/hp-plugin-output.txt
    if grep -q "Plugin is installed" /tmp/hp-plugin-output.txt; then
        echo "HPLIP插件已安装"
        exit 0
    else
        echo "HPLIP插件未安装或状态不明确，继续安装..."
    fi
else
    echo "hp-plugin命令超时或失败，继续安装..."
    cat /tmp/hp-plugin-output.txt || true
fi

# 跳过插件检查，直接安装
echo "准备直接安装HPLIP插件..."

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
rm -f "$PLUGIN_PATH" /tmp/plugin_answers.txt /tmp/hp-plugin-output.txt

echo "HPLIP插件安装完成" 