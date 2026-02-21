// +build linux

package sys

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

// 连接统计缓存，避免频繁读取 /proc 文件
var (
	lastTCPCount     int
	lastUDPCount     int
	lastCacheTime    time.Time
	cacheMutex       sync.RWMutex
	cacheDuration    = 5 * time.Second // 缓存5秒
	maxFileSizeLimit = 1024 * 1024     // 1MB限制，超过就不读完整文件
)

// 读取文件行数，带文件大小检查
func getLinesNum(filename string) (int, error) {
	file, err := os.Open(filename)
	if err != nil {
		return 0, err
	}
	defer file.Close()

	// 先检查文件大小，如果太大就不完整读取
	stat, err := file.Stat()
	if err == nil && stat.Size() > int64(maxFileSizeLimit) {
		// 文件太大，返回0但不报错，避免日志刷屏
		return 0, nil
	}

	sum := 0
	buf := make([]byte, 4096) // 减小缓冲区以优化内存使用
	for {
		n, err := file.Read(buf)

		var buffPosition int
		for {
			i := bytes.IndexByte(buf[buffPosition:], '\n')
			if i < 0 || n == buffPosition {
				break
			}
			buffPosition += i + 1
			sum++
		}

		if err == io.EOF {
			return sum, nil
		} else if err != nil {
			return sum, err
		}
	}
}

// 使用缓存的连接统计，避免频繁读取
func getCachedCount(getCount func() (int, error), lastCount *int, lastTime *time.Time, mutex *sync.RWMutex) (int, error) {
	now := time.Now()

	mutex.RLock()
	if now.Sub(*lastTime) < cacheDuration {
		count := *lastCount
		mutex.RUnlock()
		return count, nil
	}
	mutex.RUnlock()

	count, err := getCount()

	mutex.Lock()
	*lastCount = count
	*lastTime = now
	mutex.Unlock()

	return count, err
}

func GetTCPCount() (int, error) {
	return getCachedCount(func() (int, error) {
		root := HostProc()

		tcp4, err := getLinesNum(fmt.Sprintf("%v/net/tcp", root))
		if err != nil {
			return 0, nil
		}
		tcp6, err := getLinesNum(fmt.Sprintf("%v/net/tcp6", root))
		if err != nil {
			return tcp4, nil
		}

		return tcp4 + tcp6, nil
	}, &lastTCPCount, &lastCacheTime, &cacheMutex)
}

func GetUDPCount() (int, error) {
	return getCachedCount(func() (int, error) {
		root := HostProc()

		udp4, err := getLinesNum(fmt.Sprintf("%v/net/udp", root))
		if err != nil {
			return 0, nil
		}
		udp6, err := getLinesNum(fmt.Sprintf("%v/net/udp6", root))
		if err != nil {
			return udp4, nil
		}

		return udp4 + udp6, nil
	}, &lastUDPCount, &lastCacheTime, &cacheMutex)
}