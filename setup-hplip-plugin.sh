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
    echo "检测到已安装的HPLIP版本（带包后缀）: $INSTALLED_VERSION"
    # 去除Debian包后缀(+dfsg0)
    CLEAN_VERSION=$(echo $INSTALLED_VERSION | sed 's/+dfsg[0-9]*$//')
    echo "清理后的HPLIP版本: $CLEAN_VERSION"
    PLUGIN_VERSION=$CLEAN_VERSION
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

echo "尝试使用官方安装脚本..."
# 检查是否存在官方安装脚本
if [ -f "$TEMP_DIR/plugin_install.py" ] || [ -f "$TEMP_DIR/installPlugin.py" ]; then
    echo "找到官方安装脚本，尝试执行插件安装..."
    cd "$TEMP_DIR"
    
    # 设置无头模式环境变量，强制使用非图形界面
    export QT_QPA_PLATFORM=offscreen
    export DISPLAY=""
    
    # 尝试直接安装方法
    echo "尝试直接安装方法..."
    python3 -c "
import os, glob
import shutil
import sys

# 获取系统架构
import platform
arch = platform.machine()
plugin_dir = 'x86_64'

if arch == 'x86_64':
    plugin_dir = 'x86_64'
elif arch == 'aarch64':
    plugin_dir = 'aarch64'
elif arch.startswith('arm'):
    plugin_dir = 'arm'
    if arch == 'armv7l':
        plugin_dir = 'arm32'
elif arch in ['i686', 'i386']:
    plugin_dir = 'x86_32'

print(f'系统架构: {arch}, 使用插件目录: {plugin_dir}')

# 创建目标目录
os.makedirs('/usr/share/hplip/data/firmware', exist_ok=True)
os.makedirs('/usr/share/hplip/data/plugins', exist_ok=True)
os.makedirs('/usr/share/hplip/prnt/plugins', exist_ok=True)

# 安装固件
for fw in glob.glob('*.fw.gz'):
    try:
        print(f'安装固件: {fw}')
        shutil.copy(fw, '/usr/share/hplip/data/firmware/')
    except Exception as e:
        print(f'复制固件文件失败: {e}')

# 尝试安装架构特定的插件
plugin_installed = False
for plugin in glob.glob(f'*-{plugin_dir}.so'):
    try:
        print(f'安装插件: {plugin}')
        shutil.copy(plugin, '/usr/share/hplip/prnt/plugins/')
        plugin_installed = True
    except Exception as e:
        print(f'复制插件文件失败: {e}')

# 如果没有找到架构特定的插件，尝试任何可能的匹配
if not plugin_installed:
    print('未找到架构特定插件，尝试其他架构...')
    for arch_pattern in ['arm', 'arm32', 'arm64', 'x86_32', 'x86_64']:
        for plugin in glob.glob(f'*-{arch_pattern}.so'):
            try:
                print(f'安装备选插件: {plugin}')
                shutil.copy(plugin, '/usr/share/hplip/prnt/plugins/')
                plugin_installed = True
            except Exception as e:
                print(f'复制备选插件文件失败: {e}')

# 修改权限
for dir_path in ['/usr/share/hplip/data/firmware', '/usr/share/hplip/data/plugins', '/usr/share/hplip/prnt/plugins']:
    os.system(f'chmod -R 755 {dir_path}')

if plugin_installed:
    print('HPLIP插件文件安装成功')
    sys.exit(0)
else:
    print('警告: 未能安装任何插件文件')
    sys.exit(1)
" || echo "直接安装方法失败"
    
    # 检查安装结果
    if [ $? -eq 0 ]; then
        echo "插件安装成功！"
        echo "HPLIP插件安装完成"
    else
        echo "直接安装失败，尝试原始方法..."
        
        # 尝试使用不同方法运行安装脚本
        if [ -f "$TEMP_DIR/installPlugin.py" ]; then
            echo "使用installPlugin.py安装..."
            python3 installPlugin.py -n 2>/dev/null || python installPlugin.py -n 2>/dev/null
        else
            echo "使用plugin_install.py安装..."
            python3 plugin_install.py -n 2>/dev/null || python plugin_install.py -n 2>/dev/null
        fi
        
        # 检查安装结果
        if [ $? -eq 0 ]; then
            echo "官方安装脚本执行成功！"
            echo "HPLIP插件安装完成"
        else
            echo "官方安装脚本执行失败，将尝试手动安装方式..."
            # 继续执行手动安装流程
        fi
    fi
