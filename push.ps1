# 推送脚本：自动找本机代理，找不到就直连重试
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\push.ps1                  # 推 main + 标签
#   powershell -ExecutionPolicy Bypass -File .\push.ps1 -Message "备注"   # 先提交再推
#   powershell -ExecutionPolicy Bypass -File .\push.ps1 -Proxy 7890       # 指定代理端口
#   powershell -ExecutionPolicy Bypass -File .\push.ps1 -NoProxy          # 强制直连

param(
    [string]$Message = "",
    [int]$Proxy = 0,
    [switch]$NoProxy
)

$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repo

function Say($m, $c = "Cyan") { Write-Host $m -ForegroundColor $c }

Say "== 推送 H3 Studio =="

# ---------- 提交（可选） ----------
$dirty = (git status --porcelain)
if ($Message) {
    if (-not $dirty) { Say "没有需要提交的改动" "Yellow" }
    else {
        git add -A
        git -c user.name="Introduce183" -c user.email="Introduce183@users.noreply.github.com" commit -m $Message
        Say "已提交: $Message" "Green"
    }
} elseif ($dirty) {
    Say "提示：有未提交的改动，加 -Message `"说明`" 会自动提交" "Yellow"
}

# ---------- 找代理 ----------
$proxyUrl = $null
if (-not $NoProxy) {
    $ports = if ($Proxy) { @($Proxy) } else { @(7897, 7890, 7891, 1080, 10809, 2080) }
    foreach ($p in $ports) {
        $open = Test-NetConnection -ComputerName 127.0.0.1 -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if (-not $open) { continue }
        $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 8 -x "http://127.0.0.1:$p" https://github.com 2>$null
        if ($code -eq "200") { $proxyUrl = "http://127.0.0.1:$p"; Say "代理可用: $proxyUrl" "Green"; break }
        Say "端口 $p 开着但走不通 GitHub" "DarkGray"
    }
    if (-not $proxyUrl) { Say "没找到可用代理，改用直连" "Yellow" }
} else {
    Say "已指定直连（-NoProxy）" "Yellow"
}

# ---------- 推送 ----------
$gitArgs = @("push", "origin", "main", "--tags")
$ok = $false
for ($i = 1; $i -le 3; $i++) {
    Say "推送第 $i 次…" "DarkGray"
    if ($proxyUrl) {
        $out = git -c "http.proxy=$proxyUrl" -c "https.proxy=$proxyUrl" @gitArgs 2>&1
    } else {
        $out = git @gitArgs 2>&1
    }
    if ($LASTEXITCODE -eq 0) { $ok = $true; $out | Out-String; break }
    Say ("  失败: " + (($out | Select-Object -Last 2) -join ' / ')) "Yellow"
    Start-Sleep -Seconds (4 * $i)
}

if ($ok) {
    Say ""
    Say "推送成功。远端: https://github.com/Introduce183/h3-studio" "Green"
    $head = git log --oneline -1
    $ver = if (Test-Path (Join-Path $repo "VERSION")) { (Get-Content (Join-Path $repo "VERSION") -Raw).Trim() } else { "?" }
    Say "当前: v$ver  $head" "Green"
} else {
    Say ""
    Say "[失败] 三次都没推上去。" "Red"
    Say "  1) 确认 Clash / 梯子 已启动并在运行模式" "Yellow"
    Say "  2) 手动指定端口: .\push.ps1 -Proxy 7897" "Yellow"
    Say "  3) 或用 -NoProxy 走直连（国内可能超时）" "Yellow"
    exit 1
}
