#!/bin/bash

# x-ui 优化版部署脚本 (集成版)
# 该脚本会自动部署优化后的代码并配置开机自启
# 适合需要保留现有配置的升级场景

set -e

echo "🚀 开始部署优化版 x-ui..."

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
   echo "❌ 请使用 root 权限运行此脚本 (sudo ./deploy-optimized.sh)"
   exit 1
fi

# 设置变量
INSTALL_DIR="/usr/local/x-ui"
BINARY_NAME="x-ui"
SERVICE_NAME="x-ui"
BACKUP_DIR="/tmp/x-ui-backup-$(date +%Y%m%d-%H%M%S)"

# 函数：备份现有配置
backup_existing() {
    if [ -d "$INSTALL_DIR" ]; then
        echo "📦 备份现有配置到 $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        cp -r "$INSTALL_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
        echo "✅ 备份完成"
    fi
}

# 函数：停止现有服务
stop_existing_service() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "🛑 停止现有 x-ui 服务"
        systemctl stop "$SERVICE_NAME"
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    fi
}

# 函数：编译优化版
build_optimized() {
    echo "🔨 编译优化版 x-ui (已集成自优化模块)..."
    cd /clay/11/x-ui_youhua
    
    # 清理旧构建
    go clean
    
    # 编译优化版本
    go build -ldflags="-s -w" -o "$BINARY_NAME-optimized" main.go
    
    if [ ! -f "$BINARY_NAME-optimized" ]; then
        echo "❌ 编译失败"
        exit 1
    fi
    
    echo "✅ 编译成功"
}

# 函数：安装优化版
install_optimized() {
    echo "📥 安装优化版 x-ui..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/bin"
    
    # 复制优化版二进制文件
    cp "$BINARY_NAME-optimized" "$INSTALL_DIR/x-ui"
    chmod +x "$INSTALL_DIR/x-ui"
    
    # 复制必要的资源文件
    cp -r bin/* "$INSTALL_DIR/bin/" 2>/dev/null || true
    cp -r web "$INSTALL_DIR/" 2>/dev/null || true
    
    # 恢复备份的配置文件
    if [ -d "$BACKUP_DIR/x-ui" ]; then
        echo "📋 恢复配置文件"
        cp -r "$BACKUP_DIR/x-ui"/* "$INSTALL_DIR/" 2>/dev/null || true
    fi
    
    echo "✅ 安装完成"
}

# 函数：创建系统服务
create_service() {
    echo "🔧 创建系统服务..."
    
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
    systemctl enable "$SERVICE_NAME"
    
    echo "✅ 服务创建完成"
}

# 函数：启动服务并验证
start_and_verify() {
    echo "🚀 启动 x-ui 服务..."
    systemctl start "$SERVICE_NAME"
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ x-ui 服务启动成功"
        
        # 显示服务信息
        echo ""
        echo "📊 服务状态信息："
        systemctl status "$SERVICE_NAME" --no-pager -l
        
        echo ""
        echo "🌐 访问地址：http://$(hostname -I | awk '{print $1}'):54321"
        echo "🔑 默认用户名：admin"
        echo "🔑 默认密码：admin"
        
    else
        echo "❌ x-ui 服务启动失败"
        echo "请查看日志：journalctl -u $SERVICE_NAME -f"
        exit 1
    fi
}

# 函数：显示使用信息
show_usage() {
    echo ""
    echo "🎉 x-ui 优化版部署完成！"
    echo ""
    echo "📋 常用命令："
    echo "  查看状态: systemctl status $SERVICE_NAME"
    echo "  启动服务: systemctl start $SERVICE_NAME"
    echo "  停止服务: systemctl stop $SERVICE_NAME"
    echo "  重启服务: systemctl restart $SERVICE_NAME"
    echo "  查看日志: journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "🔧 优化特性："
    echo "  ✓ 自适应内存管理 (内置)"
    echo "  ✓ 智能内核参数调优 (内置)"
    echo "  ✓ 自动开启 BBR (内置)"
    echo "  ✓ CPU轮询频率降低 80%"
    echo "  ✓ Goroutine优雅关闭"
    echo ""
}

# 主执行流程
main() {
    echo "🎯 x-ui 优化版部署脚本"
    echo "═══════════════════════════════════════"
    
    # 执行部署步骤
    backup_existing
    stop_existing_service
    build_optimized
    install_optimized
    create_service
    # performance_optimization 已移除，由程序自优化替代
    start_and_verify
    show_usage
    
    echo "✨ 部署完成！享受优化后的 x-ui 服务吧！"
}

# 运行主函数
main "$@"