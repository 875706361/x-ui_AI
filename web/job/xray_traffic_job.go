package job

import (
	"context"
	"x-ui/logger"
	"x-ui/web/service"
)

type XrayTrafficJob struct {
	ctx            context.Context
	xrayService    *service.XrayService
	inboundService *service.InboundService
}

func NewXrayTrafficJob(ctx context.Context) *XrayTrafficJob {
	return &XrayTrafficJob{
		ctx: ctx,
	}
}

func (j *XrayTrafficJob) Run() {
	if j.xrayService == nil || !j.xrayService.IsXrayRunning() {
		return
	}
	traffics, err := j.xrayService.GetRawTraffic()
	if err != nil {
		logger.Warning("get xray traffic failed:", err)
		return
	}
	if traffics == nil {
		return
	}
	err = j.inboundService.AddTraffic(traffics)
	if err != nil {
		logger.Warning("add traffic failed:", err)
	}
}
