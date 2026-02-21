package service

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/shirou/gopsutil/cpu"
	"github.com/shirou/gopsutil/disk"
	"github.com/shirou/gopsutil/host"
	"github.com/shirou/gopsutil/load"
	"github.com/shirou/gopsutil/mem"
	"github.com/shirou/gopsutil/net"
	"io"
	"io/fs"
	"net/http"
	"os"
	"runtime"
	"time"
	"x-ui/logger"
	"x-ui/util/sys"
	"x-ui/xray"
)

type ProcessState string

const (
	Running ProcessState = "running"
	Stop    ProcessState = "stop"
	Error   ProcessState = "error"
)

type Status struct {
	T   time.Time `json:"-"`
	Cpu float64   `json:"cpu"`
	Mem struct {
		Current uint64 `json:"current"`
		Total   uint64 `json:"total"`
	} `json:"mem"`
	Swap struct {
		Current uint64 `json:"current"`
		Total   uint64 `json:"total"`
	} `json:"swap"`
	Disk struct {
		Current uint64 `json:"current"`
		Total   uint64 `json:"total"`
	} `json:"disk"`
	Xray struct {
		State    ProcessState `json:"state"`
		ErrorMsg string       `json:"errorMsg"`
		Version  string       `json:"version"`
	} `json:"xray"`
	Uptime   uint64    `json:"uptime"`
	Loads    []float64 `json:"loads"`
	TcpCount int       `json:"tcpCount"`
	UdpCount int       `json:"udpCount"`
	NetIO    struct {
		Up   uint64 `json:"up"`
		Down uint64 `json:"down"`
	} `json:"netIO"`
	NetTraffic struct {
		Sent uint64 `json:"sent"`
		Recv uint64 `json:"recv"`
	} `json:"netTraffic"`
}

type Release struct {
	TagName string `json:"tag_name"`
}

type ServerService struct {
	xrayService XrayService
}

func (s *ServerService) GetStatus(lastStatus *Status) *Status {
	now := time.Now()
	status := &Status{
		T: now,
	}

	// CPU - 设置超时，避免卡住
	cpuDone := make(chan []float64, 1)
	go func() {
		percents, err := cpu.Percent(0, false)
		if err == nil {
			cpuDone <- percents
		} else {
			cpuDone <- nil
		}
	}()
	select {
	case percents := <-cpuDone:
		if percents != nil {
			status.Cpu = percents[0]
		}
	case <-time.After(3 * time.Second):
		logger.Warning("get cpu percent timeout")
	}

	// Uptime - 设置超时
	uptimeDone := make(chan uint64, 1)
	go func() {
		upTime, err := host.Uptime()
		if err == nil {
			uptimeDone <- upTime
		} else {
			uptimeDone <- 0
		}
	}()
	select {
	case upTime := <-uptimeDone:
		status.Uptime = upTime
	case <-time.After(2 * time.Second):
		logger.Warning("get uptime timeout")
	}

	// Memory - 设置超时
	memDone := make(chan struct {
		info *mem.VirtualMemoryStat
		err  error
	}, 1)
	go func() {
		memInfo, err := mem.VirtualMemory()
		memDone <- struct {
			info *mem.VirtualMemoryStat
			err  error
		}{memInfo, err}
	}()
	select {
	case result := <-memDone:
		if result.err == nil {
			status.Mem.Current = result.info.Used
			status.Mem.Total = result.info.Total
		} else {
			logger.Warning("get virtual memory failed:", result.err)
		}
	case <-time.After(2 * time.Second):
		logger.Warning("get virtual memory timeout")
	}

	// Swap - 设置超时
	swapDone := make(chan struct {
		info *mem.SwapMemoryStat
		err  error
	}, 1)
	go func() {
		swapInfo, err := mem.SwapMemory()
		swapDone <- struct {
			info *mem.SwapMemoryStat
			err  error
		}{swapInfo, err}
	}()
	select {
	case result := <-swapDone:
		if result.err == nil {
			status.Swap.Current = result.info.Used
			status.Swap.Total = result.info.Total
		} else {
			logger.Warning("get swap memory failed:", result.err)
		}
	case <-time.After(2 * time.Second):
		logger.Warning("get swap memory timeout")
	}

	// Disk - 设置超时
	diskDone := make(chan struct {
		info *disk.UsageStat
		err  error
	}, 1)
	go func() {
		distInfo, err := disk.Usage("/")
		diskDone <- struct {
			info *disk.UsageStat
			err  error
		}{distInfo, err}
	}()
	select {
	case result := <-diskDone:
		if result.err == nil {
			status.Disk.Current = result.info.Used
			status.Disk.Total = result.info.Total
		} else {
			logger.Warning("get dist usage failed:", result.err)
		}
	case <-time.After(2 * time.Second):
		logger.Warning("get dist usage timeout")
	}

	// Load avg - 设置超时
	loadDone := make(chan struct {
		info *load.AvgStat
		err  error
	}, 1)
	go func() {
		avgState, err := load.Avg()
		loadDone <- struct {
			info *load.AvgStat
			err  error
		}{avgState, err}
	}()
	select {
	case result := <-loadDone:
		if result.err == nil {
			status.Loads = []float64{result.info.Load1, result.info.Load5, result.info.Load15}
		} else {
			logger.Warning("get load avg failed:", result.err)
		}
	case <-time.After(2 * time.Second):
		logger.Warning("get load avg timeout")
	}

	// Network stats - 设置超时
	netDone := make(chan struct {
		sent uint64
		recv uint64
		err  error
	}, 1)
	go func() {
		ioStats, err := net.IOCounters(false)
		if err == nil && len(ioStats) > 0 {
			ioStat := ioStats[0]
			netDone <- struct {
				sent uint64
				recv uint64
				err  error
			}{ioStat.BytesSent, ioStat.BytesRecv, nil}
		} else {
			netDone <- struct {
				sent uint64
				recv uint64
				err  error
			}{0, 0, err}
		}
	}()
	select {
	case result := <-netDone:
		if result.err == nil {
			status.NetTraffic.Sent = result.sent
			status.NetTraffic.Recv = result.recv
			if lastStatus != nil {
				duration := now.Sub(lastStatus.T)
				seconds := float64(duration) / float64(time.Second)
				up := uint64(float64(status.NetTraffic.Sent-lastStatus.NetTraffic.Sent) / seconds)
				down := uint64(float64(status.NetTraffic.Recv-lastStatus.NetTraffic.Recv) / seconds)
				status.NetIO.Up = up
				status.NetIO.Down = down
			}
		} else {
			logger.Warning("get io counters failed:", result.err)
		}
	case <-time.After(2 * time.Second):
		logger.Warning("get io counters timeout")
	}

	// TCP/UDP连接统计 - 使用带超时的获取
	tcpDone := make(chan struct {
		count int
		err   error
	}, 1)
	go func() {
		count, err := sys.GetTCPCount()
		tcpDone <- struct {
			count int
			err   error
		}{count, err}
	}()

	udpDone := make(chan struct {
		count int
		err   error
	}, 1)
	go func() {
		count, err := sys.GetUDPCount()
		udpDone <- struct {
			count int
			err   error
		}{count, err}
	}()

	// 等待TCP统计，最多等待2秒
	select {
	case result := <-tcpDone:
		status.TcpCount = result.count
		if result.err != nil {
			logger.Warning("get tcp connections failed:", result.err)
		}
	case <-time.After(2 * time.Second):
		logger.Warning("get tcp connections timeout")
	}

	// 等待UDP统计，最多等待2秒
	select {
	case result := <-udpDone:
		status.UdpCount = result.count
		if result.err != nil {
			logger.Warning("get udp connections failed:", result.err)
		}
	case <-time.After(2 * time.Second):
		logger.Warning("get udp connections timeout")
	}

	if s.xrayService.IsXrayRunning() {
		status.Xray.State = Running
		status.Xray.ErrorMsg = ""
	} else {
		err := s.xrayService.GetXrayErr()
		if err != nil {
			status.Xray.State = Error
		} else {
			status.Xray.State = Stop
		}
		status.Xray.ErrorMsg = s.xrayService.GetXrayResult()
	}
	status.Xray.Version = s.xrayService.GetXrayVersion()

	return status
}

