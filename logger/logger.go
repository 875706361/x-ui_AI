package logger

import (
	"fmt"
	"github.com/op/go-logging"
	"os"
	"sync"
	"time"
)

var logger *logging.Logger

// 警告消息抑制，避免日志刷屏
var (
	lastWarningMsg   string
	lastWarningTime  time.Time
	warningMutex     sync.RWMutex
	warningCooldown  = 30 * time.Second // 同一警告30秒内只记录一次
)

func init() {
	InitLogger(logging.INFO)
}

func InitLogger(level logging.Level) {
	format := logging.MustStringFormatter(
		`%{time:2006/01/02 15:04:05} %{level} - %{message}`,
	)
	newLogger := logging.MustGetLogger("x-ui")
	backend := logging.NewLogBackend(os.Stderr, "", 0)
	backendFormatter := logging.NewBackendFormatter(backend, format)
	backendLeveled := logging.AddModuleLevel(backendFormatter)
	backendLeveled.SetLevel(level, "")
	newLogger.SetBackend(backendLeveled)

	logger = newLogger
}

// 抑制频繁的警告消息
func shouldLogWarning(msg string) bool {
	now := time.Now()

	warningMutex.RLock()
	if msg == lastWarningMsg && now.Sub(lastWarningTime) < warningCooldown {
		warningMutex.RUnlock()
		return false
	}
	warningMutex.RUnlock()

	warningMutex.Lock()
	lastWarningMsg = msg
	lastWarningTime = now
	warningMutex.Unlock()

	return true
}

func Debug(args ...interface{}) {
	logger.Debug(args...)
}

func Debugf(format string, args ...interface{}) {
	logger.Debugf(format, args...)
}

func Info(args ...interface{}) {
	logger.Info(args...)
}

func Infof(format string, args ...interface{}) {
	logger.Infof(format, args...)
}

func Warning(args ...interface{}) {
	msg := fmt.Sprint(args...)
	if shouldLogWarning(msg) {
		logger.Warning(args...)
	}
}

func Warningf(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	if shouldLogWarning(msg) {
		logger.Warningf(format, args...)
	}
}

func Error(args ...interface{}) {
	logger.Error(args...)
}

func Errorf(format string, args ...interface{}) {
	logger.Errorf(format, args...)
}