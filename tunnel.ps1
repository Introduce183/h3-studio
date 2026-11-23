# H3 WebUI 反向隧道（带自动重连）
# 通常由 start-all.ps1 调用；也可单独运行：
#   powershell -ExecutionPolicy Bypass -File .\tunnel.ps1 -RemoteHost 1.2.3.4 -User admin -RemotePort 18490

param(
    [string]$RemoteHost = "",
    [string]$User = "",
    [int]$SshPort = 22,
    [int]$LocalPort = 8190,
    [int]$RemotePort = 18490,
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519"
)

$ErrorActionPreference = "Continue"
if (-not $RemoteHost -or -not $User) {
    Write-Host "[错误] 需要 -RemoteHost 与 -User" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $KeyPath)) {
    Write-Host "[错误] 找不到密钥 $KeyPath" -ForegroundColor Red
    exit 1
}

$attempt = 0
while ($true) {
    $attempt++
    & ssh -N -T `
        -o BatchMode=yes `
        -o ExitOnForwardFailure=yes `
        -o ServerAliveInterval=20 `
        -o ServerAliveCountMax=3 `
        -o StrictHostKeyChecking=accept-new `
        -o ConnectTimeout=15 `
        -i $KeyPath `
        -p $SshPort `
        -R "0.0.0.0:${RemotePort}:127.0.0.1:${LocalPort}" `
        "$User@$RemoteHost"

    Start-Sleep -Seconds 5
}
