#!/bin/bash

# x-ui 智能全自动部署脚本 (集成版)
# 功能：自动编译、安装、Swap配置、开机自启
# 特点：优化逻辑已集成到二进制文件中，启动时自动执行

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量
INSTALL_DIR="/usr/local/x-ui"
SERVICE_NAME="x-ui"
LOG_FILE="/var/log/x-ui-install.log"

# 输出并记录日志
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
    echo "[$(date +'%H:%M:%S')] $1" >> "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
    echo "[SUCCESS] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
    echo "[WARN] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "[ERROR] $1" >> "$LOG_FILE"
    exit 1
}

# 1. 环境检查与准备
check_environment() {
    log "正在检查系统环境..."
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本"
    fi

    # 检查Go环境
    if ! command -v go &> /dev/null; then
        warn "未找到 Go 环境，正在尝试自动安装..."
        if [[ -f /etc/debian_version ]]; then
            apt update -qq && apt install -y golang-go git
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y golang git
        else
            error "无法自动安装 Go，请手动安装后重试"
        fi
    fi
    
    success "环境检查通过"
}

# 2. 编译集成优化版的代码
build_project() {
    log "开始编译 x-ui (已集成自优化模块)..."
    
    cd /clay/11/x-ui_youhua
    
    # 清理旧文件
    go clean
    rm -f x-ui
    
    # 编译 (去除符号表减小体积)
    go build -ldflags="-s -w" -o x-ui main.go
    
    if [ ! -f "x-ui" ]; then
        error "编译失败，请检查 Go 环境或代码"
    fi
    
    success "编译成功"
}

# 4. 安装与服务配置
install_service() {
    log "正在安装服务..."
    
    # 停止旧服务
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    
    # 创建目录
    mkdir -p "$INSTALL_DIR/bin"
    
    # 复制文件
    cp x-ui "$INSTALL_DIR/"
    cp -r bin/* "$INSTALL_DIR/bin/" 2>/dev/null || true
    cp -r web "$INSTALL_DIR/" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/x-ui"
    
    # 生成 Systemd 配置文件
    # 注意：不再需要注入环境变量，因为程序会自动计算并设置
    log "生成 Systemd 配置文件..."
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=x-ui - Intelligent Optimized Panel
Documentation=https://github.com/vaxilu/x-ui
After=network.target network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/x-ui
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

# 进程优先级优化
CPUSchedulingPolicy=fair
CPUSchedulingPriority=50

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    success "服务安装并配置开机自启成功"
}

# 5. 启动与验证
start_and_verify() {
    log "正在启动服务..."
    systemctl start $SERVICE_NAME
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        IP=$(hostname -I | awk '{print $1}')
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}🎉 x-ui 部署完成！${NC}"
        echo -e "${GREEN}═══════════════════════════════════════${NC}"
        echo -e "ℹ️  说明："
        echo -e "  程序已集成智能优化模块，启动时会自动："
        echo -e "  1. 根据内存大小动态调整 GOMEMLIMIT 和 GOGC"
        echo -e "  2. 优化内核网络参数 (TCP缓冲区、队列等)"
        echo -e "  3. 自动开启 BBR (如果内核支持)"
        echo ""
        echo -e "🌐 访问地址: ${BLUE}http://${IP}:54321${NC}"
        echo -e "🔑 默认账号: ${YELLOW}admin${NC}"
        echo -e "🔑 默认密码: ${YELLOW}admin${NC}"
        echo ""
    else
        error "服务启动失败，请检查日志: journalctl -u $SERVICE_NAME -f"
    fi
}

# 主流程
main() {
    echo "🤖 启动 x-ui 部署程序..."
    echo "日志文件: $LOG_FILE"
    
    check_environment
    build_project
    install_service
    start_and_verify
}

main
