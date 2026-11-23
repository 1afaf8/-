<#
.SYNOPSIS
  可再生存量缓存清理器。默认预演（只列路径与大小），加 -Apply 才真正删除。

.DESCRIPTION
  只处理可再生缓存：
    · AMD 着色器缓存（DXC / DX / Vulkan / OpenGL / DX9）
    · Windows 临时文件（%TEMP%、C:\Windows\Temp、Windows 更新缓存）
    · 缩略图缓存（thumbcache_*.db）
    · 浏览器缓存（Chrome / Edge / Brave / 夸克 / Firefox，仅 Cache 类目录）
    · IDE 缓存（VS Code / Cursor / VSCodium / JetBrains 系）

  明确不碰：
    · 桌面 / 文档 / 下载 / 图片 / 视频里的任何文件
    · 微信、QQ 等通讯软件"文件"目录里的接收文件
    · 休眠文件 hiberfil.sys、页面文件 pagefile.sys（不关闭休眠功能）
    · 系统还原点 / 卷影副本（不执行 vssadmin 删除）
    · C:\Windows\WinSxS、C:\Windows\Installer、已安装软件及其目录
    · 浏览器 Login Data / Cookies / History / Bookmarks
    · 回收站（默认不清空）

  删除方式：只删目录内的内容，保留目录本身；被占用文件自动跳过，不强制解锁。
  容量口径：按文件逻辑大小统计。稀疏/压缩文件的实际占盘可能明显更小，
            最终以"剩余空间变化"为准（脚本会在 -Apply 后报告真实释放量）。

.PARAMETER Apply
  真正执行删除。不加此参数 = 预演，不动任何文件。

.PARAMETER LogPath
  可选。把输出同时写入日志文件（提权运行时看不到窗口，靠日志读结果）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\clean-caches.ps1

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\clean-caches.ps1 -Apply
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [string]$LogPath = ""
)

$ErrorActionPreference = "SilentlyContinue"
$script:Freed = [int64]0
$script:TotalLogical = [int64]0
$script:Items = 0

# ---------------------------------------------------------------------------
# 基础设施
# ---------------------------------------------------------------------------

function Write-Log {
  param([string]$Msg)
  Write-Output $Msg
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value $Msg -Encoding UTF8 }
}

function Format-Size {
  param([int64]$Bytes)
  if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
  return ("{0:N0} MB" -f ($Bytes / 1MB))
}

function Get-TargetBytes {
  param([string]$Path, [string]$Filter = "")
  if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
  if ($Filter) {
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -Filter $Filter -ErrorAction SilentlyContinue
  } else {
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
  }
  $sum = ($files | Measure-Object -Property Length -Sum).Sum
  if (-not $sum) { return [int64]0 }
  return [int64]$sum
}

# 白名单：只允许操作这些根之下（或等于）的路径
$AllowedRoots = @(
  $env:TEMP,
  $env:LOCALAPPDATA,
  $env:APPDATA,
  "C:\Windows\Temp",
  "C:\Windows\SoftwareDistribution\Download"
)

