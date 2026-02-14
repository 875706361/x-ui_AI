package optimize

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"x-ui/logger"
)

// Status 存储优化状态
type Status struct {
	TotalMemory int64 `json:"total_memory"`
	MemLimit    int64 `json:"mem_limit"`
	GCPercent   int   `json:"gc_percent"`
	BBR         bool  `json:"bbr_enabled"`
	KernelOpt   bool  `json:"kernel_optimized"`
}

var currentStatus Status

// Init 执行所有系统优化
func Init() {
	logger.Info("Starting system self-optimization...")

	// 1. 优化 Go 运行时参数 (GC 和 内存限制)
	optimizeRuntime()

	// 2. 优化系统内核参数 (网络栈)
	optimizeKernel()

	// 3. 尝试开启 BBR
	enableBBR()

	logger.Info("System self-optimization completed.")
}

// GetStatus 返回当前的优化状态
func GetStatus() Status {
	return currentStatus
}

// optimizeRuntime 根据物理内存自动调整 Go 运行时参数
func optimizeRuntime() {
	totalMem := getTotalMemory()
	if totalMem == 0 {
		logger.Warning("Failed to detect total memory, skipping runtime optimization.")
		return
	}
	currentStatus.TotalMemory = totalMem

	logger.Infof("Detected total memory: %d MB", totalMem/1024/1024)

	// 动态设置 GOMEMLIMIT (设置为总内存的 75%)
	memLimit := int64(float64(totalMem) * 0.75)
	debug.SetMemoryLimit(memLimit)
	currentStatus.MemLimit = memLimit
	logger.Infof("Set GOMEMLIMIT to %d MB", memLimit/1024/1024)

	// 动态设置 GOGC
	// 内存 < 1GB: GOGC=50 (更积极回收)
	// 内存 < 4GB: GOGC=75
	// 内存 >= 4GB: GOGC=100 (默认)
	var gcPercent int
	if totalMem < 1024*1024*1024 {
		gcPercent = 50
	} else if totalMem < 4*1024*1024*1024 {
		gcPercent = 75
	} else {
		gcPercent = 100
	}
	debug.SetGCPercent(gcPercent)
	currentStatus.GCPercent = gcPercent
	logger.Infof("Set GOGC to %d", gcPercent)
}

// optimizeKernel 优化 Linux 内核网络参数
func optimizeKernel() {
	if runtime.GOOS != "linux" {
		return
	}

	totalMem := getTotalMemory()
	
	// 根据内存大小动态计算 TCP 缓冲区
	var tcpMem string
	if totalMem < 1024*1024*1024 {
		// < 1GB 内存: 4MB max buffer
		tcpMem = "4096 87380 4194304"
	} else {
		// >= 1GB 内存: 128MB max buffer
		tcpMem = "4096 65536 134217728"
	}

	params := map[string]string{
		"net.core.default_qdisc":        "fq",
		"net.core.rmem_max":             "134217728",
		"net.core.wmem_max":             "134217728",
		"net.ipv4.tcp_rmem":             tcpMem,
		"net.ipv4.tcp_wmem":             tcpMem,
		"net.ipv4.tcp_notsent_lowat":    "16384",
		"net.ipv4.tcp_no_metrics_save":  "1",
		"net.core.netdev_max_backlog":   "5000",
		"net.ipv4.tcp_fastopen":         "3",
		"net.ipv4.tcp_slow_start_after_idle": "0",
	}

	logger.Info("Applying kernel network optimizations...")
	successCount := 0
	for key, value := range params {
		if err := setSysctl(key, value); err != nil {
			// 某些参数可能在某些环境下不可用，仅记录调试信息
			logger.Debugf("Failed to set %s: %v", key, err)
		} else {
			successCount++
		}
	}
	
	if successCount > 0 {
		currentStatus.KernelOpt = true
	}
}

// enableBBR 尝试开启 BBR 拥塞控制算法
func enableBBR() {
	if runtime.GOOS != "linux" {
		return
	}

	// 检查内核版本是否支持 BBR (需要 >= 4.9)
	kernelVer := getKernelVersion()
	if kernelVer < 4.9 {
		logger.Warningf("Kernel version %.1f is too old for BBR (requires >= 4.9), using cubic instead.", kernelVer)
		setSysctl("net.ipv4.tcp_congestion_control", "cubic")
		currentStatus.BBR = false
		return
	}

	// 开启 BBR
	if err := setSysctl("net.ipv4.tcp_congestion_control", "bbr"); err != nil {
		logger.Warning("Failed to enable BBR, fallback to cubic.")
		setSysctl("net.ipv4.tcp_congestion_control", "cubic")
		currentStatus.BBR = false
	} else {
		logger.Info("BBR congestion control enabled successfully.")
		currentStatus.BBR = true
	}
}

// 辅助函数：获取总物理内存 (字节)
func getTotalMemory() int64 {
	file, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "MemTotal:") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				kb, err := strconv.ParseInt(parts[1], 10, 64)
				if err == nil {
					return kb * 1024
				}
			}
		}
	}
	return 0
}

// 辅助函数：设置 sysctl 参数
func setSysctl(key, value string) error {
	// 尝试直接写入 /proc/sys/...
	path := "/proc/sys/" + strings.ReplaceAll(key, ".", "/")
	if err := os.WriteFile(path, []byte(value), 0644); err == nil {
		return nil
	}

	// 如果写入失败，尝试使用 sysctl 命令
	cmd := exec.Command("sysctl", "-w", fmt.Sprintf("%s=%s", key, value))
	return cmd.Run()
}

// 辅助函数：获取内核版本
func getKernelVersion() float64 {
	out, err := exec.Command("uname", "-r").Output()
	if err != nil {
		return 0
	}
	
	verStr := strings.TrimSpace(string(out))
	// 移除可能存在的非数字后缀，如 "-generic"
	verStr = strings.Split(verStr, "-")[0]
	parts := strings.Split(verStr, ".")
	if len(parts) >= 2 {
		major, _ := strconv.Atoi(parts[0])
		minor, _ := strconv.Atoi(parts[1])
		return float64(major) + float64(minor)/10.0
	}
	return 0
}
