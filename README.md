# 📄 1. 最终版 VitePress 文档 (`server-guide.md`)

直接覆盖保存即可。

````markdown
---
title: 终极服务器架构：数据即基础设施
date: 2025-12-06
password: 532
aside: true
outline: deep
---

# 🏛️ 终极服务器架构：数据即基础设施

> **核心理念**：操作系统是“耗材”，只有 `/data` 是“资产”。
> **设计目标**：原子级迁移、权限零焦虑、全自动化维护。

---

## 🛠️ 1. 初始化 (One-Key Setup)

在**新服务器**执行此命令。它将自动完成：安装 Docker、创建专用网络 `proxynet`、建立目录结构、修正权限。

::: tip 前置要求
请确保数据盘已挂载到 `/data`。若无独立数据盘，脚本将直接在系统盘创建目录。
:::

```bash
# 复制整段执行：初始化系统环境
curl -fsSL [https://get.docker.com](https://get.docker.com) | sh && \
docker network create proxynet || true && \
mkdir -p /data/stacks /data/shared/media /data/shared/downloads /data/shared/backups /data/scripts && \
chown -R 1000:1000 /data && \
chmod -R 755 /data && \
echo "✅ 环境初始化完毕"
````

-----

## 🚀 2. 核心服务部署

### 2.1 部署 Dockge (管理面板)

复制以下命令，**一次性**启动管理面板。访问端口：`5001`。

```bash
# 复制整段执行：部署 Dockge
mkdir -p /data/stacks/dockge && cd /data/stacks/dockge && \
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
    networks:
      - proxynet

networks:
  proxynet:
    external: true
EOF
docker compose up -d && echo "✅ Dockge 已启动: http://IP:5001"
```

### 2.2 部署 Caddy (网关)

复制以下命令，启动反向代理网关。

```bash
# 复制整段执行：部署 Caddy
mkdir -p /data/stacks/caddy && cd /data/stacks/caddy && \
touch Caddyfile && \
cat > compose.yaml << 'EOF'
services:
  caddy:
    image: caddy:alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./data:/data
      - ./config:/config
    networks:
      - proxynet

networks:
  proxynet:
    external: true
EOF
docker compose up -d && echo "✅ Caddy 网关已就绪"
```

-----

## 🛡️ 3. 自动备份策略 (Auto Backup)

这是保障数据安全的关键。我们将配置一个脚本，每天凌晨 3 点自动打包所有服务的配置数据，并保留最近 7 天的备份。

**步骤 1：一键安装备份脚本**

```bash
# 复制整段执行：创建备份脚本
cat > /data/scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/data/shared/backups"
SOURCE_DIR="/data/stacks"
DATE=$(date +%Y%m%d)

# 1. 压缩所有 stack 的 data 目录 (排除大文件)
tar -czf "$BACKUP_DIR/stacks_backup_$DATE.tar.gz" \
    --exclude='*/media' --exclude='*/downloads' \
    -C "$SOURCE_DIR" .

# 2. 删除 7 天前的旧备份
find "$BACKUP_DIR" -name "stacks_backup_*.tar.gz" -mtime +7 -exec rm {} \;
echo "Backup completed: $DATE"
EOF
chmod +x /data/scripts/backup.sh && echo "✅ 备份脚本已创建"
```

**步骤 2：添加定时任务**

```bash
# 复制整段执行：写入 Crontab (每天凌晨 3:00 执行)
(crontab -l 2>/dev/null; echo "0 3 * * * /data/scripts/backup.sh") | crontab - && echo "✅ 定时任务已添加"
```

-----

## 📝 4. 标准部署模版

在 Dockge 中新建服务时，请务必使用此模板。

```yaml
services:
  # 服务名 (修改此处)
  app_name:
    image: vendor/image:latest
    container_name: app_name
    restart: unless-stopped
    environment:
      - PUID=1000          # 权限统一
      - PGID=1000
      - TZ=Asia/Shanghai   # 时区统一
    volumes:
      - ./data:/config           # 配置：存放在当前目录下
      - /data/shared/media:/media # 数据：引用共享池
    networks:
      - proxynet                 # 网络：仅加入内部网

networks:
  proxynet:
    external: true
```

-----

## 🚚 5. 服务器迁移指南

只需两步，完成全量迁移。

1.  **旧服务器**：发送数据。

    ```bash
    docker stop $(docker ps -a -q) && \
    rsync -avz --delete /data/ root@新IP:/data/
    ```

2.  **新服务器**：环境复活。
    *(先执行本文第1步初始化环境)*

    ```bash
    cd /data/stacks/dockge && docker compose up -d
    # 随后登录 Dockge 面板，点击 "Scan Stacks Folder" 复活所有服务
    ```

<!-- end list -->

```

---

### 🤖 2. 专用 AI 提示词 (Prompt)

发送给任意 AI，一键生成符合上述架构的配置。

**复制以下内容：**

> 你是我的系统架构师。请基于 "Infrastructure as Data" 规范为我生成 Docker Compose 配置。
>
> **严格规范：**
> 1.  **目录**：持久化数据必须挂载在 `./data` (相对路径)。大型媒体文件挂载 `/data/shared/media` (绝对路径)。
> 2.  **网络**：不暴露端口 (No `ports`)，只加入外部网络 `proxynet`。
> 3.  **权限**：环境变量必须包含 `PUID=1000`, `PGID=1000`, `TZ=Asia/Shanghai`。
> 4.  **反代**：附带 Caddyfile 配置段落 (假设域名 `服务名.example.com`)。
>
> **输出要求：**
> * 不要解释，直接给出 YAML 代码块。
> * 如果涉及数据库，数据库文件也存放在 `./data/db` 中。
>
> **任务：请为我部署 [在此输入服务名称，如: Halo / Vaultwarden / Emby]**
```
