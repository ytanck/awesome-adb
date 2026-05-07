# go-sentinel 监控脚本
# 此脚本用于监控和自动重启go-sentinel进程

param (
    [Parameter(Mandatory=$true)]
    [string]$AndroidId,
    
    [Parameter(Mandatory=$true)]
    [string]$WsUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$ExecPath,
    
    [int]$MonitorInterval = 10, # 默认监控检查间隔（秒）
    
    [string]$TempFileDir = $null, # 临时文件目录，默认使用系统临时目录
    
    [string]$LogDir = $null # 日志目录，默认使用go-sentinel.exe所在目录
)

# 如果没有指定临时文件目录，则使用系统临时目录
if (-not $TempFileDir) {
    $TempFileDir = [System.IO.Path]::GetTempPath()
}

# 如果没有指定日志目录，则使用go-sentinel.exe所在目录
if (-not $LogDir) {
    $LogDir = Split-Path -Parent $ExecPath
}

# 获取当前PowerShell进程ID
$monitorProcessId = $PID
$host.UI.RawUI.WindowTitle = "Go-Sentinel 监控 - $AndroidId"

# 确保AndroidId不包含非法字符，替换为安全的文件名
$safeAndroidId = $AndroidId -replace '[\\\/\:\*\?\"\<\>\|]', '_'

# 保存进程信息的临时文件
$processInfoFile = Join-Path -Path $TempFileDir -ChildPath "go-sentinel-$safeAndroidId-info.txt"

# 确保可执行文件存在
if (-not (Test-Path $ExecPath)) {
    Write-Error "错误: go-sentinel可执行文件不存在: $ExecPath"
    exit 1
}

# 写入临时文件的安全函数
function Write-InfoFile {
    param(
        [string]$Content,
        [switch]$Force
    )
    
    try {
        if ($Force) {
            $Content | Out-File -FilePath $processInfoFile -Force -ErrorAction Stop
        } else {
            $Content | Out-File -FilePath $processInfoFile -Append -ErrorAction Stop
        }
        return $true
    } catch {
        # 写入失败时，尝试使用备用路径
        try {
            $backupFile = Join-Path -Path $env:TEMP -ChildPath "go-sentinel-info.txt"
            if ($Force) {
                $Content | Out-File -FilePath $backupFile -Force -ErrorAction Stop
            } else {
                $Content | Out-File -FilePath $backupFile -Append -ErrorAction Stop
            }
            # 更新进程信息文件路径
            $script:processInfoFile = $backupFile
            return $true
        } catch {
            return $false
        }
    }
}

# 停止已存在的go-sentinel进程
function Stop-ExistingProcess {
    # 查找所有go-sentinel进程
    $existingProcesses = Get-Process | Where-Object { $_.ProcessName -eq "go-sentinel" } -ErrorAction SilentlyContinue
    
    foreach ($proc in $existingProcesses) {
        try {
            # 通过命令行参数查找使用相同androidId的进程
            $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId = '$($proc.Id)'").CommandLine
            if ($cmdLine -match "-android_id\s+`"?$AndroidId`"?") {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                
                # 确认进程已终止
                if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
                    taskkill /F /PID $proc.Id /T 2>$null
                    Start-Sleep -Seconds 1
                }
            }
        } catch { }
    }
}

# 启动go-sentinel进程
function Start-GoSentinel {
    try {
        # 构建命令行参数
        $argString = "-android_id `"$AndroidId`" -ws_url `"$WsUrl`""
        
        # 确保输出日志文件名安全
        $outputLogFile = Join-Path -Path $LogDir -ChildPath "go-sentinel-$safeAndroidId-output.log"
        
        # 启动进程并重定向输出到日志文件
        $process = Start-Process -FilePath $ExecPath `
            -ArgumentList $argString `
            -WindowStyle Hidden `
            -PassThru `
            -RedirectStandardOutput $outputLogFile `
            -ErrorAction Stop
            
        if ($process) {
            return $process
        } else {
            return $null
        }
    } catch {
        return $null
    }
}

# 检查进程是否在运行
function Test-ProcessRunning {
    param($processId)
    
    if (-not $processId) { return $false }
    
    try {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        return ($process -ne $null)
    } catch {
        return $false
    }
}

# 开始监控
function Start-Monitor {
    # 将当前监控进程信息写入临时文件
    $infoWritten = Write-InfoFile -Content "AndroidId: $AndroidId" -Force
    if ($infoWritten) {
        Write-InfoFile -Content "MonitorProcessId: $monitorProcessId"
        Write-InfoFile -Content "StartTime: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
    
    # 停止已存在的进程
    Stop-ExistingProcess
    
    # 首次启动进程
    $mainProcess = Start-GoSentinel
    if (-not $mainProcess) {
        exit 1
    }
    
    $processId = $mainProcess.Id
    
    # 将主进程ID记录到临时文件
    if ($infoWritten) {
        Write-InfoFile -Content "ProcessId: $processId"
    }
    
    # 监控循环
    while ($true) {
        try {
            $isRunning = Test-ProcessRunning -processId $processId
            
            if (-not $isRunning) {
                # 重新启动进程
                $mainProcess = Start-GoSentinel
                if ($mainProcess) {
                    $processId = $mainProcess.Id
                    
                    # 更新临时文件中的进程ID
                    if ($infoWritten -and (Test-Path $processInfoFile)) {
                        try {
                            $fileContent = Get-Content $processInfoFile -ErrorAction Stop
                            $newContent = $fileContent | Where-Object { -not $_.StartsWith("ProcessId:") }
                            $newContent | Out-File $processInfoFile -Force -ErrorAction Stop
                            "ProcessId: $processId" | Out-File $processInfoFile -Append -ErrorAction Stop
                            "RestartTime: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $processInfoFile -Append -ErrorAction Stop
                        } catch {
                            # 如果更新失败，不影响主要功能
                        }
                    }
                }
            }
            
            # 暂停指定的间隔时间
            Start-Sleep -Seconds $MonitorInterval
            
        } catch {
            Start-Sleep -Seconds $MonitorInterval
        }
    }
}

# 开始监控
Start-Monitor