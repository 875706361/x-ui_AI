#!/bin/bash

# x-ui 资源监控脚本
# 当 CPU 或内存使用过高时自动重启服务

# 配置
CPU_THRESHOLD=80        # CPU 使用率阈值 (%)
MEMORY_THRESHOLD=80     # 内存使用率阈值 (%)
CHECK_INTERVAL=60       # 检查间隔 (秒)
LOG_FILE="/var/log/x-ui-monitor.log"
SERVICE_NAME="x-ui"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查 CPU 使用率
check_cpu() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    echo "$cpu_usage"
}

# 检查内存使用率
check_memory() {
    local mem_usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
    echo "$mem_usage"
}

# 重启服务
restart_service() {
    log "资源使用异常，正在重启服务..."
    systemctl restart "$SERVICE_NAME"
    sleep 5

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "服务重启成功"
    else
        log "服务重启失败！"
    fi
}

# 主监控循环
log "监控脚本启动 (CPU 阈值: ${CPU_THRESHOLD}%, 内存阈值: ${MEMORY_THRESHOLD}%)"

while true; do
    cpu=$(check_cpu)
    mem=$(check_memory)

    log "CPU: ${cpu}%, 内存: ${mem}%"

    # 检查是否超过阈值
    cpu_check=$(echo "$cpu > $CPU_THRESHOLD" | bc 2>/dev/null || echo "0")
    if [ "$cpu_check" = "1" ]; then
        log "警告: CPU 使用率过高 (${cpu}%)"
        restart_service
    fi

    mem_check=$(echo "$mem > $MEMORY_THRESHOLD" | bc 2>/dev/null || echo "0")
    if [ "$mem_check" = "1" ]; then
        log "警告: 内存使用率过高 (${mem}%)"
        # 内存高不一定重启，先记录日志
    fi

    sleep "$CHECK_INTERVAL"
done