#!/bin/bash

# x-ui 安装与优化脚本
# 解决 CPU 满载问题并自动安装所需依赖

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
INSTALL_DIR="/root/CLAY/x-ui"
BINARY_NAME="x-ui"
SERVICE_NAME="x-ui"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   x-ui 安装与优化脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 用户运行此脚本${NC}"
    exit 1
fi

# 检查 Go 是否安装
echo -e "${YELLOW}[1/7] 检查 Go 环境...${NC}"
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}   Go 未安装，正在安装 Go 1.21.6...${NC}"
    cd /tmp
    wget -q https://go.dev/dl/go1.21.6.linux-amd64.tar.gz -O go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go.tar.gz
    rm -f go.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    export PATH=$PATH:/usr/local/go/bin
    echo -e "${GREEN}   Go 安装成功${NC}"
else
    GO_VERSION=$(go version | awk '{print $3}')
    echo -e "${GREEN}   Go 已安装: ${GO_VERSION}${NC}"
fi

# 安装系统依赖
echo ""
echo -e "${YELLOW}[2/7] 安装系统依赖...${NC}"
if command -v apt-get &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq wget curl unzip build-essential bc 2>/dev/null || true
elif command -v yum &> /dev/null; then
    yum install -y -q wget curl unzip gcc make bc 2>/dev/null || true
fi
echo -e "${GREEN}   系统依赖安装完成${NC}"

# 编译项目
echo ""
echo -e "${YELLOW}[3/7] 编译 x-ui 项目...${NC}"
cd "$INSTALL_DIR"
if [ -f "go.mod" ]; then
    echo "   下载依赖..."
    go mod download
    echo "   编译中..."
    CGO_ENABLED=0 go build -o x-ui main.go
    chmod +x x-ui
    echo -e "${GREEN}   编译成功: $(du -h x-ui | cut -f1)${NC}"
else
    echo -e "${RED}   错误: 未找到 go.mod 文件${NC}"
    exit 1
fi

# 停止现有服务
echo ""
echo -e "${YELLOW}[4/7] 停止现有服务...${NC}"
if systemctl is-active --quiet x-ui 2>/dev/null; then
    systemctl stop x-ui
    echo -e "${GREEN}   服务已停止${NC}"
else
    echo -e "${YELLOW}   服务未运行${NC}"
fi

# 创建优化的 systemd 服务文件
echo ""
echo -e "${YELLOW}[5/7] 配置 systemd 服务...${NC}"
cat > /etc/systemd/system/x-ui.service << 'EOF'
[Unit]
Description=x-ui Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/root/CLAY/x-ui
ExecStart=/root/CLAY/x-ui/x-ui

# 资源限制 - 防止 CPU 满载
CPUQuota=200%      # 最多使用 2 个 CPU 核心
MemoryMax=1G       # 最大内存限制 1GB
LimitNOFILE=65536  # 文件描述符限制

# 安全设置
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=true
ProtectHome=true

# 重启策略
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo -e "${GREEN}   服务配置完成 (CPU 限制: 200%, 内存: 1GB)${NC}"

# 启用并启动服务
echo ""
echo -e "${YELLOW}[6/7] 启动 x-ui 服务...${NC}"
systemctl enable x-ui
systemctl start x-ui
sleep 3

if systemctl is-active --quiet x-ui; then
    echo -e "${GREEN}   服务启动成功!${NC}"
else
    echo -e "${RED}   服务启动失败，请检查日志: journalctl -u x-ui${NC}"
    exit 1
fi

# 显示服务状态
echo ""
echo -e "${YELLOW}[7/7] 服务状态...${NC}"
systemctl status x-ui --no-pager -l | head -n 15

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   安装完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "常用命令:"
echo -e "  启动服务:   systemctl start x-ui"
echo -e "  停止服务:   systemctl stop x-ui"
echo -e "  重启服务:   systemctl restart x-ui"
echo -e "  查看状态:   systemctl status x-ui"
echo -e "  查看日志:   journalctl -u x-ui -f"
echo ""
echo -e "${YELLOW}优化说明:${NC}"
echo -e "  1. 添加了系统资源限制 (CPU 200%, 内存 1GB)"
echo -e "  2. 添加了所有系统调用的超时机制"
echo -e "  3. 添加了 TCP/UDP 连接数统计缓存 (5秒)"
echo -e "  4. 添加了日志警告抑制机制 (30秒)"
echo -e "  5. 添加了大文件读取保护 (>1MB 不完整读取)"
echo ""
