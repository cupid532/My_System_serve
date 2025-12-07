cat > /tmp/setup.sh << 'SCRIPT_END'
#!/bin/bash
# ============================================
# 脚本 1: 挂载数据盘（独立执行）
# 使用方法: sudo bash mount_disk.sh
# ============================================

mount_data_disk() {
    echo "========================================="
    echo "  数据盘挂载工具"
    echo "========================================="
    echo ""
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then 
        echo "❌ 请使用 root 权限执行"
        exit 1
    fi
    
    # 检查 /data 是否已挂载
    if mountpoint -q /data 2>/dev/null; then
        echo "✅ /data 已挂载"
        df -h /data
        exit 0
    fi
    
    # 显示未挂载的磁盘
    echo "💾 扫描未挂载的磁盘..."
    echo ""
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk | grep -v "/$"
    echo ""
    
    # 手动输入磁盘
    read -p "请输入要挂载的磁盘名（例如 sdb 或 vdb）: " DISK_NAME
    DISK="/dev/$DISK_NAME"
    
    # 验证磁盘存在
    if [ ! -b "$DISK" ]; then
        echo "❌ 磁盘 $DISK 不存在"
        exit 1
    fi
    
    # 显示磁盘信息
    DISK_SIZE=$(lsblk -ndo SIZE "$DISK")
    echo ""
    echo "⚠️  即将格式化磁盘:"
    echo "   设备: $DISK"
    echo "   大小: $DISK_SIZE"
    echo "   挂载点: /data"
    echo ""
    echo "⚠️  警告: 此操作将清空磁盘所有数据！"
    echo ""
    
    # 二次确认
    read -p "确认格式化并挂载？(输入 YES 继续): " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo "❌ 操作已取消"
        exit 1
    fi
    
    # 开始操作
    echo ""
    echo "🔧 正在格式化 $DISK ..."
    mkfs.ext4 -F -L DATA_DISK "$DISK"
    
    echo "📁 创建挂载点 /data ..."
    mkdir -p /data
    
    echo "🔗 挂载磁盘..."
    mount "$DISK" /data
    
    echo "⚙️  配置开机自动挂载..."
    UUID=$(blkid -s UUID -o value "$DISK")
    
    # 备份 fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # 添加到 fstab（检查是否已存在）
    if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID /data ext4 defaults,nofail 0 2" >> /etc/fstab
        echo "✓ 已添加到 /etc/fstab"
    fi
    
    echo ""
    echo "========================================="
    echo "✅ 数据盘挂载完成！"
    echo "========================================="
    echo ""
    df -h /data
    echo ""
    echo "💡 下一步: 执行环境初始化脚本"
}

# ============================================
# 脚本 2: 初始化环境（独立执行）
# 使用方法: sudo bash init_env.sh
# ============================================

init_environment() {
    echo "========================================="
    echo "  Docker 环境初始化"
    echo "========================================="
    echo ""
    
    set -e
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then 
        echo "❌ 请使用 root 权限执行"
        exit 1
    fi
    
    # 检查 /data 是否存在
    if [ ! -d /data ]; then
        echo "❌ /data 目录不存在，请先执行挂载脚本"
        exit 1
    fi
    
    # 1. 安装 Docker
    echo "📦 [1/5] 检查 Docker..."
    if ! command -v docker &> /dev/null; then
        echo "正在安装 Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        
        # 配置 Docker 镜像加速
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<'DOCKEREOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "2"
  },
  "registry-mirrors": [
    "https://docker.1panel.live",
    "https://docker.m.daocloud.io"
  ]
}
DOCKEREOF
        systemctl restart docker
        echo "✓ Docker 安装完成"
    else
        echo "✓ Docker 已安装: $(docker --version)"
    fi
    
    # 2. 创建 Docker 网络
    echo ""
    echo "🌐 [2/5] 创建 Docker 网络..."
    docker network create --subnet=172.30.0.0/16 proxynet 2>/dev/null && \
        echo "✓ 网络 proxynet 已创建" || \
        echo "✓ 网络 proxynet 已存在"
    
    # 3. 创建目录结构
    echo ""
    echo "📁 [3/5] 创建目录结构..."
    mkdir -p /data/{stacks,shared/{media,downloads,configs,backups},scripts,logs}
    echo "✓ 目录结构已创建"
    
    # 4. 创建配置文件
    echo ""
    echo "📝 [4/5] 创建配置文件..."
    
    # 环境变量配置
    cat > /data/.env <<'ENVEOF'
# 全局环境变量
PUID=1000
PGID=1000
TZ=Asia/Shanghai

