package controller

import (
	"x-ui/web/service"
	"x-ui/web/session"

	"github.com/gin-gonic/gin"
)

type XrayController struct {
	BaseController
	xrayService    service.XrayService
	inboundService service.InboundService
	settingService service.SettingService
}

func NewXrayController(g *gin.RouterGroup) *XrayController {
	a := &XrayController{}
	a.initRouter(g)
	return a
}

func (a *XrayController) initRouter(g *gin.RouterGroup) {
	g = g.Group("/xray")
	g.Use(func(c *gin.Context) {
		if !session.IsLogin(c) {
			pureJsonMsg(c, false, "login expired")
			c.Abort()
			return
		}
		c.Next()
	})

	g.POST("/restart", a.Restart)
	g.POST("/generateRealityKeyPair", a.GenerateRealityKeyPair)
}

func (a *XrayController) Restart(c *gin.Context) {
	err := a.xrayService.RestartXray(true)
	jsonMsg(c, "restart xray", err)
}

func (a *XrayController) GenerateRealityKeyPair(c *gin.Context) {
	privateKey, publicKey, err := a.xrayService.GenerateRealityKeyPair()
	if err != nil {
		jsonMsg(c, "generate reality key", err)
		return
	}
	jsonObj(c, map[string]string{
		"privateKey": privateKey,
		"publicKey":  publicKey,
	}, nil)
}
