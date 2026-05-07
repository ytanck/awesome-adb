# MyFirstScript.ps1
# 这是一个注释

# 1. 定义变量
$serviceName = "WinRM"
$logFile = "D:\jb工具\service_status.txt"
$date = Get-Date

# 2. 写入输出信息
Write-Host "脚本开始执行于 $date" -ForegroundColor Green
Write-Host "正在检查服务：$serviceName"...

# 3. 获取服务状态（核心逻辑）
$service = Get-Service -Name $serviceName

# 4. 判断并操作
if ($service.Status -eq 'Running') {
    Write-Host "服务 $serviceName 正在运行。" -ForegroundColor Green
    # 可以在这里做更多事情，比如停止它
    # Stop-Service -Name $serviceName
} else {
    Write-Host "服务 $serviceName 未运行。状态为: $($service.Status)" -ForegroundColor Yellow
    # 可以在这里启动它
    # Start-Service -Name $serviceName
}

# 5. 将结果记录到文件
"检查时间: $date | 服务名: $serviceName | 状态: $($service.Status)" | Out-File -FilePath $logFile -Append

# 6. 脚本结束
Write-Host "检查完成，结果已记录到 $logFile" -ForegroundColor Green