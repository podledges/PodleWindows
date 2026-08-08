#Requires -Version 5.1
<#
.SYNOPSIS
  PODLES setup smoke - post-install verification (Windows twin of smoke.sh).

.DESCRIPTION
  Read-only: verifies tool versions against setup/versions.manifest, config
  shape, and the no-hardcoded-user-paths rule. Exit 0 = passed, 1 = failures.

.PARAMETER Strict
  WARNs also fail (clean-machine proof runs).
#>
[CmdletBinding()]
param(
  [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:Fail = $false
$script:Warned = $false

function Write-Ok([string]$Message)   { Write-Host "[podles-smoke] OK: $Message" -ForegroundColor Green }
function Write-Info([string]$Message) { Write-Host "[podles-smoke] $Message" -ForegroundColor Cyan }
function Write-SmokeWarn([string]$Message) { Write-Host "[podles-smoke] WARN: $Message" -ForegroundColor Yellow; $script:Warned = $true }
function Write-SmokeFail([string]$Message) { Write-Host "[podles-smoke] FAIL: $Message" -ForegroundColor Red; $script:Fail = $true }

$setupDir = $PSScriptRoot
if (-not $setupDir) { $setupDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$homeDir = Split-Path -Parent $setupDir
$manifest = Join-Path $setupDir 'versions.manifest'

# --- 1. Home shape ----------------------------------------------------------
if (Test-Path -LiteralPath (Join-Path $homeDir 'AGENTS.md')) { Write-Ok 'AGENTS.md present' } else { Write-SmokeFail "AGENTS.md missing at $homeDir" }
if (Test-Path -LiteralPath (Join-Path $homeDir 'bin')) { Write-Ok 'bin/ present' } else { Write-SmokeFail 'bin/ missing' }

# --- 2. Tool versions vs manifest -------------------------------------------
function Get-FirstVersion([string]$Text) {
  $m = [regex]::Match($Text, '[0-9]+\.[0-9]+(\.[0-9]+)?')
  if ($m.Success) { return $m.Value }
  return $null
}

if (-not (Test-Path -LiteralPath $manifest)) {
  Write-SmokeFail "versions.manifest missing at $manifest"
} else {
  foreach ($line in Get-Content -LiteralPath $manifest) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#')) { continue }
    $parts = $t -split '\s+'
    $tool = $parts[0]; $min = $parts[1]; $requirement = $parts[2]
    $verArgs = @()
    if ($parts.Count -gt 3) { $verArgs = $parts[3..($parts.Count - 1)] }
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      if ($requirement -eq 'required') {
        Write-SmokeFail "$tool missing (required, min $min)"
      } else {
        Write-SmokeWarn "$tool missing (optional, min $min)"
      }
      continue
    }
    $out = ''
    try { $out = (& $tool @verArgs 2>&1 | Out-String) } catch { $out = '' }
    $got = Get-FirstVersion $out
    if (-not $got) {
      Write-SmokeWarn "$tool present but version unreadable"
    } elseif ([version]($got + $(if (($got -split '\.').Count -lt 3) { '.0' } else { '' })) -ge [version]($min + $(if (($min -split '\.').Count -lt 3) { '.0' } else { '' }))) {
      Write-Ok ("{0,-12} {1} (min {2})" -f $tool, $got, $min)
    } else {
      Write-SmokeFail "$tool version $got below manifest minimum $min"
    }
  }
}

# --- 3. Config shape --------------------------------------------------------
$configDir = Join-Path $homeDir 'config'
$backendPath = Join-Path $configDir 'backend'
if (Test-Path -LiteralPath $backendPath) {
  $backend = (Get-Content -LiteralPath $backendPath -Raw).Trim()
  if ($backend -in @('herdr', 'tmux', 'cmux')) { Write-Ok "config/backend = $backend" } else { Write-SmokeFail "config/backend has unexpected value '$backend'" }
} else {
  Write-SmokeWarn 'config/backend not applied yet (run install with -ApplyConfig)'
}
$harnessPath = Join-Path $configDir 'crew-harness'
if (Test-Path -LiteralPath $harnessPath) {
  $harness = (Get-Content -LiteralPath $harnessPath -Raw).Trim()
  if ($harness -in @('pi', 'claude')) { Write-Ok "config/crew-harness = $harness" } else { Write-SmokeFail "config/crew-harness has unexpected value '$harness'" }
} else {
  Write-SmokeWarn 'config/crew-harness not applied yet'
}
$dispatchPath = Join-Path $configDir 'crew-dispatch.json'
if (Test-Path -LiteralPath $dispatchPath) {
  try {
    $null = Get-Content -LiteralPath $dispatchPath -Raw | ConvertFrom-Json
    Write-Ok 'config/crew-dispatch.json is valid JSON'
  } catch {
    Write-SmokeFail 'config/crew-dispatch.json is not valid JSON'
  }
} else {
  Write-SmokeWarn 'config/crew-dispatch.json not applied yet'
}

# --- 4. Kit hygiene: no per-user absolute paths in setup/ -------------------
$patterns = '([A-Za-z]:\\+Users\\+|/[a-z]/Users/|(^|[^A-Za-z])/Users/)[A-Za-z0-9._-]+'
$kitFiles = Get-ChildItem -LiteralPath $setupDir -Recurse -File |
  Where-Object { $_.Extension -in @('.sh', '.ps1', '.md', '.example', '.manifest') }
$hits = @()
foreach ($f in $kitFiles) {
  $found = Select-String -LiteralPath $f.FullName -Pattern $patterns -AllMatches -ErrorAction SilentlyContinue |
    Where-Object { $_.Line -notmatch 'Users[\\/]<' }
  if ($found) { $hits += $found }
}
if ($hits.Count -gt 0) {
  Write-SmokeFail 'hardcoded user-profile paths found in setup/:'
  $hits | Select-Object -First 10 | ForEach-Object { Write-Host ("  {0}:{1}: {2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim()) -ForegroundColor Red }
} else {
  Write-Ok 'no hardcoded user-profile paths in setup/'
}

# --- 5. Result --------------------------------------------------------------
if ($Strict -and $script:Warned) {
  Write-SmokeFail 'strict mode: WARNs present'
}
if ($script:Fail) {
  Write-Info 'SMOKE FAILED'
  exit 1
}
Write-Info 'SMOKE PASSED'
exit 0
