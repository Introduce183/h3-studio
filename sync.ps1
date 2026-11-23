# 提示：耗时与可跑时长取决于本机显存，先看 docs/本机适配指南.md
# H3 Studio 同步脚本
# 用法（在仓库目录里跑）：
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1            # 检查 + 更新 + 重启
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check      # 只看有没有更新
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -NoRestart  # 更新但不重启
#
# 作用：查版本差异 → 拉最新代码 → 同步工作流模板到 DSH 插件目录 → 重启 WebUI

param(
    [int]$Port = 8190,
    [switch]$Check,
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repo

function Say($m, $c = "Cyan") { Write-Host $m -ForegroundColor $c }

Say "== H3 Studio 同步 =="
Say "仓库: $repo"

if (-not (Test-Path (Join-Path $repo ".git"))) {
    Say "[错误] 这个目录不是 git 仓库。请先 git clone。" "Red"
    exit 1
}

# ---------- 1. 版本对比 ----------
$localVer = if (Test-Path (Join-Path $repo "VERSION")) { (Get-Content (Join-Path $repo "VERSION") -Raw).Trim() } else { "?" }
$headShort = (git rev-parse --short HEAD).Trim()
Say "本地版本: v$localVer ($headShort)"

Say "查询远端…" "DarkGray"
git fetch --quiet origin
if ($LASTEXITCODE -ne 0) {
    Say "[错误] git fetch 失败：检查网络或仓库地址。" "Red"
    exit 1
}

$behind = [int]((git rev-list --count HEAD..origin/main).Trim())
$remoteShort = (git rev-parse --short origin/main).Trim()
$remoteVer = "?"
try {
    $remoteVer = ((git show origin/main:VERSION) -replace "`r", "").Trim()
} catch { }
$latestMsg = (git log --oneline -1 origin/main).Trim()

if ($behind -eq 0) {
    Say "✅ 已是最新：v$localVer ($headShort)" "Green"
    if ($Check) { exit 0 }
} else {
    Say "⬆ 落后远端 $behind 个提交（远端 v$remoteVer / $remoteShort）" "Yellow"
    Say "   最新提交: $latestMsg" "Yellow"
    Say "   待更新文件:" "Yellow"
    git diff --name-only HEAD..origin/main | ForEach-Object { "     - $_" }
    if ($Check) {
        Say ""
        Say "（-Check 模式，未做任何改动。去掉 -Check 即执行更新）" "DarkGray"
        exit 0
    }
}

# ---------- 2. 拉代码 ----------
$oldHead = $headShort
if ($behind -gt 0) {
    git pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Say "[错误] git pull 失败：本地有改动或分叉。先 git status 看看，或 git stash。" "Red"
        exit 1
    }
    $newShort = (git rev-parse --short HEAD).Trim()
    $newVer = if (Test-Path (Join-Path $repo "VERSION")) { (Get-Content (Join-Path $repo "VERSION") -Raw).Trim() } else { "?" }
    Say "已更新: $oldHead → $newShort  (v$newVer)" "Green"
    Say "本次改动文件:" "Green"
    git diff --name-only "$oldHead..HEAD" | ForEach-Object { "   - $_" }
} else {
    Say "代码无需更新，继续检查模板…" "DarkGray"
}

# ---------- 3. 同步工作流模板 ----------
$wfSrc = Join-Path $repo "workflows"
$wfDst = Join-Path $env:USERPROFILE ".dsh-comfyui-workbench\workflows"
if (Test-Path $wfSrc) {
    New-Item -ItemType Directory -Force $wfDst | Out-Null
    $changed = @()
    Get-ChildItem $wfSrc -File | ForEach-Object {
        $dst = Join-Path $wfDst $_.Name
        $need = $true
        if (Test-Path $dst) { $need = (Get-FileHash $_.FullName).Hash -ne (Get-FileHash $dst).Hash }
        if ($need) { Copy-Item $_.FullName $dst -Force; $changed += $_.Name }
    }
    if ($changed.Count -eq 0) {
        Say "模板已是最新（无需覆盖）" "Green"
    } else {
        Say "模板已同步: $($changed.Count) 个文件 → $wfDst" "Green"
        $changed | ForEach-Object { "   ~ $_" }
        Say "⚠ 模板有变化，必须去 DSH 里重载插件，否则预检会误报缺节点：" "Yellow"
        Say "   plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=false" "Yellow"
        Say "   plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=true" "Yellow"
    }
} else {
    Say "[警告] 仓库里没有 workflows/ 目录" "Yellow"
}

# ---------- 4. 重启 WebUI ----------
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
