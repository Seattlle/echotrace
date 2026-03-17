//go:build windows
// +build windows

package unlock

import (
	"fmt"
	"syscall"
	"unsafe"
)

var (
	rstrtmgr                = syscall.NewLazyDLL("rstrtmgr.dll")
	procRmStartSession      = rstrtmgr.NewProc("RmStartSession")
	procRmEndSession        = rstrtmgr.NewProc("RmEndSession")
	procRmRegisterResources = rstrtmgr.NewProc("RmRegisterResources")
	procRmShutdown          = rstrtmgr.NewProc("RmShutdown")
)

const (
	CCH_RM_SESSION_KEY  = 32
	CCH_RM_MAX_APP_NAME = 255
	CCH_RM_MAX_SVC_NAME = 63

	// RmShutdown 标志
	RmForceShutdown          = 0x1
	RmShutdownOnlyRegistered = 0x10
)

// ForceUnlockFile 强制解锁文件（关闭所有占用该文件的句柄）
func ForceUnlockFile(filePath string) error {
	// 步骤1：启动 Restart Manager 会话
	var sessionHandle uint32
	sessionKey := make([]uint16, CCH_RM_SESSION_KEY+1)

	ret, _, _ := procRmStartSession.Call(
		uintptr(unsafe.Pointer(&sessionHandle)),
		uintptr(0),
		uintptr(unsafe.Pointer(&sessionKey[0])),
	)

	if ret != 0 {
		return fmt.Errorf("RmStartSession failed with error code: %d", ret)
	}

	// 确保会话结束时关闭
	defer procRmEndSession.Call(uintptr(sessionHandle))

	// 步骤2：注册文件资源
	filePathUTF16, err := syscall.UTF16PtrFromString(filePath)
	if err != nil {
		return fmt.Errorf("failed to convert file path to UTF16: %w", err)
	}

	filePathArray := [1]*uint16{filePathUTF16}

	ret, _, _ = procRmRegisterResources.Call(
		uintptr(sessionHandle),
		uintptr(1), // nFiles
		uintptr(unsafe.Pointer(&filePathArray[0])),
		uintptr(0), // nApplications
		uintptr(0), // rgApplications
		uintptr(0), // nServices
		uintptr(0), // rgsServiceNames
	)

	if ret != 0 {
		return fmt.Errorf("RmRegisterResources failed with error code: %d", ret)
	}

	// 步骤3：强制关闭占用文件的进程/句柄
	ret, _, _ = procRmShutdown.Call(
		uintptr(sessionHandle),
		uintptr(RmForceShutdown|RmShutdownOnlyRegistered),
		uintptr(0), // fnStatus callback
	)

	if ret != 0 {
		// 错误代码 6（ERROR_INVALID_HANDLE）可能意味着没有进程占用文件
		if ret == 6 {
			return nil // 没有进程占用，视为成功
		}
		return fmt.Errorf("RmShutdown failed with error code: %d", ret)
	}

	return nil
}
