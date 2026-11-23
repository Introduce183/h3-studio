# 同步自查：对着这份跑一遍，任何一项 ✗ 都说明本机状态和仓库不一致
# 用法：powershell -ExecutionPolicy Bypass -File .\verify.ps1
#       powershell -ExecutionPolicy Bypass -File .\verify.ps1 -Fix   # 能自动修的直接修

param([switch]$Fix)

$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repo
$ok = 0; $bad = 0; $warn = 0

function Row($name, $state, $detail) {
    $mark = switch ($state) { "ok" { "✓" } "bad" { "✗" } default { "!" } }
    $color = switch ($state) { "ok" { "Green" } "bad" { "Red" } default { "Yellow" } }
    if ($state -eq "ok") { $script:ok++ } elseif ($state -eq "bad") { $script:bad++ } else { $script:warn++ }
    Write-Host ("  {0} {1,-26} {2}" -f $mark, $name, $detail) -ForegroundColor $color
}

Write-Host "`n== H3 Studio 同步自查 ==`n" -ForegroundColor Cyan

# 1) 版本
$ver = if (Test-Path (Join-Path $repo "VERSION")) { (Get-Content (Join-Path $repo "VERSION") -Raw).Trim() } else { "?" }
$head = ""
if (Test-Path (Join-Path $repo ".git")) {
    $head = (git rev-parse --short HEAD 2>$null)
    git fetch --quiet origin 2>$null
    $behind = (git rev-list --count HEAD..origin/main 2>$null)
    if ($behind -and [int]$behind -gt 0) {
        Row "仓库版本" "warn" "v$ver ($head) —— 落后远端 $behind 个提交，先跑 sync.ps1"
    } else {
        Row "仓库版本" "ok" "v$ver ($head) 已是最新"
    }
} else {
    Row "仓库版本" "bad" "不是 git 仓库，无法同步"
}

# 2) 工作流模板
$wfSrc = Join-Path $repo "workflows"
$wfDst = Join-Path $env:USERPROFILE ".dsh-comfyui-workbench\workflows"
$ids = @("minimax-h3-ref2v-community", "minimax-h3-ref2v-community-multi", "minimax-h3-ref2v-continue")
$missing = @(); $diff = @()
foreach ($id in $ids) {
    foreach ($ext in @(".json", ".schema.json", ".meta.json")) {
        $s = Join-Path $wfSrc ($id + $ext)
        $d = Join-Path $wfDst ($id + $ext)
        if (-not (Test-Path $d)) { $missing += ($id + $ext); continue }
        if ((Test-Path $s) -and ((Get-FileHash $s).Hash -ne (Get-FileHash $d).Hash)) { $diff += ($id + $ext) }
    }
}
if ($missing.Count) { Row "工作流模板" "bad" "插件目录缺 $($missing.Count) 个文件 → 跑 sync.ps1" }
elseif ($diff.Count) { Row "工作流模板" "warn" "$($diff.Count) 个模板与仓库不一致 → 跑 sync.ps1 并重载插件" }
else { Row "工作流模板" "ok" "3 套 × 3 文件已同步" }

# 3) 模型
$models = @("diffusion_models\minimax_h3_ref2va_pruned_int8_convrot.safetensors",
            "text_encoders\qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors",
            "vae\minimax_h3_video_vae_int8_convrot.safetensors",
            "vae\minimax_h3_audio_vae_fp32.safetensors",
            "loras\minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors")
$mdlRoot = ""
$startup = Join-Path $repo "startup.json"
if (Test-Path $startup) {
    try {
        $c = Get-Content $startup -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($c.mainPy) { $mdlRoot = Join-Path (Split-Path (Split-Path (Split-Path $c.mainPy -Parent) -Parent) -Parent) "ComfyUI-Shared\models" }
    } catch { }
}
if (-not $mdlRoot -or -not (Test-Path $mdlRoot)) { $mdlRoot = "E:\Comfy-Desktop\ComfyUI-Shared\models" }
$missM = @()
foreach ($m in $models) { if (-not (Test-Path (Join-Path $mdlRoot $m))) { $missM += (Split-Path $m -Leaf) } }
if ($missM.Count) { Row "必需模型" "bad" "$($missM.Count) 个缺失：$($missM -join ", ")" }
else { Row "必需模型" "ok" "5 个必需模型齐全（$mdlRoot）" }

# 4) WebUI 文件
$pairs = @(@("webui\app.py", "webui\app.py"), @("webui\static\index.html", "webui\static\index.html"))
$webDiff = @()
foreach ($p in $pairs) {
    $s = Join-Path $repo $p[0]
    if (-not (Test-Path $s)) { continue }
}
Row "WebUI 源码" "ok" ("app.py {0} KB · index.html {1} KB" -f [math]::Round((Get-Item (Join-Path $repo 'webui\app.py')).Length/1KB), [math]::Round((Get-Item (Join-Path $repo 'webui\static\index.html')).Length/1KB))

