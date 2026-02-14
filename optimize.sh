#!/bin/bash

# 优化脚本 - x-ui 启动前自动执行
# 需要 root 权限

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
fi

echo "Starting system optimization..."

# 1. 优化内核参数
echo "Optimizing kernel parameters..."

# 获取总内存 (KB)
total_mem=$(grep MemTotal /proc/meminfo | awk "{print $2}")
# 转换为字节
total_mem_bytes=$((total_mem * 1024))

# 根据内存大小设置 TCP 缓冲区
if [[ $total_mem_bytes -lt 1073741824 ]]; then
    # < 1GB 内存
    tcp_mem="4096 87380 4194304"
else
    # >= 1GB 内存
    tcp_mem="4096 65536 134217728"
fi

# 设置 sysctl 参数
sysctl_params=(
    "net.core.default_qdisc=fq"
    "net.core.rmem_max=134217728"
    "net.core.wmem_max=134217728"
    "net.ipv4.tcp_rmem=$tcp_mem"
    "net.ipv4.tcp_wmem=$tcp_mem"
    "net.ipv4.tcp_notsent_lowat=16384"
    "net.ipv4.tcp_no_metrics_save=1"
    "net.core.netdev_max_backlog=5000"
    "net.ipv4.tcp_fastopen=3"
    "net.ipv4.tcp_slow_start_after_idle=0"
)

for param in "${sysctl_params[@]}"; do
    sysctl -w "$param" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Failed to set $param"
    else
        echo "Set $param"
    fi
done

# 2. 尝试开启 BBR
echo "Checking BBR support..."
kernel_version=$(uname -r | cut -d- -f1)
major_version=$(echo $kernel_version | cut -d. -f1)
minor_version=$(echo $kernel_version | cut -d. -f2)

if [[ $major_version -ge 5 ]] || ([[ $major_version -eq 4 ]] && [[ $minor_version -ge 9 ]]); then
    echo "Kernel version $kernel_version supports BBR."
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "BBR enabled successfully."
    else
        echo "Failed to enable BBR, falling back to cubic."
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
    fi
else
    echo "Kernel version $kernel_version is too old for BBR (requires >= 4.9)."
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
fi

echo "System optimization completed."
