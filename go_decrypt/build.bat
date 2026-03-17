@echo off
REM Windows 编译脚本 - 编译 Go 代码为 DLL

echo Building Go decrypt library for Windows...

REM 设置输出目录
set OUTPUT_DIR=..\windows\runner

REM 创建输出目录
if not exist %OUTPUT_DIR% mkdir %OUTPUT_DIR%

REM 编译 64 位 DLL
echo Compiling 64-bit DLL...
set CGO_ENABLED=1
set GOOS=windows
set GOARCH=amd64
set CGO_LDFLAGS=-static -static-libgcc -static-libstdc++
go build -buildmode=c-shared -ldflags="-s -w" -o %OUTPUT_DIR%\go_decrypt.dll main.go

if %ERRORLEVEL% EQU 0 (
    echo Build successful! DLL created at %OUTPUT_DIR%\go_decrypt.dll
) else (
    echo Build failed with error code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo Done!