# 路径配置
DATA_ROOT=/data
MEDIA_DIR=/data/shared/media
DOWNLOAD_DIR=/data/shared/downloads
CONFIG_DIR=/data/shared/configs
ENVEOF
    
    # 快速导航脚本
    cat > /data/scripts/goto.sh <<'GOTOEOF'
#!/bin/bash
# 快速跳转脚本
case "$1" in
    stacks|s) cd /data/stacks && pwd ;;
    media|m) cd /data/shared/media && pwd ;;
    downloads|d) cd /data/shared/downloads && pwd ;;
    configs|c) cd /data/shared/configs && pwd ;;
    logs|l) cd /data/logs && pwd ;;
    *) 
        echo "用法: goto [stacks|media|downloads|configs|logs]"
        echo "简写: goto [s|m|d|c|l]"
        ;;
esac
GOTOEOF
    chmod +x /data/scripts/goto.sh
    
    # 清理脚本
    cat > /data/scripts/cleanup.sh <<'CLEANEOF'
#!/bin/bash
# Docker 和日志清理脚本
echo "🧹 清理 Docker 垃圾..."
docker system prune -af --volumes
echo "🧹 清理旧日志 (30天前)..."
find /data/logs -type f -name "*.log" -mtime +30 -delete 2>/dev/null
echo "✅ 清理完成"
CLEANEOF
    chmod +x /data/scripts/cleanup.sh
    
    echo "✓ 配置文件已创建"
    
    # 5. 设置权限
    echo ""
    echo "🔐 [5/5] 配置权限..."
    chown -R 1000:1000 /data
    chmod 755 /data
    find /data -type d -exec chmod 755 {} \; 2>/dev/null
    find /data -type f -exec chmod 644 {} \; 2>/dev/null
    chmod +x /data/scripts/*.sh 2>/dev/null
    echo "✓ 权限配置完成"
    
    # 添加快捷命令
    if ! grep -q "goto.sh" ~/.bashrc 2>/dev/null; then
        echo "alias goto='source /data/scripts/goto.sh'" >> ~/.bashrc
        echo "✓ 已添加快捷命令 goto (重新登录生效)"
    fi
    
    # 完成总结
    echo ""
    echo "========================================="
    echo "✅ 环境初始化完成！"
    echo "========================================="
    echo ""
    echo "📊 系统信息:"
    echo "  - Docker: $(docker --version)"
    echo "  - 数据目录: /data"
    echo "  - 可用空间: $(df -h /data | tail -1 | awk '{print $4}')"
    echo ""
    echo "📁 目录结构:"
    tree -L 2 /data 2>/dev/null || ls -lah /data
    echo ""
    echo "🚀 快速开始:"
    echo "  1. 进入工作目录: cd /data/stacks"
    echo "  2. 查看环境变量: cat /data/.env"
    echo "  3. 快速跳转: goto stacks  (或 goto s)"
    echo "  4. 清理垃圾: bash /data/scripts/cleanup.sh"
    echo ""
}

# ============================================
# 主菜单
# ============================================

show_main_menu() {
    echo ""
    echo "========================================="
    echo "  服务器初始化工具"
    echo "========================================="
    echo ""
    echo "请选择要执行的操作:"
    echo ""
    echo "  1) 挂载数据盘到 /data"
    echo "  2) 初始化 Docker 环境"
    echo "  3) 完整安装 (挂载 + 环境)"
    echo "  0) 退出"
    echo ""
    echo "========================================="
    echo ""
}

# 主程序
main() {
    if [ "$#" -eq 1 ]; then
        case "$1" in
            mount) mount_data_disk ;;
            init) init_environment ;;
            all) 
                mount_data_disk
                echo ""
                read -p "按回车继续初始化环境..."
                init_environment
                ;;
            *) 
                echo "用法: $0 [mount|init|all]"
                exit 1
                ;;
        esac
    else
        while true; do
            show_main_menu
            read -p "请选择 [0-3]: " choice
            echo ""
            
            case "$choice" in
                1) mount_data_disk ;;
                2) init_environment ;;
                3) 
                    mount_data_disk
                    echo ""
                    read -p "按回车继续初始化环境..."
                    init_environment
                    ;;
                0) 
                    echo "👋 退出脚本"
                    exit 0
                    ;;
                *) 
                    echo "❌ 无效选择"
                    ;;
            esac
            
            echo ""
            read -p "按回车返回菜单..."
        done
    fi
}

main "$@"
SCRIPT_END

chmod +x /tmp/setup.sh && sudo /tmp/setup.sh