func (s *ServerService) GetXrayVersions() ([]string, error) {
	url := "https://api.github.com/repos/XTLS/Xray-core/releases"
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}

	defer resp.Body.Close()
	buffer := bytes.NewBuffer(make([]byte, 8192))
	buffer.Reset()
	_, err = buffer.ReadFrom(resp.Body)
	if err != nil {
		return nil, err
	}

	releases := make([]Release, 0)
	err = json.Unmarshal(buffer.Bytes(), &releases)
	if err != nil {
		return nil, err
	}
	versions := make([]string, 0, len(releases))
	for _, release := range releases {
		versions = append(versions, release.TagName)
	}
	return versions, nil
}

func (s *ServerService) downloadXRay(version string) (string, error) {
	osName := runtime.GOOS
	arch := runtime.GOARCH

	switch osName {
	case "darwin":
		osName = "macos"
	}

	switch arch {
	case "amd64":
		arch = "64"
	case "arm64":
		arch = "arm64-v8a"
	}

	fileName := fmt.Sprintf("Xray-%s-%s.zip", osName, arch)
	url := fmt.Sprintf("https://github.com/XTLS/Xray-core/releases/download/%s/%s", version, fileName)
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	os.Remove(fileName)
	file, err := os.Create(fileName)
	if err != nil {
		return "", err
	}
	defer file.Close()

	_, err = io.Copy(file, resp.Body)
	if err != nil {
		return "", err
	}

	return fileName, nil
}

func (s *ServerService) UpdateXray(version string) error {
	zipFileName, err := s.downloadXRay(version)
	if err != nil {
		return err
	}

	zipFile, err := os.Open(zipFileName)
	if err != nil {
		return err
	}
	defer func() {
		zipFile.Close()
		os.Remove(zipFileName)
	}()

	stat, err := zipFile.Stat()
	if err != nil {
		return err
	}
	reader, err := zip.NewReader(zipFile, stat.Size())
	if err != nil {
		return err
	}

	s.xrayService.StopXray()
	defer func() {
		err := s.xrayService.RestartXray(true)
		if err != nil {
			logger.Error("start xray failed:", err)
		}
	}()

	copyZipFile := func(zipName string, fileName string) error {
		zipFile, err := reader.Open(zipName)
		if err != nil {
			return err
		}
		os.Remove(fileName)
		file, err := os.OpenFile(fileName, os.O_CREATE|os.O_RDWR|os.O_TRUNC, fs.ModePerm)
		if err != nil {
			return err
		}
		defer file.Close()
		_, err = io.Copy(file, zipFile)
		return err
	}

	err = copyZipFile("xray", xray.GetBinaryPath())
	if err != nil {
		return err
	}
	err = copyZipFile("geosite.dat", xray.GetGeositePath())
	if err != nil {
		return err
	}
	err = copyZipFile("geoip.dat", xray.GetGeoipPath())
	if err != nil {
		return err
	}

	return nil

}
