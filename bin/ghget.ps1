<#
.SYNOPSIS
  Fetch a GitHub repository's source as a tarball (no git identity needed).

.DESCRIPTION
  Downloads from codeload.github.com and unpacks it. Gives you the working tree
  (no .git history), which is enough to read, edit and build. Pushing needs an
  SSH key or token separately.
  Compatible with Windows PowerShell 5.1. Keep this file ASCII-only: PS 5.1
  decodes BOM-less scripts as ANSI and would mangle non-ASCII paths.

.EXAMPLE
  powershell -NoProfile -File ghget.ps1 -Repo octocat/Hello-World
  powershell -NoProfile -File ghget.ps1 -Repo owner/repo -Ref refs/heads/dev -Out D:\src\repo
#>
param(
  [Parameter(Mandatory)][string]$Repo,
  [string]$Ref = '',
  [string]$Out = '',
  [int]$TimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $workspaceRoot '.cache'
if (-not (Test-Path $cache)) { New-Item -ItemType Directory -Force -Path $cache | Out-Null }

function Get-Tarball([string]$r, [string]$ref) {
  $url = "https://codeload.github.com/$r/tar.gz/$ref"
  $name = ($r -replace '[/\\]', '-')
  $tmp = Join-Path $cache ("ghget-" + $name + "-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".tgz")
  & curl.exe -sSL --fail -m $TimeoutSec -o $tmp $url 2>&1 | Out-Null
  $ok = $false
  if ((Test-Path $tmp) -and ((Get-Item $tmp).Length -gt 1024) -and ($LASTEXITCODE -eq 0)) { $ok = $true }
  return [pscustomobject]@{ Ok = $ok; Path = $tmp; Url = $url }
}

if ($Ref) { $tryRefs = @($Ref) } else { $tryRefs = @('refs/heads/main', 'refs/heads/master') }

$got = $null
foreach ($r in $tryRefs) {
  $res = Get-Tarball $Repo $r
  if ($res.Ok) { $got = $res; break }
  Write-Verbose ("failed: " + $res.Url)
}
if (-not $got) { throw ("download failed: " + $Repo + " (tried " + ($tryRefs -join ', ') + ")") }

if ($Ref) { $refSlug = $Ref } else { $refSlug = 'default' }
$refSlug = $refSlug -replace '[\\/:*?"<>|]', '-'

if (-not $Out) {
  $Out = Join-Path $cache (($Repo -replace '[/\\]', '-') + "-" + $refSlug)
}
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

& tar.exe -xzf $got.Path -C $Out
if ($LASTEXITCODE -ne 0) { throw ("unpack failed: " + $got.Path) }
Remove-Item $got.Path -Force -ErrorAction SilentlyContinue

$root = Get-ChildItem $Out -Directory | Select-Object -First 1
$dir = $Out
$size = 0
if ($root) {
  $dir = $root.FullName
  $size = [math]::Round((Get-ChildItem $root.FullName -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
}
if ($Ref) { $shown = $Ref } else { $shown = 'default' }
Write-Output ("OK " + $Repo + " @" + $shown + " -> " + $dir + " (" + $size + " MB)")
