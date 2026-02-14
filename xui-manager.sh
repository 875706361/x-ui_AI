#!/bin/bash

# x-ui 管理脚本
# 用于管理优化版 x-ui 服务的启停和状态查看

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SERVICE_NAME="x-ui"
INSTALL_DIR="/usr/local/x-ui"

# 显示帮助信息
show_help() {
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}  x-ui 优化版管理工具${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令："
    echo "  start   - 启动 x-ui 服务"
    echo "  stop    - 停止 x-ui 服务"
    echo "  restart - 重启 x-ui 服务"
    echo "  status  - 查看服务状态"
    echo "  logs    - 查看实时日志"
    echo "  info    - 显示服务信息"
    echo "  update  - 更新到最新优化版"
    echo "  backup  - 备份配置文件"
    echo "  restore - 恢复配置文件"
    echo "  help    - 显示此帮助信息"
    echo ""
}

# 检查服务状态
check_service() {
    if systemctl is-active --quiet $SERVICE_NAME; then
        return 0
    else
        return 1
    fi
}

# 启动服务
start_service() {
    echo -e "${YELLOW}🚀 正在启动 x-ui 服务...${NC}"
    
    if check_service; then
        echo -e "${GREEN}✅ x-ui 服务已经在运行${NC}"
        return 0
    fi
    
    systemctl start $SERVICE_NAME
    sleep 2
    
    if check_service; then
        echo -e "${GREEN}✅ x-ui 服务启动成功${NC}"
        show_info
    else
        echo -e "${RED}❌ x-ui 服务启动失败${NC}"
        echo "请查看日志获取详细信息"
        show_logs
        exit 1
    fi
}

# 停止服务
stop_service() {
    echo -e "${YELLOW}🛑 正在停止 x-ui 服务...${NC}"
    
    if ! check_service; then
        echo -e "${GREEN}✅ x-ui 服务已经停止${NC}"
        return 0
    fi
    
    systemctl stop $SERVICE_NAME
    sleep 2
    
    if ! check_service; then
        echo -e "${GREEN}✅ x-ui 服务停止成功${NC}"
    else
        echo -e "${RED}❌ x-ui 服务停止失败${NC}"
        exit 1
    fi
}

# 重启服务
restart_service() {
    echo -e "${YELLOW}🔄 正在重启 x-ui 服务...${NC}"
    
    systemctl restart $SERVICE_NAME
    sleep 3
    
    if check_service; then
        echo -e "${GREEN}✅ x-ui 服务重启成功${NC}"
        show_info
    else
        echo -e "${RED}❌ x-ui 服务重启失败${NC}"
        exit 1
    fi
}

# 显示服务状态
show_status() {
    echo -e "${BLUE}📊 x-ui 服务状态${NC}"
    echo "═══════════════════════════════════════"
    
    if check_service; then
        echo -e "状态: ${GREEN}运行中${NC}"
        
        # 获取进程信息
        local pid=$(systemctl show -p MainPID $SERVICE_NAME | cut -d= -f2)
        if [[ "$pid" != "0" ]]; then
            echo "进程ID: $pid"
            
            # 获取内存使用
            local mem=$(ps -p $pid -o rss= 2>/dev/null | awk '{print $1/1024 " MB"}')
            if [[ -n "$mem" ]]; then
                echo "内存使用: $mem"
            fi
            
            # 获取CPU使用
            local cpu=$(ps -p $pid -o %cpu= 2>/dev/null)
            if [[ -n "$cpu" ]]; then
                echo "CPU使用: ${cpu}%"
            fi
        fi
        
        # 获取监听端口
        local ports=$(ss -tlnp | grep x-ui | awk '{print $4}' | cut -d: -f2 | sort -u)
        if [[ -n "$ports" ]]; then
            echo "监听端口: $ports"
        fi
        
        # 获取运行时间
        local uptime=$(systemctl show -p ActiveEnterTimestamp $SERVICE_NAME | cut -d= -f2)
        if [[ -n "$uptime" ]]; then
            echo "运行时间: $uptime"
        fi
        
    else
        echo -e "状态: ${RED}已停止${NC}"
    fi
    
    echo ""
    systemctl status $SERVICE_NAME --no-pager -l
}

