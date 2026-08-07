#Requires -Version 5.1
<#
.SYNOPSIS
  PODLES Firstmate setup bootstrap (Windows).

.DESCRIPTION
  Discovers the firstmate home as the parent of this script's directory.
  Detects tools, prompts for primary harness (Pi vs Claude), optionally
  applies config templates, and prints auth/smoke next steps.

  Never hardcodes a user profile path. Does not store secrets.

.PARAMETER DryRun
  Detect and print only; no installs, no config writes.

.PARAMETER Primary
  Skip prompt: pi | claude

.PARAMETER ApplyConfig
  Copy example configs into <home>/config (and captain example if missing).

.PARAMETER SkipNpmInstall
  Do not offer npm global installs.

.PARAMETER Yes
  Prefer non-destructive yes on optional install offers only.
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [ValidateSet('pi', 'claude')]
  [string]$Primary,
  [switch]$ApplyConfig,
  [switch]$SkipNpmInstall,
  [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-Info([string]$Message) { Write-Host "[podles-setup] $Message" -ForegroundColor Cyan }
function Write-Warn([string]$Message) { Write-Host "[podles-setup] WARN: $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message)  { Write-Host "[podles-setup] ERROR: $Message" -ForegroundColor Red }
function Write-Ok([string]$Message)   { Write-Host "[podles-setup] OK: $Message" -ForegroundColor Green }

function Get-SetupPaths {
  $scriptDir = $PSScriptRoot
  if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
  $homeDir = Split-Path -Parent $scriptDir
  [pscustomobject]@{
    SetupDir = $scriptDir
    HomeDir  = $homeDir
    ConfigDir = Join-Path $homeDir 'config'
    DataDir   = Join-Path $homeDir 'data'
    ExampleDir = Join-Path $scriptDir 'config'
    AgentsMd = Join-Path $homeDir 'AGENTS.md'
  }
}

function New-SetupLog {
  $dir = [System.IO.Path]::GetTempPath()
  $name = 'podles-setup-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)
  $path = Join-Path $dir $name
  "PODLES setup log $(Get-Date -Format o)" | Out-File -FilePath $path -Encoding utf8
  return $path
}

function Write-Log([string]$LogPath, [string]$Message) {
  if ($LogPath) {
    Add-Content -Path $LogPath -Value ("{0} {1}" -f (Get-Date -Format o), $Message)
  }
}

function Test-CommandExists([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ToolVersion([string]$Name, [string[]]$VersionArgs) {
  if (-not (Test-CommandExists $Name)) { return $null }
  try {
    $out = & $Name @VersionArgs 2>&1 | Out-String
    $line = ($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    return $line.Trim()
  } catch {
    return '(present, version unknown)'
  }
}

function Test-BashIsGitFriendly {
  $bash = Get-Command bash -ErrorAction SilentlyContinue
  if (-not $bash) {
    return [pscustomobject]@{ Ok = $false; Detail = 'bash not on PATH' }
  }
  $src = $bash.Source
  if ($src -match 'System32\\bash\.exe$' -or $src -match '\\WindowsApps\\' -or $src -match 'wsl') {
    return [pscustomobject]@{ Ok = $false; Detail = "bash resolves to WSL/store shadow: $src" }
  }
  return [pscustomobject]@{ Ok = $true; Detail = $src }
}

function Read-YesNo([string]$Prompt, [bool]$DefaultNo = $true) {
  if ($Yes -and -not $DefaultNo) { return $true }
  $suffix = if ($DefaultNo) { '[y/N]' } else { '[Y/n]' }
  $r = Read-Host "$Prompt $suffix"
  if ([string]::IsNullOrWhiteSpace($r)) { return -not $DefaultNo }
  return $r -match '^(y|yes)$'
}

function Get-PrimaryChoice {
  param([string]$Forced)
  if ($Forced) { return $Forced }
  Write-Host ''
  Write-Host 'Primary agent choice (credits / quota)' -ForegroundColor Magenta
  Write-Host '  Yes = lots of GPT remaining, OR little/no Claude left  -> Pi primary (crew: Grok + GPT/Codex)'
  Write-Host '  No  = Claude usage still available / prefer subscription -> Claude primary (save API credits)'
  Write-Host ''
  $r = Read-Host 'Do you have a lot of GPT usage remaining, or little/no Claude usage left? [y/N]'
  if ($r -match '^(y|yes)$') { return 'pi' }
  return 'claude'
}

function Copy-ExampleConfig {
  param(
    [string]$Source,
    [string]$Dest,
    [string]$LogPath,
    [switch]$WhatIfDry
  )
  if (-not (Test-Path -LiteralPath $Source)) {
    Write-Warn "Missing example: $Source"
    return
  }
  $destDir = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $destDir)) {
    if ($WhatIfDry) { Write-Info "DRY: mkdir $destDir"; return }
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  }
  if (Test-Path -LiteralPath $Dest) {
    $existing = (Get-Content -LiteralPath $Dest -Raw -ErrorAction SilentlyContinue)
    $incoming = (Get-Content -LiteralPath $Source -Raw -ErrorAction SilentlyContinue)
    if ($existing -eq $incoming) {
      Write-Ok "Unchanged: $Dest"
      return
    }
    if ($WhatIfDry) {
      Write-Info "DRY: would prompt overwrite $Dest"
      return
    }
    if (-not (Read-YesNo "Overwrite existing $Dest ?" $true)) {
      Write-Info "Kept existing $Dest"
      Write-Log $LogPath "skip overwrite $Dest"
      return
    }
  } elseif ($WhatIfDry) {
    Write-Info "DRY: copy $Source -> $Dest"
    return
  }
  Copy-Item -LiteralPath $Source -Destination $Dest -Force
  Write-Ok "Wrote $Dest"
  Write-Log $LogPath "wrote $Dest"
}

# --- main ---
$paths = Get-SetupPaths
$log = New-SetupLog
Write-Info "Log: $log"
Write-Log $log "home=$($paths.HomeDir) setup=$($paths.SetupDir) dry=$DryRun"

if (-not (Test-Path -LiteralPath $paths.AgentsMd)) {
  Write-Err "AGENTS.md not found at $($paths.HomeDir). Run this from a firstmate home that contains setup/."
  Write-Log $log 'FAIL no AGENTS.md'
  exit 1
}
Write-Ok "Firstmate home: $($paths.HomeDir)"

$bashCheck = Test-BashIsGitFriendly
if ($bashCheck.Ok) {
  Write-Ok "bash: $($bashCheck.Detail)"
} else {
  Write-Warn $bashCheck.Detail
  Write-Warn 'Move Git for Windows above WSL on PATH, then FULLY restart terminals/IDE/Herdr/agents. See setup/DEBUG.md'
  Write-Log $log "bash warn: $($bashCheck.Detail)"
}

$tools = @(
  @{ Name = 'node'; Args = @('-v') },
  @{ Name = 'npm'; Args = @('-v') },
  @{ Name = 'git'; Args = @('--version') },
  @{ Name = 'gh'; Args = @('--version') },
  @{ Name = 'jq'; Args = @('--version') },
  @{ Name = 'pi'; Args = @('--version') },
  @{ Name = 'claude'; Args = @('--version') },
  @{ Name = 'codex'; Args = @('--version') },
  @{ Name = 'grok'; Args = @('--version') },
  @{ Name = 'herdr'; Args = @('--version') },
  @{ Name = 'treehouse'; Args = @('--version') },
  @{ Name = 'no-mistakes'; Args = @('--version') }
)

Write-Host ''
Write-Info 'Tool detection'
$missing = @()
foreach ($t in $tools) {
  $ver = Get-ToolVersion $t.Name $t.Args
  if ($ver) {
    Write-Ok ("{0,-12} {1}" -f $t.Name, $ver)
    Write-Log $log ("tool {0}={1}" -f $t.Name, $ver)
  } else {
    Write-Warn ("{0,-12} MISSING" -f $t.Name)
    Write-Log $log ("tool {0}=MISSING" -f $t.Name)
    $missing += $t.Name
  }
}

$primary = Get-PrimaryChoice -Forced $Primary
Write-Info "Primary harness choice: $primary"
Write-Log $log "primary=$primary"

if (-not $SkipNpmInstall -and -not $DryRun) {
  $npmTargets = @()
  if ($missing -contains 'pi') { $npmTargets += '@earendil-works/pi-coding-agent' }
  # Package names drift — offer only if clearly missing and user confirms
  if ($missing -contains 'claude') {
    Write-Warn 'Claude Code missing: install via current Anthropic docs (npm global or native installer), then re-run detection.'
  }
  foreach ($pkg in @('gh-axi', 'lavish-axi', 'quota-axi', 'tasks-axi', 'chrome-devtools-axi')) {
    if (-not (Test-CommandExists $pkg)) { $npmTargets += $pkg }
  }
  if ($npmTargets.Count -gt 0 -and (Test-CommandExists 'npm')) {
    Write-Info ("Optional npm globals: {0}" -f ($npmTargets -join ', '))
    if (Read-YesNo 'Run npm install -g for the packages listed above?' $true) {
      foreach ($pkg in $npmTargets) {
        Write-Info "npm install -g $pkg"
        npm install -g $pkg 2>&1 | Tee-Object -FilePath $log -Append | Out-Host
      }
    }
  }
} elseif ($DryRun) {
  Write-Info 'DRY: skipped npm install offers'
}

Write-Host ''
Write-Info 'Manual installs (open vendor docs if MISSING)'
Write-Host '  Herdr:     https://herdr.dev  (add bin to PATH)'
Write-Host '  Codex:     official Codex CLI for your account'
Write-Host '  Grok:      Grok Build CLI + auth'
Write-Host '  treehouse: firstmate bootstrap or releases'
Write-Host '  gh:        winget install GitHub.cli'
Write-Host '  no-mistakes: ADD DEFENDER EXCLUSION FIRST, then install (setup/DEBUG.md)'

$shouldApply = $ApplyConfig
if (-not $shouldApply -and -not $DryRun) {
  $shouldApply = Read-YesNo 'Apply PODLES config templates into config/ (prompt before overwrite)?' $false
}

if ($shouldApply -or $DryRun) {
  Write-Host ''
  Write-Info 'Config templates'
  $ex = $paths.ExampleDir
  Copy-ExampleConfig (Join-Path $ex 'backend.example') (Join-Path $paths.ConfigDir 'backend') $log -WhatIfDry:$DryRun

  $harnessSrc = if ($primary -eq 'claude') {
    Join-Path $ex 'crew-harness.claude.example'
  } else {
    Join-Path $ex 'crew-harness.example'
  }
  Copy-ExampleConfig $harnessSrc (Join-Path $paths.ConfigDir 'crew-harness') $log -WhatIfDry:$DryRun

  $dispatchSrc = if ($primary -eq 'claude') {
    Join-Path $ex 'crew-dispatch.claude-primary.json.example'
  } else {
    Join-Path $ex 'crew-dispatch.json.example'
  }
  Copy-ExampleConfig $dispatchSrc (Join-Path $paths.ConfigDir 'crew-dispatch.json') $log -WhatIfDry:$DryRun

  $captainDest = Join-Path $paths.DataDir 'captain.md'
  if (-not (Test-Path -LiteralPath $captainDest)) {
    Copy-ExampleConfig (Join-Path $ex 'captain.md.example') $captainDest $log -WhatIfDry:$DryRun
  } else {
    Write-Ok "Left existing data/captain.md in place"
  }
}

Write-Host ''
Write-Info 'Next steps'
Write-Host '  1. Fix any WARN above (especially Git Bash PATH) and FULLY restart shells.'
Write-Host '  2. Auth: gh auth login; claude/codex/grok logins; herdr ready.'
Write-Host '  3. Open CHECKLIST.md and tick smoke tests.'
if ($primary -eq 'pi') {
  Write-Host "  4. cd `"$($paths.HomeDir)`" ; pi"
  Write-Host '     Approve project trust (or use -e fallback in setup/README.md).'
} else {
  Write-Host "  4. cd `"$($paths.HomeDir)`" ; claude"
  Write-Host '     Folder trust, then bypass-permissions (Down+Enter if default is No/exit).'
}
Write-Host "  5. Log file: $log"
Write-Host '  6. Problems: setup/DEBUG.md'
Write-Log $log 'done'
Write-Ok 'Setup script finished.'
exit 0
