#!/bin/bash
set -e

PLUGIN_VERSION="3.22.10"  # 改为与系统匹配的版本
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

# 检查系统中已安装的HPLIP版本
INSTALLED_VERSION=$(dpkg -l hplip | grep hplip | awk '{print $3}' | cut -d- -f1)
if [ -n "$INSTALLED_VERSION" ]; then
    echo "检测到已安装的HPLIP版本: $INSTALLED_VERSION"
    PLUGIN_VERSION=$INSTALLED_VERSION
    echo "将插件版本调整为: $PLUGIN_VERSION"
fi

echo "下载HPLIP插件 ${PLUGIN_VERSION}..."
if ! wget -q -O "$PLUGIN_PATH" "https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/hplip-${PLUGIN_VERSION}-plugin.run"; then
    echo "插件下载失败，尝试使用备用链接..."
    if ! wget -q -O "$PLUGIN_PATH" "https://developers.hp.com/sites/default/files/hplip-${PLUGIN_VERSION}-plugin.run"; then
        echo "备用链接也失败，尝试硬编码已知可用的版本..."
        PLUGIN_VERSION="3.22.10"
        wget -q -O "$PLUGIN_PATH" "https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/hplip-${PLUGIN_VERSION}-plugin.run" || { echo "无法下载HPLIP插件"; exit 1; }
    fi
fi

# 修改权限
chmod +x "$PLUGIN_PATH"

echo "提取插件文件（跳过图形安装）..."
# 创建临时目录
TEMP_DIR="/tmp/hplip-plugin-extract"
mkdir -p "$TEMP_DIR"

# 将插件文件解压到临时目录
cd "$TEMP_DIR"
sh "$PLUGIN_PATH" --noexec --target "$TEMP_DIR"

# 设置环境变量以避免图形界面
export DIALOG_UI=no
export GUI_MODE=no
export INTERACTIVE_MODE=no
export PLUGIN_INSTALL=1

# 直接复制插件文件到正确的位置
echo "手动安装插件文件..."
if [ -d "$TEMP_DIR/plugin_install" ]; then
    # 根据系统架构选择正确的插件目录
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        PLUGIN_DIR=x86_64
    elif [ "$ARCH" = "aarch64" ]; then
        PLUGIN_DIR=aarch64
    elif [[ "$ARCH" == arm* ]]; then
        PLUGIN_DIR=arm
    elif [ "$ARCH" = "i686" ] || [ "$ARCH" = "i386" ]; then
        PLUGIN_DIR=x86_32
    else
        echo "无法识别的架构: $ARCH，尝试使用默认插件"
        PLUGIN_DIR=x86_64
    fi
    
    # 创建目标目录
    mkdir -p /usr/share/hplip/data/firmware
    mkdir -p /usr/share/hplip/data/plugins
    mkdir -p /usr/share/hplip/prnt/plugins
    
    # 复制插件文件
    echo "复制插件文件到系统目录..."
    if [ -d "$TEMP_DIR/plugin_install/data/firmware" ]; then
        cp -v "$TEMP_DIR"/plugin_install/data/firmware/* /usr/share/hplip/data/firmware/ || echo "复制firmware文件失败，但继续..."
    fi
    
    if [ -d "$TEMP_DIR/plugin_install/data/plugins" ]; then
        cp -v "$TEMP_DIR"/plugin_install/data/plugins/* /usr/share/hplip/data/plugins/ || echo "复制plugins数据文件失败，但继续..."
    fi
    
    if [ -d "$TEMP_DIR/plugin_install/$PLUGIN_DIR" ]; then
        cp -v "$TEMP_DIR"/plugin_install/$PLUGIN_DIR/* /usr/share/hplip/prnt/plugins/ || echo "复制架构特定插件失败，但继续..."
    else
        echo "警告: 未找到架构 $PLUGIN_DIR 的插件文件"
        # 尝试复制所有可用架构的插件
        for dir in "$TEMP_DIR"/plugin_install/*/; do
            if [ -d "$dir" ] && [ "$(basename "$dir")" != "data" ]; then
                echo "尝试从 $(basename "$dir") 复制插件..."
                cp -v "$dir"/* /usr/share/hplip/prnt/plugins/ || echo "复制失败，但继续..."
            fi
        done
    fi
    
    # 设置权限
    chmod -R 755 /usr/share/hplip/data/firmware
    chmod -R 755 /usr/share/hplip/data/plugins
    chmod -R 755 /usr/share/hplip/prnt/plugins
    
    echo "HPLIP插件文件安装完成"
else
    echo "错误: 插件提取目录不存在，安装失败"
    exit 1
fi

# 清理
echo "清理临时文件和锁文件..."
rm -rf "$TEMP_DIR"
rm -f "$PLUGIN_PATH"
rm -f /var/hp-plugin.lock
rm -f /var/lib/hp/hplip.lock
rm -f ~/.hplip/hplip.lock

echo "====================================================="
echo "HPLIP插件安装完成（手动方式）"
echo ""
echo "下一步："
echo "1. 检查打印机连接: lsusb | grep -i hp"
echo "2. 查看可用打印设备: hp-probe -b usb -x"
echo "3. 设置打印机: hp-setup -i"
echo "4. 查看已配置的打印机: lpstat -v"
echo "5. 启用打印机共享: lpadmin -p [打印机名称] -o printer-is-shared=true"
echo "=====================================================" 