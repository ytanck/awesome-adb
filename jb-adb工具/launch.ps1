# go-sentinel 启动脚本
# 此脚本用于启动 go-sentinel 主进程及其监控进程

param (
    [string]$AndroidId = "5b3c291fae31637e",
    [string]$WsUrl = "wss://device-cluster-dev.gyjxwh.com/websocket/sentinel",
    [string]$ExecPath = "C:\Users\Administrator\Desktop\go-sentinel.exe", 
    [int]$MonitorInterval = 10,
    [switch]$Hidden = $true
)

# 获取当前脚本所在目录
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$monitorScript = Join-Path -Path $scriptDir -ChildPath "monitor.ps1"

# 创建临时文件目录（使用系统临时目录）
$tempFileDir = [System.IO.Path]::GetTempPath()
$logDir = Split-Path -Parent $ExecPath

# 确保AndroidId不包含非法字符，替换为安全的文件名
$safeAndroidId = $AndroidId -replace '[\\\/\:\*\?\"\<\>\|]', '_'

# 检查并关闭所有相关进程
function Stop-AllRelatedProcesses {
    param($androidId, $safeAndroidId)
    
    Write-Host "正在检查并关闭所有相关进程..." -ForegroundColor Cyan
    
    # 1. 通过临时文件查找并关闭进程
    $processInfoFile = Join-Path -Path $tempFileDir -ChildPath "go-sentinel-$safeAndroidId-info.txt"
    if (Test-Path $processInfoFile) {
        try {
            # 读取主进程ID
            $fileContent = Get-Content $processInfoFile -ErrorAction SilentlyContinue
            if ($fileContent) {
                $processIdLine = $fileContent | Where-Object { $_ -like "ProcessId: *" } | Select-Object -First 1
                if ($processIdLine) {
                    $processId = ($processIdLine -replace "ProcessId: ", "").Trim()
                    try {
                        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                        if ($process) {
                            Write-Host "正在终止旧进程(PID:$processId)..." -ForegroundColor Yellow
                            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 1
                            if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
                                taskkill /F /PID $processId /T 2>$null
                            }
                        }
                    } catch { }
                }
                
                # 读取监控进程ID
                $monitorIdLine = $fileContent | Where-Object { $_ -like "MonitorProcessId: *" } | Select-Object -First 1
                if ($monitorIdLine) {
                    $monitorId = ($monitorIdLine -replace "MonitorProcessId: ", "").Trim()
                    try {
                        $monitor = Get-Process -Id $monitorId -ErrorAction SilentlyContinue
                        if ($monitor) {
                            Write-Host "正在终止旧监控进程(PID:$monitorId)..." -ForegroundColor Yellow
                            Stop-Process -Id $monitorId -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 1
                            if (Get-Process -Id $monitorId -ErrorAction SilentlyContinue) {
                                taskkill /F /PID $monitorId /T 2>$null
                            }
                        }
                    } catch { }
                }
                
                # 读取启动进程ID
                $launchIdLine = $fileContent | Where-Object { $_ -like "LaunchPowershellId: *" } | Select-Object -First 1
                if ($launchIdLine) {
                    $launchId = ($launchIdLine -replace "LaunchPowershellId: ", "").Trim()
                    try {
                        $launchProcess = Get-Process -Id $launchId -ErrorAction SilentlyContinue
                        if ($launchProcess) {
                            Write-Host "正在终止旧启动进程(PID:$launchId)..." -ForegroundColor Yellow
                            Stop-Process -Id $launchId -Force -ErrorAction SilentlyContinue
                        }
                    } catch { }
                }
            }
        } catch {
            Write-Host "读取临时文件时出错: $_" -ForegroundColor Red
        }
    }
    
    # 2. 查找所有go-sentinel进程并关闭
    Get-Process | Where-Object { $_.ProcessName -eq "go-sentinel" } | ForEach-Object {
        try {
            $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId = '$($_.Id)'").CommandLine
            if ($cmdLine -match "-android_id\s+`"?$androidId`"?") {
                Write-Host "终止使用相同设备ID的进程(PID:$($_.Id))..." -ForegroundColor Yellow
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                if (Get-Process -Id $_.Id -ErrorAction SilentlyContinue) {
                    taskkill /F /PID $_.Id /T 2>$null
                }
            }
        } catch { }
    }
    
    # 3. 查找所有可能的监控PowerShell进程
    Get-Process | Where-Object { $_.ProcessName -eq "powershell" } | ForEach-Object {
        try {
            $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId = '$($_.Id)'").CommandLine
            if ($cmdLine -match "monitor\.ps1.*$androidId") {
                Write-Host "终止相关监控PowerShell进程(PID:$($_.Id))..." -ForegroundColor Yellow
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    
    # 4. 清理旧的日志文件
    $outputLog = Join-Path -Path $logDir -ChildPath "go-sentinel-$safeAndroidId-output.log"
    $errorLog = Join-Path -Path $logDir -ChildPath "go-sentinel-$safeAndroidId-error.log"
    $monitorLog = Join-Path -Path $logDir -ChildPath "go-sentinel-$safeAndroidId.log"
    
    if (Test-Path $outputLog) { Remove-Item $outputLog -Force -ErrorAction SilentlyContinue }
    if (Test-Path $errorLog) { Remove-Item $errorLog -Force -ErrorAction SilentlyContinue }
    if (Test-Path $monitorLog) { Remove-Item $monitorLog -Force -ErrorAction SilentlyContinue }
    
    # 5. 删除临时文件
    if (Test-Path $processInfoFile) { Remove-Item $processInfoFile -Force -ErrorAction SilentlyContinue }
}

# 启动监控脚本
function Start-Monitor {
    # 构建参数
    $argsList = @(
        "-ExecutionPolicy", "Bypass",
        "-NoProfile",
        "-File", "`"$monitorScript`"",
        "-AndroidId", "`"$AndroidId`"",
        "-WsUrl", "`"$WsUrl`"",
        "-ExecPath", "`"$ExecPath`"",
        "-MonitorInterval", "$MonitorInterval",
        "-TempFileDir", "`"$tempFileDir`"",
        "-LogDir", "`"$logDir`""
    )
    
    # 启动方式
    $windowStyle = if ($Hidden) { "Hidden" } else { "Normal" }
    
    # 启动监控脚本
    Write-Host "正在启动监控进程..." -ForegroundColor Green
    Start-Process powershell.exe -ArgumentList $argsList -WindowStyle $windowStyle
    
    # 等待进程启动
    $processInfoFile = Join-Path -Path $tempFileDir -ChildPath "go-sentinel-$safeAndroidId-info.txt"
    $maxWaitTime = 10 # 最多等待10秒
    $waitCount = 0
    
    Start-Sleep -Seconds 1
    
    $processId = $null
    $monitorId = $null
    
    while ($waitCount -lt $maxWaitTime) {
        if (Test-Path $processInfoFile) {
            try {
                $fileContent = Get-Content $processInfoFile -ErrorAction SilentlyContinue
                if ($fileContent) {
                    $processIdLine = $fileContent | Where-Object { $_ -like "ProcessId: *" } | Select-Object -First 1
                    if ($processIdLine) {
                        $processId = ($processIdLine -replace "ProcessId: ", "").Trim()
                    }
                    
                    $monitorIdLine = $fileContent | Where-Object { $_ -like "MonitorProcessId: *" } | Select-Object -First 1
                    if ($monitorIdLine) {
                        $monitorId = ($monitorIdLine -replace "MonitorProcessId: ", "").Trim()
                    }
                    
                    # 记录启动进程ID
                    if (-not ($fileContent | Where-Object { $_ -like "LaunchPowershellId: *" })) {
                        try {
                            "LaunchPowershellId: $PID" | Out-File $processInfoFile -Append -ErrorAction SilentlyContinue
                        } catch { }
                    }
                    
                    if ($processId -and $monitorId) { break }
                }
            } catch { }
        }
        
        Start-Sleep -Seconds 1
        $waitCount++
    }
    
    # 显示进程信息
    if ($processId) {
        Write-Host "go-sentinel进程已启动，PID: $processId" -ForegroundColor Green
    } else {
        Write-Host "无法获取go-sentinel进程PID，请检查临时文件" -ForegroundColor Yellow
    }
    
    if ($monitorId) {
        Write-Host "监控进程已启动，PID: $monitorId" -ForegroundColor Green
    } else {
        Write-Host "无法获取监控进程PID，请检查临时文件" -ForegroundColor Yellow
    }
    
    return @{
        ProcessId = $processId
        MonitorId = $monitorId
    }
}

# 主程序开始
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "                go-sentinel 启动工具" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "当前PowerShell进程PID: $PID" -ForegroundColor Cyan
Write-Host "使用设备ID: $AndroidId" -ForegroundColor Cyan
Write-Host "连接地址: $WsUrl" -ForegroundColor Cyan
Write-Host "可执行文件: $ExecPath" -ForegroundColor Cyan
Write-Host "监控间隔: $MonitorInterval 秒" -ForegroundColor Cyan
Write-Host "日志输出目录: $logDir" -ForegroundColor Cyan

# 首先检查并终止所有相关进程
Stop-AllRelatedProcesses -androidId $AndroidId -safeAndroidId $safeAndroidId

# 检查monitor.ps1文件是否存在，不存在则创建
if (-not (Test-Path $monitorScript)) {
    Write-Host "监控脚本不存在，将创建..." -ForegroundColor Yellow
    # 如果direct-monitor.ps1不存在，则直接写入新的monitor.ps1
    if (-not (Test-Path "$scriptDir\direct-monitor.ps1")) {
        Write-Host "创建新的监控脚本..." -ForegroundColor Yellow
    } else {
        Copy-Item -Path "$scriptDir\direct-monitor.ps1" -Destination $monitorScript
    }
}

# 启动监控
$processInfo = Start-Monitor

# 显示启动摘要
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "启动摘要:" -ForegroundColor Cyan
Write-Host "设备ID: $AndroidId" -ForegroundColor Cyan
Write-Host "主进程PID: $($processInfo.ProcessId)" -ForegroundColor Green
Write-Host "监控进程PID: $($processInfo.MonitorId)" -ForegroundColor Green
Write-Host "启动PowerShell进程PID: $PID" -ForegroundColor Green
Write-Host "临时文件: $(Join-Path -Path $tempFileDir -ChildPath "go-sentinel-$safeAndroidId-info.txt")" -ForegroundColor Cyan
Write-Host "程序日志: $(Join-Path -Path $logDir -ChildPath "go-sentinel-$safeAndroidId-output.log")" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "提示：" -ForegroundColor Yellow
Write-Host "- 要以隐藏窗口模式运行，请使用 -Hidden 参数" -ForegroundColor Yellow
Write-Host "- 要指定设备ID，请使用 -AndroidId 参数" -ForegroundColor Yellow
Write-Host ""

# 等待用户按键
Write-Host "按任意键继续..." -ForegroundColor Magenta
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")