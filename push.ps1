<#
.SYNOPSIS
  Stage everything, commit with a message, push to origin.

.DESCRIPTION
  One-shot helper for this workspace. Runs `git add -A`, takes a commit
  message (parameter or interactive prompt), commits, then pushes.
  Run it from anywhere: it always operates on the repository that holds it.

  ASCII-only on purpose: Windows PowerShell 5.1 decodes BOM-less scripts as
  ANSI, so Chinese text here would be mangled.

.PARAMETER Message
  Commit message. Omit it to be prompted.

.PARAMETER NoPush
  Commit only, do not push.

.EXAMPLE
  .\push.ps1
  .\push.ps1 -Message "feat: add login page"
  .\push.ps1 -Message "wip" -NoPush
#>
param(
  [string]$Message = '',
  [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

# Resolve git: PATH first, then the standard install location.
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = 'C:\Program Files\Git\cmd\git.exe' }
if (-not (Test-Path $git)) { throw 'git not found' }

# Always work on the repo this script lives in.
$root = $PSScriptRoot
Set-Location $root

& $git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { throw "not a git repository: $root" }

# 1. stage
& $git add -A
if ($LASTEXITCODE -ne 0) { throw 'git add failed' }

$staged = & $git diff --cached --name-only
if (-not $staged) {
  Write-Host 'Nothing to commit - working tree is clean.' -ForegroundColor Yellow
  exit 0
}

Write-Host ("Staged {0} file(s):" -f @($staged).Count) -ForegroundColor Cyan
$staged | ForEach-Object { Write-Host ("  " + $_) }

# 2. message
if (-not $Message) {
  $Message = Read-Host 'Commit message'
}
if (-not $Message -or -not $Message.Trim()) {
  Write-Host 'Empty commit message - aborted, changes stay staged.' -ForegroundColor Red
  exit 1
}

# 3. commit
& $git commit -m $Message
if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }

$sha = (& $git rev-parse --short HEAD).Trim()
$branch = (& $git rev-parse --abbrev-ref HEAD).Trim()
Write-Host ("Committed {0} on {1}" -f $sha, $branch) -ForegroundColor Green

if ($NoPush) {
  Write-Host 'Skipped push (-NoPush).' -ForegroundColor Yellow
  exit 0
}

# 4. push (set upstream on first push)
& $git rev-parse --abbrev-ref '@{u}' *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'No upstream yet - pushing with -u origin HEAD' -ForegroundColor Cyan
  & $git push -u origin HEAD
} else {
  & $git push
}
if ($LASTEXITCODE -ne 0) { throw 'git push failed' }

Write-Host ("Pushed {0} to origin/{1}" -f $sha, $branch) -ForegroundColor Green
