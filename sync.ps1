# H3 Studio 同步脚本
# 用法（在仓库目录里跑）：
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -NoRestart
# 作用：拉最新代码 → 同步工作流模板到 DSH 插件目录 → 重启 WebUI

param(
    [int]$Port = 8190,
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repo

function Say($m, $c = "Cyan") { Write-Host $m -ForegroundColor $c }

Say "== H3 Studio 同步 =="
Say "仓库: $repo"

# ---------- 1. 拉代码 ----------
if (-not (Test-Path (Join-Path $repo ".git"))) {
    Say "[错误] 这个目录不是 git 仓库。请先 git clone。" "Red"
    exit 1
}
Say "拉取远端…" "DarkGray"
git pull --ff-only
if ($LASTEXITCODE -ne 0) {
    Say "[错误] git pull 失败：本地有改动或分叉。先 git status 看看，或 git stash。" "Red"
    exit 1
}
$head = git log --oneline -1
Say "当前版本: $head" "Green"

# ---------- 2. 同步工作流模板 ----------
$wfSrc = Join-Path $repo "workflows"
$wfDst = Join-Path $env:USERPROFILE ".dsh-comfyui-workbench\workflows"
if (Test-Path $wfSrc) {
    New-Item -ItemType Directory -Force $wfDst | Out-Null
    $copied = 0
    Get-ChildItem $wfSrc -File | ForEach-Object {
        $dst = Join-Path $wfDst $_.Name
        $need = $true
        if (Test-Path $dst) {
            $same = (Get-FileHash $_.FullName).Hash -eq (Get-FileHash $dst).Hash
            $need = -not $same
        }
        if ($need) { Copy-Item $_.FullName $dst -Force; $copied++ }
    }
    Say "模板已同步到: $wfDst（更新 $copied 个文件）" "Green"
    if ($copied -gt 0) {
        Say "⚠ 模板有变化，需要在 DSH 里重载插件，否则预检会误报缺节点：" "Yellow"
        Say "   plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=false" "Yellow"
        Say "   plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=true" "Yellow"
    }
} else {
    Say "[警告] 仓库里没有 workflows/ 目录" "Yellow"
}

# ---------- 3. 重启 WebUI ----------
if ($NoRestart) {
    Say "已跳过重启（-NoRestart）" "Yellow"
    exit 0
}

$python = $env:H3_PYTHON
try {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($conn.OwningProcess)" -ErrorAction SilentlyContinue
        if ($proc -and $proc.CommandLine -match '^\s*"?([^"]+\.exe)') { $python = $Matches[1] }
        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        Say "已停止旧的 WebUI (PID $($conn.OwningProcess))" "DarkGray"
        Start-Sleep -Seconds 2
    }
} catch { }

if (-not $python) {
    foreach ($p in @(
        "$env:LOCALAPPDATA\Programs\@comfyorgcomfyui-electron\resources\ComfyUI\.venv\Scripts\python.exe",
        "$env:LOCALAPPDATA\Programs\@comfyorgcomfyui-electron\resources\python_embeded\python.exe",
        "C:\ComfyUI\.venv\Scripts\python.exe",
        "C:\ComfyUI\python_embeded\python.exe"
    )) { if (Test-Path $p) { $python = $p; break } }
}
if (-not $python) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source }
}
if (-not $python) {
    Say "[错误] 找不到 Python，请设置 H3_PYTHON 或手动启动 webui\app.py" "Red"
    exit 1
}

$app = Join-Path $repo "webui\app.py"
Start-Process -FilePath $python -ArgumentList ('"' + $app + '"') -WorkingDirectory (Join-Path $repo "webui") -WindowStyle Hidden
Say "已启动，等待就绪…" "DarkGray"

$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:$Port/api/health" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { Say ("健康检查通过: " + $r.Content) "Green"; $ok = $true; break }
    } catch { }
}
if (-not $ok) {
    Say "[警告] 没起来，手动跑一次 $app 看报错" "Yellow"
    exit 1
}

try {
    $o = (Invoke-WebRequest "http://127.0.0.1:$Port/api/outputs" -UseBasicParsing -TimeoutSec 20).Content | ConvertFrom-Json
    Say ("作品库: {0} 条，下一个编号 #{1}" -f $o.items.Count, $o.next) "Green"
} catch { }

Say ""
Say "同步完成。浏览器 Ctrl+F5 强刷。" "Green"