function Test-AllowedPath {
  param([string]$Path)
  $norm = $Path.TrimEnd('\')
  foreach ($r in $AllowedRoots) {
    if (-not $r) { continue }
    $rn = $r.TrimEnd('\')
    if ($norm -ieq $rn) { return $true }
    if ($norm -ilike "$rn\*") { return $true }
  }
  return $false
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------------------------
# 目标清单（Name / Path / Risk / Note / Admin / Filter）
# ---------------------------------------------------------------------------

$Targets = @()
function Add-Target {
  param(
    [string]$Name, [string]$Path, [string]$Risk, [string]$Note,
    [bool]$Admin = $false, [string]$Filter = ""
  )
  $script:Targets += [pscustomobject]@{
    Name = $Name; Path = $Path; Risk = $Risk; Note = $Note; Admin = $Admin; Filter = $Filter
  }
}

# --- 1. Windows 临时文件 ---
Add-Target "用户临时文件 %TEMP%" $env:TEMP "低" "正在运行的程序占用的文件会自动跳过，删不掉不影响"
Add-Target "系统临时文件 Windows\Temp" "C:\Windows\Temp" "低" "需管理员；同上，占用文件跳过" $true
Add-Target "Windows 更新缓存" "C:\Windows\SoftwareDistribution\Download" "低" "需管理员；只停一次更新服务，清完恢复原状态（不改变系统设置）" $true

# --- 2. 缩略图缓存 ---
Add-Target "缩略图缓存" "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" "低" "只删 thumbcache_*.db；资源管理器会自动重建，首次打开图片文件夹略慢" $false "thumbcache_*.db"

# --- 3. AMD / DirectX 着色器缓存 ---
$amdRoot = "$env:LOCALAPPDATA\AMD"
foreach ($c in @("DxcCache", "DxCache", "VkCache", "OglCache", "Dx9Cache")) {
  $p = Join-Path $amdRoot $c
  if (Test-Path -LiteralPath $p) {
    Add-Target "AMD 着色器缓存 $c" $p "低" "预编译着色器，删除后自动重建；首次进游戏/首次启动 3D 应用会略慢"
  }
}
if (Test-Path -LiteralPath "$env:LOCALAPPDATA\D3DSCache") {
  Add-Target "D3D 着色器缓存" "$env:LOCALAPPDATA\D3DSCache" "低" "同上，自动重建"
}

# --- 4. 浏览器缓存（仅 Cache 类目录，绝不碰登录/书签/历史）---
$ChromiumBrowsers = @(
  @{ Name = "Chrome"; Root = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
  @{ Name = "Edge"; Root = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
  @{ Name = "Brave"; Root = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
  @{ Name = "夸克"; Root = "$env:LOCALAPPDATA\Quark\User Data" }
)
foreach ($b in $ChromiumBrowsers) {
  if (-not (Test-Path -LiteralPath $b.Root)) { continue }
  $profiles = Get-ChildItem -LiteralPath $b.Root -Directory -ErrorAction SilentlyContinue
  foreach ($prof in $profiles) {
    if ($prof.Name -ne "Default" -and $prof.Name -notlike "Profile *") { continue }
    foreach ($sub in @("Cache", "Code Cache", "GPUCache")) {
      $t = Join-Path $prof.FullName $sub
      if (Test-Path -LiteralPath $t) {
        Add-Target ("{0} 缓存 [{1}/{2}]" -f $b.Name, $prof.Name, $sub) $t "低" "网页缓存；登录状态、书签、历史均不受影响；浏览器运行时会跳过占用文件"
      }
    }
  }
}

$ffRoot = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
if (Test-Path -LiteralPath $ffRoot) {
  foreach ($prof in (Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue)) {
    $t = Join-Path $prof.FullName "cache2"
    if (Test-Path -LiteralPath $t) {
      Add-Target ("Firefox 缓存 [{0}]" -f $prof.Name) $t "低" "网页缓存，登录状态与书签不受影响"
    }
  }
}

# --- 5. IDE 缓存 ---
$Editors = @(
  @{ Name = "VS Code"; Root = "$env:APPDATA\Code" },
  @{ Name = "Cursor"; Root = "$env:APPDATA\Cursor" },
  @{ Name = "VSCodium"; Root = "$env:APPDATA\VSCodium" }
)
foreach ($e in $Editors) {
  if (-not (Test-Path -LiteralPath $e.Root)) { continue }
  foreach ($sub in @("Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs", "logs")) {
    $t = Join-Path $e.Root $sub
    if (Test-Path -LiteralPath $t) {
      $risk = if ($sub -eq "CachedData" -or $sub -eq "CachedExtensionVSIXs") { "中" } else { "低" }
      $note = if ($risk -eq "中") { "扩展宿主缓存；删除后首次启动会重新编译/校验扩展，稍慢" } else { "界面与网页缓存，自动重建" }
      Add-Target ("{0} {1}" -f $e.Name, $sub) $t $risk $note
    }
  }
}

$jbRoot = "$env:LOCALAPPDATA\JetBrains"
if (Test-Path -LiteralPath $jbRoot) {
  foreach ($prod in (Get-ChildItem -LiteralPath $jbRoot -Directory -ErrorAction SilentlyContinue)) {
    $t = Join-Path $prod.FullName "caches"
    if (Test-Path -LiteralPath $t) {
      Add-Target ("JetBrains {0} 索引缓存" -f $prod.Name) $t "中" "删除后项目下次打开需重建索引，超大项目可能几分钟，期间搜索/跳转变慢"
    }
  }
}

# ---------------------------------------------------------------------------
# 执行
# ---------------------------------------------------------------------------

$mode = if ($Apply) { "实际清理" } else { "预演（不删除任何文件）" }
Write-Log ("=== C 盘可再生缓存清理 | {0} | {1} ===" -f $mode, (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
if (-not $isAdmin) { Write-Log "提示：当前非管理员，标记「需管理员」的项会被跳过。想全清请右键 → 以管理员身份运行。" }
Write-Log ""

$freeBefore = (Get-PSDrive C).Free

$wuWasRunning = $false
if ($Apply -and $isAdmin) {
  $wuWasRunning = (Get-Service wuauserv -ErrorAction SilentlyContinue).Status -eq "Running"
  if ($wuWasRunning) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }
}

foreach ($item in $Targets) {
  if (-not (Test-Path -LiteralPath $item.Path)) {
    Write-Log ("[跳过] {0} — 路径不存在" -f $item.Name)
    continue
  }
  if (-not (Test-AllowedPath $item.Path)) {
    Write-Log ("[中止] {0} — 路径不在白名单：{1}" -f $item.Name, $item.Path)
    continue
  }
  if ($item.Admin -and -not $isAdmin) {
    Write-Log ("[跳过] {0} — 需要管理员权限" -f $item.Name)
    continue
  }

  $sizeBefore = Get-TargetBytes -Path $item.Path -Filter $item.Filter
  $script:Items++
  $script:TotalLogical += $sizeBefore

  if (-not $Apply) {
    Write-Log ("[预演] {0,-28} {1,10}   风险:{2}  {3}" -f $item.Name, (Format-Size $sizeBefore), $item.Risk, $item.Note)
    Write-Log ("        {0}" -f $item.Path)
    continue
  }

  if ($sizeBefore -eq 0) {
    Write-Log ("[完成] {0,-28} {1,10}   无内容可删" -f $item.Name, (Format-Size 0))
    continue
  }

  if ($item.Filter) {
    Get-ChildItem -LiteralPath $item.Path -Force -Filter $item.Filter -ErrorAction SilentlyContinue |
      Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
  } else {
    Get-ChildItem -LiteralPath $item.Path -Force -ErrorAction SilentlyContinue |
      Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
  }

  $sizeAfter = Get-TargetBytes -Path $item.Path -Filter $item.Filter
  $delta = $sizeBefore - $sizeAfter
  if ($delta -lt 0) { $delta = 0 }
  $script:Freed += $delta
  Write-Log ("[完成] {0,-28} 释放 {1,10}   风险:{2}" -f $item.Name, (Format-Size $delta), $item.Risk)
}

if ($Apply -and $isAdmin -and $wuWasRunning) { Start-Service wuauserv -ErrorAction SilentlyContinue }

Write-Log ""
if (-not $Apply) {
  Write-Log ("=== 预演结束：共 {0} 项，逻辑合计 {1}。未删除任何文件 ===" -f $script:Items, (Format-Size $script:TotalLogical))
  Write-Log "确认无误后加 -Apply 执行：powershell -NoProfile -ExecutionPolicy Bypass -File .\clean-caches.ps1 -Apply"
  Write-Log "注意：逻辑大小不等于实际占盘。稀疏/压缩的文件（例如 AMD 的 .parc 着色器块）标记很大但实际很小，"
  Write-Log "      真实回收量以 -Apply 结束时的「剩余空间变化」为准。被进程占用的缓存这次删不掉，重启后可再跑一次。"
} else {
  $freeAfter = (Get-PSDrive C).Free
  $real = $freeAfter - $freeBefore
  Write-Log ("=== 清理完成：逻辑删除 {0}，实际释放 {1}（C 盘剩余 {2} → {3}）===" -f `
      (Format-Size $script:Freed), (Format-Size $real),
      (Format-Size $freeBefore), (Format-Size $freeAfter))
  Write-Log "未触碰：个人文件、通讯软件接收的文件、休眠/页面文件、系统还原点、已安装软件、回收站"
  Write-Log "回收站未清空（默认保留，需要时可在回收站里查看或还原）。"
}