# 显示实时日志
show_logs() {
    echo -e "${BLUE}📋 正在显示 x-ui 实时日志 (按 Ctrl+C 退出)${NC}"
    journalctl -u $SERVICE_NAME -f
}

# 显示服务信息
show_info() {
    echo -e "${BLUE}ℹ️  x-ui 服务信息${NC}"
    echo "═══════════════════════════════════════"
    
    # 获取IP地址
    local ip=$(hostname -I | awk '{print $1}')
    echo "访问地址: http://${ip}:54321"
    echo "配置文件: $INSTALL_DIR/x-ui.db"
    echo "日志文件: /var/log/x-ui/"
    echo ""
    
    # 显示优化特性
    echo -e "${BLUE}🔧 优化特性：${NC}"
    echo "  ✓ CPU轮询频率降低 80%"
    echo "  ✓ 系统资源缓存机制"
    echo "  ✓ Goroutine优雅关闭"
    echo "  ✓ 网络性能优化"
    echo "  ✓ 开机自动启动"
    echo ""
    
    show_status
}

# 更新服务
update_service() {
    echo -e "${YELLOW}🔄 正在更新 x-ui 到最新优化版...${NC}"
    
    # 备份当前配置
    local backup_dir="/tmp/x-ui-backup-$(date +%Y%m%d-%H%M%S)"
    if [ -d "$INSTALL_DIR" ]; then
        echo "📦 备份配置文件到 $backup_dir"
        mkdir -p "$backup_dir"
        cp -r "$INSTALL_DIR"/* "$backup_dir/" 2>/dev/null || true
    fi
    
    # 停止服务
    stop_service
    
    # 重新编译优化版
    cd /clay/11/x-ui_youhua
    go build -ldflags="-s -w" -o x-ui main.go
    
    # 安装新版本
    cp x-ui /usr/local/x-ui/
    chmod +x /usr/local/x-ui/x-ui
    
    # 启动服务
    start_service
    
    echo -e "${GREEN}✅ 更新完成${NC}"
}

# 备份配置
backup_config() {
    local backup_dir="/tmp/x-ui-backup-$(date +%Y%m%d-%H%M%S)"
    echo -e "${YELLOW}📦 正在备份配置文件到 $backup_dir${NC}"
    
    mkdir -p "$backup_dir"
    
    if [ -d "$INSTALL_DIR" ]; then
        cp -r "$INSTALL_DIR"/* "$backup_dir/" 2>/dev/null || true
        echo -e "${GREEN}✅ 备份完成：$backup_dir${NC}"
    else
        echo -e "${RED}❌ 未找到配置文件${NC}"
        exit 1
    fi
}

# 恢复配置
restore_config() {
    echo -e "${YELLOW}📋 可用的备份文件：${NC}"
    ls -la /tmp/x-ui-backup-* 2>/dev/null || {
        echo -e "${RED}❌ 未找到备份文件${NC}"
        exit 1
    }
    
    echo ""
    read -p "请输入要恢复的备份目录路径: " backup_dir
    
    if [ ! -d "$backup_dir" ]; then
        echo -e "${RED}❌ 备份目录不存在${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}🔄 正在恢复配置文件...${NC}"
    
    # 停止服务
    stop_service
    
    # 恢复配置
    cp -r "$backup_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
    
    # 启动服务
    start_service
    
    echo -e "${GREEN}✅ 配置恢复完成${NC}"
}

# 主函数
main() {
    case "$1" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        info)
            show_info
            ;;
        update)
            update_service
            ;;
        backup)
            backup_config
            ;;
        restore)
            restore_config
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ -z "$1" ]]; then
                show_info
            else
                echo -e "${RED}❌ 未知命令: $1${NC}"
                show_help
                exit 1
            fi
            ;;
    esac
}

# 运行主函数
main "$@"