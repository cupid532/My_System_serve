# 🏛️ 终极服务器架构：数据即基础设施

**核心理念**：操作系统是"耗材"，只有 `/data` 是"资产"  
**设计目标**：原子级迁移、权限零焦虑、全自动化维护  
**部署环境**：本教程，搭建环境为debin12 只建议用debin系统完成以下步骤
---

## 📋 目录

- [1. 初始化 (One-Key Setup)](#1-初始化-one-key-setup)
- [2. 核心服务部署](#2-核心服务部署)
- [3. 自动备份策略](#3-自动备份策略)
- [4. 标准部署模板](#4-标准部署模板)
- [5. 服务器迁移指南](#5-服务器迁移指南)
- [6. 常见问题排查](#6-常见问题排查)
- [7. AI 提示词](#7-ai-提示词)

---

## 🛠️ 1. 初始化 (One-Key Setup)

在新服务器执行此命令。它将自动完成：
- 挂载数据盘（如果有就会自动挂载，没有则忽略）
- 安装 Docker 和 Docker Compose
- 创建专用网络 `proxynet`
- 建立标准化目录结构
- 设置合理权限

### 前置要求

- 确保数据盘已挂载到 `/data`（若无独立数据盘,脚本将在系统盘创建）
- 需要 root 或具有 sudo 权限的用户执行
- 系统需要能够访问互联网（用于下载 Docker）

### 初始化脚本

```bash
# 复制整段执行：初始化系统环境
set -e

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
    echo "❌ 请使用 root 权限执行此脚本"
    exit 1
fi

# 安装 Docker
echo "📦 正在安装 Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
else
    echo "✓ Docker 已安装"
fi

# 创建专用网络
echo "🌐 创建 Docker 网络..."
docker network create proxynet 2>/dev/null || echo "✓ 网络 proxynet 已存在"

# 创建目录结构
echo "📁 创建目录结构..."
mkdir -p /data/{stacks,shared/{media,downloads,backups},scripts,logs}

# 设置权限（更安全的权限模型）
echo "🔐 配置权限..."
chown -R 1000:1000 /data
chmod 750 /data
chmod -R u+rwX,g+rX,o-rwx /data

# 创建配置文件
echo "📝 创建环境配置..."
cat > /data/.env << 'ENVEOF'
# 全局环境变量
PUID=1000
PGID=1000
TZ=Asia/Shanghai
ENVEOF

# 显示目录结构
echo ""
echo "✅ 环境初始化完毕！目录结构："
tree -L 2 /data 2>/dev/null || ls -lah /data

echo ""
echo "📊 系统信息："
echo "- Docker 版本: $(docker --version)"
echo "- 数据目录: /data"
echo "- 可用空间: $(df -h /data | tail -1 | awk '{print $4}')"

---

## 🚀 2. 核心服务部署

### 2.1 部署 Dockge（管理面板）

**访问地址**：`http://<服务器IP>:5001`

```bash
# 复制整段执行：部署 Dockge
mkdir -p /data/stacks/dockge && cd /data/stacks/dockge

cat > compose.yaml << 'EOF'
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    ports:
      - "5001:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - /data/stacks:/data/stacks
    environment:
      - DOCKGE_STACKS_DIR=/data/stacks
      - TZ=Asia/Shanghai
    networks:
      - proxynet
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  proxynet:
    external: true
EOF

docker compose up -d

echo ""
echo "✅ Dockge 已启动"
echo "📍 访问地址: http://$(hostname -I | awk '{print $1}'):5001"
echo "🔑 首次访问需要设置管理员账号"
```

### 2.2 部署 Caddy（反向代理网关）

```bash
# 复制整段执行：部署 Caddy
mkdir -p /data/stacks/caddy && cd /data/stacks/caddy

# 创建初始 Caddyfile
cat > Caddyfile << 'EOF'
# Caddy 全局配置
{
    email admin@example.com
    admin off
}

# 示例：Dockge 反向代理（需要配置域名 DNS）
# dockge.example.com {
#     reverse_proxy dockge:5001
# }

# 健康检查端点
:80 {
    respond /health 200
}
EOF

cat > compose.yaml << 'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"  # HTTP/3 支持
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./data:/data
      - ./config:/config
      - /data/logs/caddy:/var/log/caddy
    environment:
      - TZ=Asia/Shanghai
    networks:
      - proxynet
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  proxynet:
    external: true
EOF

docker compose up -d

echo ""
echo "✅ Caddy 网关已就绪"
echo "📝 配置文件: /data/stacks/caddy/Caddyfile"
echo "🔍 测试命令: curl http://localhost/health"
```

### 2.2.1 Caddy的一键脚本
```bash
# 一键部署 Caddy 管理快捷命令
cat > /usr/local/bin/caddy << 'EOF'
#!/bin/bash

# Caddy 管理脚本
# 工作目录
CADDY_DIR="/data/stacks/caddy"
CADDYFILE="$CADDY_DIR/Caddyfile"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否在正确的目录
check_dir() {
    if [ ! -d "$CADDY_DIR" ]; then
        echo -e "${RED}错误: Caddy 目录不存在 ($CADDY_DIR)${NC}"
        exit 1
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       Caddy 管理工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 启动 Caddy"
    echo -e "${GREEN}2.${NC} 关闭 Caddy"
    echo -e "${GREEN}3.${NC} 编辑配置文件"
    echo -e "${GREEN}4.${NC} 重载配置"
    echo -e "${GREEN}5.${NC} 重启 Caddy"
    echo -e "${GREEN}6.${NC} 查看状态"
    echo -e "${GREEN}7.${NC} 查看日志"
    echo -e "${GREEN}8.${NC} 测试配置"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

# 启动 Caddy
start_caddy() {
    echo -e "${YELLOW}正在启动 Caddy...${NC}"
    cd $CADDY_DIR
    docker compose up -d
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Caddy 启动成功${NC}"
    else
        echo -e "${RED}❌ Caddy 启动失败${NC}"
    fi
}

# 关闭 Caddy
stop_caddy() {
    echo -e "${YELLOW}正在关闭 Caddy...${NC}"
    cd $CADDY_DIR
    docker compose down
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Caddy 已关闭${NC}"
    else
        echo -e "${RED}❌ Caddy 关闭失败${NC}"
    fi
}

# 编辑配置文件
edit_config() {
    echo -e "${YELLOW}打开配置文件编辑器...${NC}"
    echo -e "${BLUE}配置文件路径: $CADDYFILE${NC}"
    echo ""
    echo -e "${YELLOW}提示：${NC}"
    
    # 优先使用 nano (最简单)，其次 vim, vi
    if command -v nano &> /dev/null; then
        echo -e "${GREEN}使用 nano 编辑器 (Ctrl+O 保存, Ctrl+X 退出)${NC}"
        sleep 1
        nano $CADDYFILE
    elif command -v vim &> /dev/null; then
        echo -e "${GREEN}使用 vim 编辑器${NC}"
        echo -e "${BLUE}基本操作: 按 i 进入编辑模式, 编辑完成后按 ESC, 然后输入 :wq 保存退出${NC}"
        sleep 2
        vim $CADDYFILE
    elif command -v vi &> /dev/null; then
        echo -e "${GREEN}使用 vi 编辑器${NC}"
        echo -e "${BLUE}基本操作: 按 i 进入编辑模式, 编辑完成后按 ESC, 然后输入 :wq 保存退出${NC}"
        sleep 2
        vi $CADDYFILE
    elif [ -n "$EDITOR" ]; then
        $EDITOR $CADDYFILE
    else
        echo -e "${RED}❌ 未找到可用的编辑器${NC}"
        echo -e "${YELLOW}请先安装编辑器: apt install nano 或 yum install nano${NC}"
        return 1
    fi
    
    # 编辑完成后询问是否重载
    echo ""
    echo -e "${YELLOW}配置文件已编辑完成${NC}"
    read -p "是否重载 Caddy 配置？(y/n): " choice
    case "$choice" in 
        y|Y|yes|YES ) reload_caddy;;
        * ) echo -e "${BLUE}已取消重载${NC}";;
    esac
}

# 重载配置
reload_caddy() {
    echo -e "${YELLOW}正在重载 Caddy 配置...${NC}"
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 配置重载成功${NC}"
    else
        echo -e "${RED}❌ 配置重载失败${NC}"
    fi
}

# 重启 Caddy
restart_caddy() {
    echo -e "${YELLOW}正在重启 Caddy...${NC}"
    cd $CADDY_DIR
    docker compose restart
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Caddy 重启成功${NC}"
    else
        echo -e "${RED}❌ Caddy 重启失败${NC}"
    fi
}

# 查看状态
show_status() {
    echo -e "${BLUE}========== Caddy 状态 ==========${NC}"
    cd $CADDY_DIR
    docker compose ps
    echo ""
    echo -e "${BLUE}========== 容器详情 ==========${NC}"
    docker inspect caddy --format='{{.State.Status}}' 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}容器运行状态: $(docker inspect caddy --format='{{.State.Status}}')${NC}"
        echo -e "${GREEN}启动时间: $(docker inspect caddy --format='{{.State.StartedAt}}')${NC}"
    else
        echo -e "${RED}容器未运行${NC}"
    fi
}

# 查看日志
show_logs() {
    echo -e "${YELLOW}显示 Caddy 日志 (Ctrl+C 退出)${NC}"
    cd $CADDY_DIR
    docker compose logs -f --tail=50
}

# 测试配置
test_config() {
    echo -e "${YELLOW}正在测试 Caddy 配置...${NC}"
    docker exec caddy caddy validate --config /etc/caddy/Caddyfile
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 配置文件语法正确${NC}"
    else
        echo -e "${RED}❌ 配置文件有错误${NC}"
    fi
}

# 主循环
main() {
    check_dir
    
    while true; do
        show_menu
        read -p "请选择操作 [0-8]: " choice
        echo ""
        
        case $choice in
            1) start_caddy ;;
            2) stop_caddy ;;
            3) edit_config ;;
            4) reload_caddy ;;
            5) restart_caddy ;;
            6) show_status ;;
            7) show_logs ;;
            8) test_config ;;
            0) 
                echo -e "${GREEN}退出 Caddy 管理工具${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${NC}"
                ;;
        esac
        
        echo ""
        read -p "按 Enter 键继续..." dummy
    done
}

# 运行主程序
main
EOF

chmod +x /usr/local/bin/caddy

echo ""
echo "✅ Caddy 管理命令已安装完成！"
echo "📝 现在你可以在任何地方输入 'caddy' 来管理 Caddy 了"
echo ""
```


### 2.3 部署 Watchtower（自动更新容器）

```bash
# 复制整段执行：部署 Watchtower
mkdir -p /data/stacks/watchtower && cd /data/stacks/watchtower

cat > compose.yaml << 'EOF'
services:
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=Asia/Shanghai
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_SCHEDULE=0 0 4 * * *  # 每天凌晨 4 点检查更新
      - WATCHTOWER_LABEL_ENABLE=true  # 只更新带标签的容器
    command: --interval 86400

networks:
  proxynet:
    external: true
EOF

docker compose up -d

echo "✅ Watchtower 已启动（每天 04:00 自动检查更新）"
```

---

## 🛡️ 3. 自动备份策略

**备份内容**：每日凌晨 3 点自动备份 `/data/stacks`（排除大体积媒体/下载目录）  
**保留策略**：保留最近 7 天的备份

### 步骤 1：创建备份脚本

```bash
# 复制整段执行：创建带日志的备份脚本
cat > /data/scripts/backup.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# 配置变量
BACKUP_DIR="/data/shared/backups"
SOURCE_DIR="/data/stacks"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$BACKUP_DIR/backup.log"
RETENTION_DAYS=7

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 记录开始时间
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========== 备份开始 ==========" >> "$LOG_FILE"

# 检查源目录是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ 错误: 源目录不存在 $SOURCE_DIR" >> "$LOG_FILE"
    exit 1
fi

# 执行备份（排除大目录和临时文件）
BACKUP_FILE="$BACKUP_DIR/stacks_backup_$DATE.tar.gz"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📦 正在创建备份..." >> "$LOG_FILE"

tar -czf "$BACKUP_FILE" \
    --exclude='*/media' \
    --exclude='*/downloads' \
    --exclude='*/cache' \
    --exclude='*/temp' \
    --exclude='*.log' \
    -C "$(dirname $SOURCE_DIR)" \
    "$(basename $SOURCE_DIR)" 2>&1 | tee -a "$LOG_FILE"

# 检查备份是否成功
if [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 备份成功: $BACKUP_FILE (大小: $BACKUP_SIZE)" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ 备份失败" >> "$LOG_FILE"
    exit 1
fi

# 清理旧备份
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🧹 清理 $RETENTION_DAYS 天前的备份..." >> "$LOG_FILE"
DELETED_COUNT=$(find "$BACKUP_DIR" -name "stacks_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已删除 $DELETED_COUNT 个旧备份文件" >> "$LOG_FILE"

# 显示当前备份列表
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📋 当前备份列表:" >> "$LOG_FILE"
ls -lh "$BACKUP_DIR"/stacks_backup_*.tar.gz 2>/dev/null | tail -5 >> "$LOG_FILE" || echo "无备份文件" >> "$LOG_FILE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========== 备份完成 ==========\n" >> "$LOG_FILE"
EOF

chmod +x /data/scripts/backup.sh
echo "✅ 备份脚本已创建: /data/scripts/backup.sh"
```

### 步骤 2：添加定时任务

```bash
# 复制整段执行：添加每日 3:00 的 cron 任务
(crontab -l 2>/dev/null | grep -v backup.sh; echo "0 3 * * * /data/scripts/backup.sh") | crontab -

echo "✅ 定时任务已配置（每天 03:00 执行）"
echo "📝 查看任务: crontab -l"
```

### 步骤 3：验证备份系统

```bash
# 手动测试备份
/data/scripts/backup.sh

# 查看备份日志
tail -20 /data/shared/backups/backup.log

# 列出所有备份
ls -lh /data/shared/backups/*.tar.gz
```

### 恢复备份（示例）

```bash
# 停止所有服务
cd /data/stacks/dockge && docker compose down

# 恢复指定日期的备份
tar -xzf /data/shared/backups/stacks_backup_20251206_030000.tar.gz -C /data

# 重启服务
docker compose up -d
```

---

## 📝 4. 标准部署模板

在 Dockge 中新建服务时，请严格遵循此模板。

### 4.1 基础模板

```yaml
# docker-compose.yaml 标准模板
services:
  app_name:  # ← 替换为实际服务名
    image: vendor/image:latest
    container_name: app_name
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
    volumes:
      - ./data:/config          # 配置文件（相对路径）
      - /data/shared/media:/media     # 共享媒体库（绝对路径）
    networks:
      - proxynet
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  proxynet:
    external: true
```

### 4.2 带数据库的服务模板

```yaml
services:
  app:
    image: vendor/app:latest
    container_name: app
    restart: unless-stopped
    depends_on:
      - db
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - DB_HOST=db
      - DB_PORT=5432
      - DB_NAME=appdb
      - DB_USER=appuser
      - DB_PASSWORD=change_this_password
    volumes:
      - ./data:/config
    networks:
      - proxynet

  db:
    image: postgres:16-alpine
    container_name: app_db
    restart: unless-stopped
    environment:
      - POSTGRES_DB=appdb
      - POSTGRES_USER=appuser
      - POSTGRES_PASSWORD=change_this_password
      - TZ=Asia/Shanghai
    volumes:
      - ./data/db:/var/lib/postgresql/data
    networks:
      - proxynet

networks:
  proxynet:
    external: true
```

### 4.3 Caddyfile 配置示例

```caddyfile
# 添加到 /data/stacks/caddy/Caddyfile

app.example.com {
    reverse_proxy app:端口号
    
    # 可选：启用日志
    log {
        output file /var/log/caddy/app.log
    }
    
    # 可选：启用压缩
    encode gzip
}
```

---

## 🚚 5. 服务器迁移指南

### 迁移流程图

```
旧服务器                    新服务器
   |                          |
   |-- 1. 停止服务             |
   |-- 2. 数据同步 ---------> |-- 3. 接收数据
   |                          |-- 4. 初始化环境
   |                          |-- 5. 启动服务
   |                          |-- 6. 验证功能
```

### 步骤 1：旧服务器数据准备

```bash
# 在旧服务器执行

# 停止所有容器（保留配置）
docker stop $(docker ps -aq) 2>/dev/null || echo "无运行中的容器"

# 创建最终备份
/data/scripts/backup.sh

# 显示数据大小
echo "📊 数据统计:"
du -sh /data/*

# 同步数据到新服务器（需提前配置 SSH 密钥）
# 替换 NEW_SERVER_IP 为新服务器地址
rsync -avz --progress \
    --exclude='/data/shared/media' \
    --exclude='/data/shared/downloads' \
    /data/ root@NEW_SERVER_IP:/data/

echo "✅ 小文件同步完成"
echo "💡 大文件目录（media/downloads）建议后台单独同步"
```

### 步骤 2：新服务器初始化

```bash
# 在新服务器执行

# 1. 执行初始化脚本（见第 1 节）
# 2. 等待数据同步完成
# 3. 启动核心服务

cd /data/stacks/dockge
docker compose up -d

cd /data/stacks/caddy
docker compose up -d

echo "✅ 核心服务已启动"
echo "📍 登录 Dockge: http://$(hostname -I | awk '{print $1}'):5001"
```

### 步骤 3：恢复所有服务

1. 打开 Dockge 面板：`http://<新服务器IP>:5001`
2. 点击 **"Scan Stacks Folder"**
3. 所有服务自动识别
4. 逐个点击 **"Start"** 启动服务

### 步骤 4：验证迁移

```bash
# 检查所有容器状态
docker ps -a

# 检查网络连接
docker network inspect proxynet

# 测试 Caddy 反向代理
curl -I http://localhost/health

# 检查日志
docker logs dockge
docker logs caddy
```

---

## 🔍 6. 常见问题排查

### 问题 1：容器无法启动

```bash
# 查看容器日志
docker logs <container_name>

# 查看详细信息
docker inspect <container_name>

# 检查端口占用
netstat -tulnp | grep <port>
```

### 问题 2：权限错误

```bash
# 重置 /data 权限
chown -R 1000:1000 /data
chmod -R u+rwX,g+rX /data

# 检查特定目录
ls -lah /data/stacks/<service_name>
```

### 问题 3：网络连接问题

```bash
# 检查网络是否存在
docker network ls | grep proxynet

# 重建网络
docker network rm proxynet
docker network create proxynet

# 重启服务
cd /data/stacks/<service> && docker compose restart
```

### 问题 4：磁盘空间不足

```bash
# 清理未使用的镜像
docker image prune -a

# 清理未使用的卷
docker volume prune

# 清理构建缓存
docker builder prune -a

# 查看磁盘占用
df -h /data
du -sh /data/*
```

### 问题 5：备份失败

```bash
# 检查备份日志
tail -50 /data/shared/backups/backup.log

# 手动执行测试
bash -x /data/scripts/backup.sh

# 检查磁盘空间
df -h /data/shared/backups
```

---

## 🤖 7. AI 提示词

### 标准提示词模板
```bash
你是我的系统架构师。请基于 **"Infrastructure as Data"** 架构规范，为我生成符合生产环境标准的 Docker Compose 部署方案。

【角色目标】
生成一份“零摩擦”的部署配置，确保服务启动即通过，无需手动进入容器修改配置，且文件结构清晰、权限正确。

【强制规范】

1. **输出顺序标准（严格执行）**
    * **第一步 (`init.sh`)**：文件系统初始化、权限修正、核心配置预埋。
    * **第二步 (`compose.yaml`)**：容器编排定义。
    * **第三步 (`Caddyfile`)**：反向代理配置。

2. **持久化目录标准**
    * 应用配置：挂载 `./data`（当前 compose 所在目录下的子目录）。
    * 媒体/大文件：挂载 `/data/shared/media`（全局共享，只读建议）。
    * 数据库文件：挂载 `./data/db`。
    * **权限原则**：必须确保宿主机挂载目录的权限归属为 `PUID:PGID`。

3. **网络与端口策略**
    * **显式映射端口**：必须使用 `ports` 暴露主要端口（格式 `宿主机端口:容器端口`），以便支持直连调试。
    * **外部网络**：必须加入外部网络 `proxynet`（用于 Caddy 内部通信）。
    * **敏感服务检查**：如果服务属于易受攻击或有默认访问限制的类型（如 qBittorrent, Jupyter, Redis）：
        * 必须在 `init.sh` 中预生成配置文件以允许非 Localhost 访问（关闭 HostHeaderValidation 等）。
        * 或者在注释中明确提示是否需要为了安全而移除 `ports` 映射。

4. **环境与容器配置**
    * **环境变量**：`PUID=1000`, `PGID=1000`, `TZ=Asia/Shanghai`。
    * **重启策略**：`restart: unless-stopped`。
    * **更新管理**：添加 label `com.centurylinklabs.watchtower.enable=true`。
    * **安全性**：禁止使用默认密码（使用 `environment` 传递强密码或随机生成），非必要不使用 root 运行。

【输出要求】

**请不要输出任何解释性废话，直接按顺序输出以下三个代码块：**

#### Block 1: `init.sh`
* **功能**：一键初始化脚本。
* **内容要求**：
    1.  `mkdir -p` 创建所有挂载目录。
    2.  **[关键] 配置预埋**：对于 qBittorrent 等默认拒绝公网 IP 访问的服务，**必须**在此处使用 `cat > ... <<EOF` 预写入配置文件（如关闭 CSRF/HostHeader 检查），确保服务启动后不会报 "Unauthorized"。
    3.  `chown -R 1000:1000` 修正目录权限。
    4.  输出 "Initialization complete" 提示。

#### Block 2: `compose.yaml`
* 包含完整的服务定义，显式端口映射，网络配置。

#### Block 3: `Caddyfile`
* 格式：`服务名.example.com { reverse_proxy 容器名:内部端口 }`

---

**【当前任务】**

请为我部署：[在此处输入服务名称]
```
---

## 📚 附录

### A. 目录结构说明

```
/data/
├── stacks/              # 所有服务的 compose 文件
│   ├── dockge/          # 管理面板
│   ├── caddy/           # 反向代理
│   └── <service>/       # 其他服务
│       ├── compose.yaml
│       └── data/        # 服务配置数据
├── shared/              # 跨服务共享目录
│   ├── media/           # 媒体文件
│   ├── downloads/       # 下载文件
│   └── backups/         # 备份文件
├── scripts/             # 自动化脚本
│   └── backup.sh
├── logs/                # 日志文件
│   └── caddy/
└── .env                 # 全局环境变量
```

### B. 端口使用规范

- **80/443**：Caddy（HTTP/HTTPS 网关）
- **5001**：Dockge（管理面板）
- **其他服务**：不暴露端口，通过 Caddy 反代访问

### C. 推荐服务清单

**基础设施**：
- Dockge - 容器管理
- Caddy - 反向代理
- Watchtower - 自动更新

**媒体服务**：
- Jellyfin / Emby - 媒体服务器
- qBittorrent - 下载工具
- Sonarr / Radarr - 媒体管理

**生产力工具**：
- Vaultwarden - 密码管理
- Nextcloud - 私有云盘
- Gitea - Git 服务器

**监控工具**：
- Uptime Kuma - 服务监控
- Grafana - 数据可视化
- Prometheus - 指标收集

---

## 📄 许可与贡献

本文档遵循 MIT 许可证。欢迎提交 Issue 和 Pull Request。

**维护者**：您的名字  
**最后更新**：2025-12-06  
**文档版本**：v2.0

---

## 🎯 快速开始检查清单

- [ ] 数据盘已挂载到 `/data`
- [ ] 执行初始化脚本
- [ ] 部署 Dockge 管理面板
- [ ] 部署 Caddy 反向代理
- [ ] 配置自动备份
- [ ] 测试服务部署
- [ ] 配置域名解析（可选）
- [ ] 启用 HTTPS（可选）

**恭喜！您的服务器架构已就绪。** 🎉