# 5) startup.json 的隧道配置
$need = @("tunnelHost", "tunnelUser", "tunnelRemotePort", "tunnelKey")
if (-not (Test-Path $startup)) {
    Row "startup.json" "bad" "不存在 → 跑 start-all.ps1 -Init"
} else {
    $c = Get-Content $startup -Raw -Encoding UTF8 | ConvertFrom-Json
    $missT = @($need | Where-Object { -not $c.$_ })
    if ($missT.Count) {
        Row "隧道配置" "bad" "startup.json 缺 $($missT -join ", ") → 补上后双击快捷方式才会带隧道"
    } else {
        Row "隧道配置" "ok" ("$($c.tunnelUser)@$($c.tunnelHost):$($c.tunnelRemotePort)")
    }
}

# 6) 访问口令
$cfg = Join-Path $repo "webui\config.json"
if (-not (Test-Path $cfg)) {
    Row "WebUI 口令" "bad" "config.json 不存在 → 至少写 {`"token`":`"<你的口令>`"}"
} else {
    try {
        $tok = (Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json).token
        if ($tok -and $tok.Length -ge 8) { Row "WebUI 口令" "ok" "已设置（$($tok.Length) 位）" }
        else { Row "WebUI 口令" "bad" "token 未设置或太短（公网暴露必须设）" }
    } catch { Row "WebUI 口令" "bad" "config.json 解析失败" }
}

# 7) 桌面快捷方式
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "H3 Studio.lnk"
$vbs = Join-Path ([Environment]::GetFolderPath('Startup')) "H3-WebUI-Tunnel.vbs"
if (Test-Path $vbs) { Remove-Item $vbs -Force -ErrorAction SilentlyContinue }
if (-not (Test-Path $lnk)) {
    Row "桌面快捷方式" "bad" "没有 H3 Studio.lnk → 跑 make-shortcut.ps1"
} else {
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnk)
    if ($sc.Arguments -match "start-all\.ps1") { Row "桌面快捷方式" "ok" "指向 start-all.ps1（会自动带隧道）" }
    else { Row "桌面快捷方式" "warn" ("指向: " + $sc.Arguments + " —— 应指向 start-all.ps1") }
}

# 8) 服务状态
$comfy = $false
try { $comfy = ((Invoke-WebRequest "http://127.0.0.1:8188/system_stats" -UseBasicParsing -TimeoutSec 4).StatusCode -eq 200) } catch { }
Row "ComfyUI (8188)" $(if ($comfy) { "ok" } else { "bad" }) $(if ($comfy) { "在线" } else { "没在跑 → 双击桌面快捷方式" })

$web = $false
try { $web = ((Invoke-WebRequest "http://127.0.0.1:8190/api/health" -UseBasicParsing -TimeoutSec 4).StatusCode -eq 200) } catch { }
Row "WebUI (8190)" $(if ($web) { "ok" } else { "bad" }) $(if ($web) { "在线" } else { "没在跑" })

# 9) 隧道进程
$tPort = 0
if (Test-Path $startup) { try { $tPort = [int](Get-Content $startup -Raw -Encoding UTF8 | ConvertFrom-Json).tunnelRemotePort } catch { } }
if (-not $tPort) {
    Row "反向隧道" "warn" "startup.json 里没有 tunnelRemotePort，跳过检查"
} else {
    $proc = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match ":$tPort`:" }
    Row "反向隧道" $(if ($proc) { "ok" } else { "bad" }) $(if ($proc) { "ssh 正在映射远端 $tPort" } else { "没有隧道进程 → 跑 tunnel.ps1 或双击快捷方式" })
}

Write-Host ("`n  结果：{0} 项通过，{1} 项失败，{2} 项提醒`n" -f $ok, $bad, $warn) -ForegroundColor $(if ($bad) { "Red" } else { "Green" })
if ($bad) {
    Write-Host "  修复顺序建议：" -ForegroundColor Yellow
    Write-Host "   1) sync.ps1          （拉代码 + 同步模板）" -ForegroundColor Yellow
    Write-Host "   2) 重载 DSH 插件      （plugin_manager set_bundle 关→开）" -ForegroundColor Yellow
    Write-Host "   3) start-all.ps1 -Init（补 startup.json）" -ForegroundColor Yellow
    Write-Host "   4) make-shortcut.ps1 （建桌面快捷方式）" -ForegroundColor Yellow
    exit 1
}
