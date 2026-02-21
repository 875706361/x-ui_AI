# x-ui CPU 优化方案

## 问题分析

x-ui 项目在长期运行后会出现 CPU 满载的情况，主要原因包括：

1. **频繁读取 /proc 文件**：TCP/UDP 连接数统计每次都读取完整文件
2. **系统调用无超时机制**：gopsutil 库调用可能长时间阻塞
3. **日志刷屏**：大量重复警告信息消耗 CPU
4. **大文件读取**：高连接量时 /proc/net/tcp 文件可能很大

## 优化方案

### 1. 连接数统计缓存 (`util/sys/sys_linux.go`)

- 添加 5 秒缓存，避免频繁读取 /proc 文件
- 添加文件大小保护 (>1MB 不完整读取)
- 使用互斥锁保证线程安全

```go
cacheDuration = 5 * time.Second
maxFileSizeLimit = 1024 * 1024
```

### 2. 系统调用超时机制 (`web/service/server.go`)

所有系统监控调用都添加了超时保护：

- CPU 统计：3 秒超时
- TCP/UDP 统计：2 秒超时
- 内存/磁盘/网络：2 秒超时
- Uptime/Load：2 秒超时

```go
select {
case result := <-cpuDone:
    status.Cpu = percents[0]
case <-time.After(3 * time.Second):
    logger.Warning("get cpu percent timeout")
}
```

### 3. 日志警告抑制 (`logger/logger.go`)

同一警告消息 30 秒内只记录一次，避免日志刷屏：

```go
warningCooldown = 30 * time.Second
```

### 4. systemd 资源限制

在服务配置中添加资源限制：

```ini
CPUQuota=200%      # 最多使用 2 个 CPU 核心
MemoryMax=1G       # 最大内存限制 1GB
LimitNOFILE=65536  # 文件描述符限制
```

## 安装使用

### 方法一：使用安装脚本（推荐）

```bash
cd /root/CLAY/x-ui
./install.sh
```

安装脚本会自动：
1. 检查并安装 Go 环境
2. 安装系统依赖
3. 编译优化后的代码
4. 配置 systemd 服务
5. 启动服务

### 方法二：手动安装

```bash
# 1. 安装 Go（如果没有）
wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
tar -C /usr/local -xzf go.tar.gz
export PATH=$PATH:/usr/local/go/bin

# 2. 编译项目
cd /root/CLAY/x-ui
go build -o x-ui main.go
chmod +x x-ui

# 3. 配置 systemd
cp /root/CLAY/x-ui/x-ui.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui
```

## 可选：启用监控脚本

监控脚本会在 CPU 使用率超过 80% 时自动重启服务：

```bash
# 安装监控服务
cp /root/CLAY/x-ui/x-ui-monitor.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable x-ui-monitor
systemctl start x-ui-monitor

# 查看监控日志
tail -f /var/log/x-ui-monitor.log
```

## 常用命令

```bash
# 服务管理
systemctl start x-ui      # 启动
systemctl stop x-ui       # 停止
systemctl restart x-ui    # 重启
systemctl status x-ui     # 状态

# 日志查看
journalctl -u x-ui -f     # 实时日志
journalctl -u x-ui -n 100 # 最近 100 条

# 监控服务（如果启用）
systemctl status x-ui-monitor
tail -f /var/log/x-ui-monitor.log
```

## 效果对比

| 指标 | 优化前 | 优化后 |
|------|--------|--------|
| CPU 峰值 | 100%+ | <200% (受限制) |
| 响应时间 | 可能卡死 | <3秒 |
| 日志量 | 大量重复 | 正常水平 |
| 稳定性 | 长期运行崩溃 | 自动恢复 |

## 注意事项

1. **首次部署建议**：先在测试环境验证，确认无问题后再部署到生产环境
2. **资源限制调整**：根据实际需求调整 `CPUQuota` 和 `MemoryMax`
3. **监控日志**：定期检查 `/var/log/x-ui-monitor.log` 了解服务运行情况
4. **版本兼容**：优化基于当前版本代码，升级前请备份修改

## 故障排查

如果服务无法启动：

```bash
# 查看详细错误
journalctl -u x-ui -n 50 --no-pager

# 手动运行测试
cd /root/CLAY/x-ui
./x-ui

# 检查端口占用
netstat -tuln | grep 54321
```

## 文件说明

- `install.sh` - 自动安装脚本
- `monitor.sh` - 资源监控脚本
- `x-ui.service` - systemd 服务配置
- `x-ui-monitor.service` - 监控服务配置
- `util/sys/sys_linux.go` - 系统调用优化
- `logger/logger.go` - 日志优化
- `web/service/server.go` - 状态监控优化