else
    echo "未找到官方安装脚本，将使用手动安装方式..."
fi

# 检查插件是否已经安装
if [ -d "/usr/share/hplip/prnt/plugins" ] && [ "$(ls -A /usr/share/hplip/prnt/plugins/)" ]; then
    echo "检测到插件文件已存在，跳过手动安装步骤"
else
    echo "未检测到已安装的插件文件，执行手动安装..."
    
    # 直接复制插件文件到正确的位置
    echo "手动安装插件文件..."
    # 创建目标目录
    mkdir -p /usr/share/hplip/data/firmware
    mkdir -p /usr/share/hplip/data/plugins
    mkdir -p /usr/share/hplip/prnt/plugins
    
    # 根据系统架构选择正确的插件目录
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        PLUGIN_DIR=x86_64
    elif [ "$ARCH" = "aarch64" ]; then
        PLUGIN_DIR=aarch64
    elif [[ "$ARCH" == arm* ]]; then
        PLUGIN_DIR=arm
        if [ "$ARCH" = "armv7l" ]; then
            PLUGIN_DIR=arm32
        fi
    elif [ "$ARCH" = "i686" ] || [ "$ARCH" = "i386" ]; then
        PLUGIN_DIR=x86_32
    else
        echo "无法识别的架构: $ARCH，尝试使用默认插件"
        PLUGIN_DIR=x86_64
    fi
    
    echo "系统架构: $ARCH, 使用插件目录: $PLUGIN_DIR"
    
    # 首先检查传统目录结构
    if [ -d "$TEMP_DIR/plugin_install" ]; then
        echo "使用传统目录结构安装插件..."
        
        # 复制插件文件
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
    else
        # 新的目录结构 - 文件直接在提取目录中
        echo "使用新的目录结构安装插件..."
        
        # 复制固件文件
        for fw in "$TEMP_DIR"/*.fw.gz; do
            if [ -f "$fw" ]; then
                cp -v "$fw" /usr/share/hplip/data/firmware/ || echo "复制固件文件失败，但继续..."
            fi
        done
        
        # 复制架构特定的插件文件
        for plugin in "$TEMP_DIR"/*-"$PLUGIN_DIR".so; do
            if [ -f "$plugin" ]; then
                cp -v "$plugin" /usr/share/hplip/prnt/plugins/ || echo "复制插件文件失败，但继续..."
            fi
        done
        
        # 如果没有找到架构特定的插件，尝试查找任何可能的匹配
        if [ ! "$(ls -A /usr/share/hplip/prnt/plugins/)" ]; then
            echo "未找到架构特定插件，尝试复制所有可能的插件..."
            for plugin_pattern in "arm" "arm32" "arm64" "x86_32" "x86_64"; do
                for plugin in "$TEMP_DIR"/*-"$plugin_pattern".so; do
                    if [ -f "$plugin" ]; then
                        cp -v "$plugin" /usr/share/hplip/prnt/plugins/ || echo "复制备选插件文件失败，但继续..."
                    fi
                done
            done
        fi
    fi
    
    # 设置权限
    chmod -R 755 /usr/share/hplip/data/firmware
    chmod -R 755 /usr/share/hplip/data/plugins
    chmod -R 755 /usr/share/hplip/prnt/plugins
    
    # 检查是否成功
    if [ "$(ls -A /usr/share/hplip/prnt/plugins/)" ]; then
        echo "HPLIP插件文件安装完成"
    else
        echo "警告: 未能复制任何插件文件，安装可能不完整"
    fi
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