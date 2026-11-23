# H3 Studio 一键启动：ComfyUI + WebUI
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\start-all.ps1            # 启动（已起则跳过）
#   powershell -ExecutionPolicy Bypass -File .\start-all.ps1 -Init      # 重新探测并保存配置
#   powershell -ExecutionPolicy Bypass -File .\start-all.ps1 -Restart   # 强制重启两个服务
#   ... -NoBrowser                                                       # 不自动开浏览器

param(
    [switch]$Init,
    [switch]$Restart,
    [switch]$NoBrowser,
    [int]$ComfyPort = 8188,
    [int]$WebPort = 8190
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $repo "startup.json"
$webDir = Join-Path $repo "webui"

function Say($m, $c = "Cyan") { Write-Host $m -ForegroundColor $c }
function Http-OK($url) {
    try { $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2; return $r.StatusCode -eq 200 } catch { return $false }
}
function Wait-Url($url, $seconds, $label) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if (Http-OK $url) { return $true }
        Start-Sleep -Seconds 1
        if ($i % 10 -eq 9) { Say ("   等待 $label … " + ($i + 1) + "s") "DarkGray" }
    }
    return $false
}

# ---------- 探测 ----------
function Find-MainPy {
    $c = @(
        $env:COMFYUI_MAIN,
        "E:\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI\main.py",
        "C:\ComfyUI\main.py",
        "D:\ComfyUI\main.py",
        "$env:LOCALAPPDATA\Programs\@comfyorgcomfyui-electron\resources\ComfyUI\main.py"
    )
    foreach ($p in $c) { if ($p -and (Test-Path $p)) { return $p } }
    foreach ($root in @($env:LOCALAPPDATA, "C:\", "D:\", "E:\")) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Filter "main.py" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -match 'ComfyUI' } | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Find-Python($mainPy) {
    $c = @($env:H3_PYTHON)
    if ($mainPy) {
        $base = Split-Path -Parent $mainPy            # .../ComfyUI
        $c += (Join-Path $base ".venv\Scripts\python.exe")
        $c += (Join-Path (Split-Path -Parent $base) "python_embeded\python.exe")
        $c += (Join-Path (Split-Path -Parent (Split-Path -Parent $base)) "python_embeded\python.exe")
    }
    $c += "C:\ComfyUI\.venv\Scripts\python.exe"
    $c += "C:\ComfyUI\python_embeded\python.exe"
    foreach ($p in $c) { if ($p -and (Test-Path $p)) { return $p } }
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Find-Yaml {
    $dir = Join-Path $env:APPDATA "Comfy Desktop\instance-model-paths"
    if (Test-Path $dir) {
        $f = Get-ChildItem $dir -Filter *.yaml -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    foreach ($d in @("$env:APPDATA\ComfyUI", "$env:LOCALAPPDATA\ComfyUI")) {
        if (Test-Path $d) {
            $f = Get-ChildItem $d -Filter "*model*paths*.yaml" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
    }
    return $null
}

function Find-Shared($mainPy) {
    # 从 main.py 往上找 4 层内名为 ComfyUI-Shared 的目录
    $d = Split-Path -Parent $mainPy
    for ($i = 0; $i -lt 5 -and $d; $i++) {
        $cand = Join-Path $d "ComfyUI-Shared"
        if ((Test-Path (Join-Path $cand "input")) -and (Test-Path (Join-Path $cand "output"))) {
            return @{ input = (Join-Path $cand "input"); output = (Join-Path $cand "output") }
        }
        $d = Split-Path -Parent $d
    }
    return @{ input = ""; output = "" }
}

function Save-Cfg($cfg) {
    $cfg | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    Say "配置已保存: $cfgPath" "DarkGray"
}

# ---------- 载入/探测配置 ----------
$cfg = $null
if (-not $Init -and (Test-Path $cfgPath)) {
    try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
}
if (-not $cfg -or $Init) {
    Say "探测 ComfyUI 安装位置…" "DarkGray"
    $mainPy = Find-MainPy
    if (-not $mainPy) {
        Say "[错误] 找不到 ComfyUI 的 main.py。请设置环境变量 COMFYUI_MAIN 指向它，或手动启动 ComfyUI。" "Red"
        exit 1
    }
    $python = Find-Python $mainPy
    $yaml = Find-Yaml
    $shared = Find-Shared $mainPy
    $cfg = [pscustomobject]@{
        mainPy     = $mainPy
        python     = $python
        yaml       = $yaml
        inputDir   = $shared.input
        outputDir  = $shared.output
        comfyPort  = $ComfyPort
        webPort    = $WebPort
    }
    Say "  main.py : $mainPy"
    Say "  python  : $python"
    Say "  yaml    : $yaml"
    Say "  input   : $($shared.input)"
    Say "  output  : $($shared.output)"
    Save-Cfg $cfg
}

Say ""
Say "== 启动 ComfyUI =="
if ($Restart) {
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'main\.py' } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Say "  已停止旧 ComfyUI (PID $($_.ProcessId))" "DarkGray"
        }
    Start-Sleep -Seconds 2
}

if (Http-OK "http://127.0.0.1:$($cfg.comfyPort)/system_stats") {
    Say "  已在运行（端口 $($cfg.comfyPort)），跳过" "Green"
} else {
    if (-not $cfg.python -or -not (Test-Path $cfg.python)) { Say "[错误] python 不存在: $($cfg.python)" "Red"; exit 1 }
    if (-not (Test-Path $cfg.mainPy)) { Say "[错误] main.py 不存在: $($cfg.mainPy)" "Red"; exit 1 }
    $comfyArgs = "-s `"$($cfg.mainPy)`""
    if ($cfg.yaml -and (Test-Path $cfg.yaml)) { $comfyArgs += " --extra-model-paths-config `"$($cfg.yaml)`"" }
    if ($cfg.inputDir) { $comfyArgs += " --input-directory `"$($cfg.inputDir)`"" }
    if ($cfg.outputDir) { $comfyArgs += " --output-directory `"$($cfg.outputDir)`"" }
    Say "  启动: $($cfg.python) $comfyArgs" "DarkGray"
    Start-Process -FilePath $cfg.python -ArgumentList $comfyArgs -WorkingDirectory (Split-Path -Parent $cfg.mainPy) -WindowStyle Hidden
    Say "  等待就绪（首次约 30–90 秒）…"
    if (-not (Wait-Url "http://127.0.0.1:$($cfg.comfyPort)/system_stats" 240 "ComfyUI")) {
        Say "[错误] ComfyUI 未能启动。手动跑一次看报错：" "Red"
        Say "  `"$($cfg.python)`" $comfyArgs" "Yellow"
        exit 1
    }
    Say "  ComfyUI 已就绪" "Green"
}

# 模型自检：防止起来的是"没有模型路径"的裸实例
try {
    $oi = Invoke-WebRequest "http://127.0.0.1:$($cfg.comfyPort)/object_info/UNETLoader" -UseBasicParsing -TimeoutSec 20
    $j = $oi.Content | ConvertFrom-Json
    $n = ($j.UNETLoader.input.required.unet_name[0] | Measure-Object).Count
    if ($n -eq 0) {
        Say "  [警告] ComfyUI 起来了但看不到任何模型 —— 说明 --extra-model-paths-config 没生效" "Yellow"
        Say "        检查 startup.json 里的 yaml 路径，然后重新跑 -Init" "Yellow"
    } else {
        Say "  模型可见性正常（$n 个主模型）" "Green"
    }
} catch { }

Say ""
Say "== 启动 WebUI =="
if ($Restart -and (Http-OK "http://127.0.0.1:$($cfg.webPort)/api/health")) {
    $conn = Get-NetTCPConnection -LocalPort $cfg.webPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) { Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue; Say "  已停止旧 WebUI" "DarkGray"; Start-Sleep -Seconds 2 }
}
$webOk = Http-OK "http://127.0.0.1:$($cfg.webPort)/api/health"
if (-not $webOk -and (Http-OK "http://127.0.0.1:$($cfg.webPort)/")) { $webOk = $true }
if ($webOk) {
    Say "  已在运行（端口 $($cfg.webPort)），跳过" "Green"
} else {
    $app = Join-Path $webDir "app.py"
    if (-not (Test-Path $app)) { Say "[错误] 找不到 $app" "Red"; exit 1 }
    Start-Process -FilePath $cfg.python -ArgumentList "`"$app`"" -WorkingDirectory $webDir -WindowStyle Hidden
    if (-not (Wait-Url "http://127.0.0.1:$($cfg.webPort)/api/health" 40 "WebUI")) {
        Say "[错误] WebUI 未能启动，手动跑：`"$($cfg.python)`" `"$app`"" "Red"
        exit 1
    }
    Say "  WebUI 已就绪" "Green"
}

$url = "http://127.0.0.1:$($cfg.webPort)"
if (-not $NoBrowser) { Start-Process $url }
Say ""
Say "全部就绪 → $url" "Green"
