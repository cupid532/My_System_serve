## rsync 定时同步操作指南

### 一、前提条件

- 源服务器 A（当前机器）
- 目标服务器 B/C（需要 root 或有写权限的用户）
- 两台机器都安装了 rsync

---

### 二、配置 SSH 免密登录

在源服务器上执行：

```bash
# 1. 生成密钥（如果已有可跳过）
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

# 2. 复制公钥到目标服务器
ssh-copy-id root@目标服务器IP

# 3. 测试连接
ssh root@目标服务器IP "echo ok"
```

---

### 三、配置定时同步任务

```bash
# 编辑 crontab
crontab -e

# 添加同步任务（每小时整点执行）
0 * * * * /usr/bin/rsync -avz /data/ root@目标服务器IP:/data/ >> /var/log/rsync.log 2>&1
```

参数说明：
- `-a`：归档模式，保留权限、时间等
- `-v`：显示详细信息
- `-z`：传输时压缩

---

### 四、从服务器 B 迁移到服务器 C

在服务器 B 上执行：

```bash
# 1. 配置 B 到 C 的免密登录
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
ssh-copy-id root@服务器C的IP

# 2. 一次性全量同步
rsync -avz --progress /data/ root@服务器C的IP:/data/

# 3. 如需持续同步，添加 crontab
crontab -e
# 添加：
0 * * * * /usr/bin/rsync -avz /data/ root@服务器C的IP:/data/ >> /var/log/rsync.log 2>&1
```

---

### 五、常用命令

```bash
# 查看当前 crontab
crontab -l

# 查看同步日志
tail -f /var/log/rsync.log

# 手动测试同步（不实际执行）
rsync -avzn /data/ root@目标IP:/data/

# 删除目标端多余文件（谨慎使用）
rsync -avz --delete /data/ root@目标IP:/data/
```
