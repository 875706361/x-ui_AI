package job

import (
	"runtime"
	"time"
	"x-ui/logger"
	"x-ui/web/service"

	"github.com/robfig/cron/v3"
)

type StatsNotifyJob struct {
	xrayService    *service.XrayService
	settingService *service.SettingService
	inboundService *service.InboundService
	lastStatus     *runtime.MemStats
	lastTime       time.Time
}

func NewStatsNotifyJob(xrayService *service.XrayService, settingService *service.SettingService, inboundService *service.InboundService) *StatsNotifyJob {
	return &StatsNotifyJob{
		xrayService:    xrayService,
		settingService: settingService,
		inboundService: inboundService,
		lastStatus:     &runtime.MemStats{},
		lastTime:       time.Now(),
	}
}

func (j *StatsNotifyJob) Add(c *cron.Cron) error {
	_, err := c.AddFunc("@every 3m", func() {
		j.Run()
	})
	return err
}

func (j *StatsNotifyJob) Run() {
	now := time.Now()
	defer func() {
		j.lastTime = now
	}()

	if now.Sub(j.lastTime) < time.Minute*3 {
		return
	}

	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)

	if j.lastStatus.Mallocs > 0 && (memStats.Mallocs-j.lastStatus.Mallocs) > 1000000 {
		logger.Warning("possible memory leak")
		runtime.GC()
	}

	*j.lastStatus = memStats

	count, err := j.inboundService.DisableInvalidInbounds()
	if err != nil {
		logger.Warning("disable invalid inbounds err:", err)
	} else if count > 0 {
		logger.Debugf("disabled %v inbounds", count)
		if j.xrayService != nil {
			j.xrayService.SetToNeedRestart()
		}
	}
}
