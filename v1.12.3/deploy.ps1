<#
.SYNOPSIS
    部署 Typora 1.12.3 授权 shim：备份原 app.asar 并替换为注入版。

.DESCRIPTION
    1. 自动定位 Typora 安装目录（或使用 -TyporaRoot）
    2. 首次部署时把原始 app.asar 备份为 app.asar.orig-backup
    3. 复制注入版 asar（-Asar，默认取脚本同目录的 app.asar.patched）
    4. 安装 shim 到 %LOCALAPPDATA%\TyporaPatch\hook.js
    5. 校验 sha256

    需要管理员权限：脚本会自动通过 UAC 自我提权。

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Asar .\app.asar.patched
    .\deploy.ps1 -TyporaRoot 'D:\Apps\Typora'
#>
[CmdletBinding()]
param(
    [string]$Asar = (Join-Path $PSScriptRoot 'app.asar.patched'),
    [string]$TyporaRoot = '',
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'

function Write-Step($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Write-Bad($m)  { Write-Host "[x] $m" -ForegroundColor Red }

# ---------------------------------------------------------------- elevate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "需要管理员权限，正在请求提权..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
        '-Asar', "`"$Asar`"")
    if ($TyporaRoot) { $argList += @('-TyporaRoot', "`"$TyporaRoot`"") }
    if ($KeepRunning) { $argList += '-KeepRunning' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait
    exit
}

# ---------------------------------------------------------------- locate Typora
if (-not $TyporaRoot) {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Typora'),
        (Join-Path ${env:ProgramFiles(x86)} 'Typora'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Typora')
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'Typora.exe')) }
    if (-not $candidates) { Write-Bad "找不到 Typora 安装目录，请用 -TyporaRoot 指定"; exit 1 }
    $TyporaRoot = $candidates[0]
}
$ResDir = Join-Path $TyporaRoot 'resources'
$Target = Join-Path $ResDir 'app.asar'
$Backup = Join-Path $ResDir 'app.asar.orig-backup'

Write-Step "Typora     : $TyporaRoot"
if (-not (Test-Path $Target)) { Write-Bad "找不到 $Target"; exit 1 }
if (-not (Test-Path $Asar))   { Write-Bad "找不到注入版 asar: $Asar（先运行 build-asar.js）"; exit 1 }

# ---------------------------------------------------------------- stop app
if (-not $KeepRunning) {
    $procs = @(Get-Process Typora -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0) {
        Write-Step "关闭 Typora（$($procs.Count) 个进程）..."
        foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null } catch {} }
        Start-Sleep -Seconds 3
        Get-Process Typora -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Remove-Item (Join-Path $env:APPDATA 'Typora\lockfile') -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- backup + copy
if (-not (Test-Path $Backup)) {
    Copy-Item $Target $Backup -Force
    Write-Ok "原始备份: $Backup ($((Get-Item $Backup).Length) 字节)"
} else {
    Write-Step "备份已存在，保留: $Backup"
}

Copy-Item $Asar $Target -Force
$srcHash = (Get-FileHash $Asar   -Algorithm SHA256).Hash
$dstHash = (Get-FileHash $Target -Algorithm SHA256).Hash
if ($srcHash -ne $dstHash) { Write-Bad "复制后哈希不一致"; exit 1 }
Write-Ok "已替换 app.asar ($((Get-Item $Target).Length) 字节, sha256 $($dstHash.Substring(0,16))...)"

# ---------------------------------------------------------------- install shim
$patchDir = Join-Path $env:LOCALAPPDATA 'TyporaPatch'
New-Item -ItemType Directory -Path $patchDir -Force | Out-Null
$shimSrc = Join-Path $PSScriptRoot 'shim.js'
if (-not (Test-Path $shimSrc)) { Write-Bad "找不到 shim.js: $shimSrc"; exit 1 }
Copy-Item $shimSrc (Join-Path $patchDir 'hook.js') -Force
Write-Ok "shim 已安装: $patchDir\hook.js"

Write-Host ""
Write-Ok "部署完成。启动 Typora 后检查日志："
Write-Host "    Get-Content `"$env:APPDATA\Typora\typora.log`" -Tail 20 | Select-String 'hasL'"
Write-Host "    期望: [watch L] hasL: true"
Write-Host ""
Write-Host "还原: .\restore.ps1" -ForegroundColor DarkGray
