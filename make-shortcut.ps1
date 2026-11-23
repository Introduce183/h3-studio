# 在桌面创建「H3 Studio」一键启动快捷方式
# 用法：powershell -ExecutionPolicy Bypass -File .\make-shortcut.ps1
#       powershell -ExecutionPolicy Bypass -File .\make-shortcut.ps1 -Name "H3 启动"

param(
    [string]$Name = "H3 Studio",
    [switch]$AlsoStartMenu
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $repo "start-all.ps1"

if (-not (Test-Path $script)) {
    Write-Host "[错误] 找不到 start-all.ps1（应与本脚本同目录）" -ForegroundColor Red
    exit 1
}

$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop "$Name.lnk"

$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($lnkPath)
$lnk.TargetPath       = "powershell.exe"
$lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$script`""
$lnk.WorkingDirectory = $repo
$lnk.WindowStyle      = 7                      # 7 = 最小化，不弹黑窗
$lnk.Description      = "启动 ComfyUI + H3 Studio WebUI"
$lnk.IconLocation     = "shell32.dll,137"      # 一个播放/启动样式的系统图标
$lnk.Save()

Write-Host "已创建桌面快捷方式: $lnkPath" -ForegroundColor Green

if ($AlsoStartMenu) {
    $sm = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$Name.lnk"
    Copy-Item $lnkPath $sm -Force
    Write-Host "已复制到开始菜单: $sm" -ForegroundColor Green
}

Write-Host ""
Write-Host "双击它就会：启动 ComfyUI（含模型路径）→ 等就绪 → 启动 WebUI → 打开浏览器" -ForegroundColor DarkGray
Write-Host "首次建议先跑一次探测：powershell -ExecutionPolicy Bypass -File `"$script`" -Init" -ForegroundColor DarkGray
