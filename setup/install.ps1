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

.PARAMETER SkipWinget
  Do not offer winget installs.

.PARAMETER AddDefenderExclusion
  Offer to add the no-mistakes Defender exclusion via an elevated PowerShell
  (explicit consent; UAC prompt). Detect-only remains the default.

.PARAMETER OneShot
  Full replication pass: auto-yes installs (winget + npm), offer the Defender
  exclusion helper, apply config for the chosen primary, end with a
  verification rescan. Interactive vendor auth stays manual (honest boundary)
  but is sequenced at the end.

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
  [switch]$SkipWinget,
  [switch]$AddDefenderExclusion,
  [switch]$OneShot,
  [switch]$Yes
)

if ($OneShot -and -not $DryRun) {
  $Yes = $true
  $ApplyConfig = $true
  $AddDefenderExclusion = $true
}

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

function Test-DefenderExclusion {
  # Read-only inspection only. Never adds/removes exclusions.
  try {
    $pref = Get-MpPreference -ErrorAction Stop
    $candidates = @($pref.ExclusionPath) + @($pref.ExclusionProcess) | Where-Object { $_ }
    if ($candidates | Where-Object { $_ -match 'administrator to view exclusions' }) {
      return [pscustomobject]@{ Status = 'Unknown'; Detail = 'Defender hides exclusions from non-admin sessions; re-check from an elevated shell' }
    }
    $hit = $candidates | Where-Object { $_ -match 'no-mistakes' }
    if ($hit) {
      return [pscustomobject]@{ Status = 'Present'; Detail = ($hit -join '; ') }
    }
    return [pscustomobject]@{ Status = 'Absent'; Detail = 'No exclusion matching "no-mistakes" found' }
  } catch {
    return [pscustomobject]@{ Status = 'Unknown'; Detail = "Could not read Defender preferences: $($_.Exception.Message)" }
  }
}

function Get-NoMistakesDir {
  # Environment-derived; never a hardcoded user profile path.
  $base = $env:LOCALAPPDATA
  if (-not $base) { return $null }
  $dir = Join-Path $base 'no-mistakes'
  if (Test-Path -LiteralPath $dir) { return $dir }
  return $null
}

function Invoke-DefenderExclusionHelper {
  param([string]$LogPath, [switch]$WhatIfDry)
  $nmDir = Get-NoMistakesDir
  if (-not $nmDir) {
    Write-Warn 'Cannot locate the no-mistakes install directory (LOCALAPPDATA\no-mistakes).'
    Write-Warn 'Install no-mistakes first or add the exclusion manually - setup/DEBUG.md #3.'
    return $false
  }
  Write-Info 'Defender exclusion helper: will add an exclusion for'
  Write-Info "  $nmDir"
  Write-Info 'via an elevated PowerShell (expect a UAC prompt).'
  if ($WhatIfDry) {
    Write-Info "DRY: would run Add-MpPreference -ExclusionPath '$nmDir' elevated"
    return $false
  }
  if (-not (Read-YesNo 'Add the Defender exclusion now (elevated)?' $true)) {
    Write-Info 'Skipped Defender exclusion helper.'
    return $false
  }
  try {
    Start-Process powershell -Verb RunAs -Wait -ArgumentList @(
      '-NoProfile', '-Command', "Add-MpPreference -ExclusionPath `"$nmDir`""
    ) -ErrorAction Stop
    Write-Ok 'Defender exclusion helper finished; re-checking.'
    Write-Log $LogPath "defender-helper=ran path=$nmDir"
    return $true
  } catch {
    Write-Warn "Elevated Add-MpPreference did not complete (UAC declined?): $($_.Exception.Message)"
    Write-Warn 'Add manually - setup/DEBUG.md #3.'
    Write-Log $LogPath 'defender-helper=failed'
    return $false
  }
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

function Test-BashPathIsWslShadow([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  # System32/SysWOW64 bash launcher (with or without .exe), Store shim, or wsl-named hit.
  return [bool](
    $Path -match '(?i)[\\/]System32[\\/]bash(\.exe)?$' -or
    $Path -match '(?i)[\\/]SysWOW64[\\/]bash(\.exe)?$' -or
    $Path -match '(?i)[\\/]WindowsApps[\\/]' -or
    $Path -match '(?i)[\\/]wsl\.exe$' -or
    $Path -match '(?i)[\\/][Ww]sl[\\/]' -or
    $Path -match '(?i)wslbash'
  )
}

function Test-BashIsGitFriendly {
  # Prefer where.exe order (true Windows PATH). Get-Command alone can disagree
  # with cmd/where in edge cases; first where.exe hit is what most tools invoke.
  $candidates = New-Object System.Collections.Generic.List[string]
  try {
    $whereOut = & where.exe bash 2>$null
    foreach ($line in @($whereOut)) {
      $t = if ($null -ne $line) { "$line".Trim() } else { '' }
      if ($t -and -not $candidates.Contains($t)) { [void]$candidates.Add($t) }
    }
  } catch {
    # where.exe missing or failed — fall through to Get-Command
  }
  if ($candidates.Count -eq 0) {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash -and $bash.Source) {
      $src = "$($bash.Source)".Trim()
      if ($src) { [void]$candidates.Add($src) }
    }
  }
  if ($candidates.Count -eq 0) {
    return [pscustomobject]@{ Ok = $false; Detail = 'bash not on PATH' }
  }
  $first = $candidates[0]
  if (Test-BashPathIsWslShadow $first) {
    return [pscustomobject]@{ Ok = $false; Detail = "bash resolves to WSL/store shadow: $first" }
  }
  return [pscustomobject]@{ Ok = $true; Detail = $first }
}

function Read-HostSafe([string]$Prompt) {
  try {
    return Read-Host $Prompt
  } catch {
    Write-Warn 'Not running in an interactive session; using default answer.'
    return ''
  }
}

function Read-YesNo([string]$Prompt, [bool]$DefaultNo = $true) {
  if ($Yes -and -not $DefaultNo) { return $true }
  $suffix = if ($DefaultNo) { '[y/N]' } else { '[Y/n]' }
  $r = Read-HostSafe "$Prompt $suffix"
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
  $r = Read-HostSafe 'Do you have a lot of GPT usage remaining, or little/no Claude usage left? [y/N]'
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
  Write-Ok "bash (Windows PATH): $($bashCheck.Detail)"
  Write-Log $log "bash ok: $($bashCheck.Detail)"
} else {
  Write-Warn $bashCheck.Detail
  Write-Warn 'Move Git for Windows above WSL on PATH, then FULLY restart terminals/IDE/Herdr/agents.'
  Write-Warn 'See setup/DEBUG.md section 1 (Git Bash must beat WSL).'
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
  @{ Name = 'treehouse'; Args = @('--version') }
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

Write-Host ''
Write-Host '=== no-mistakes install gate (Defender-first - do not skip) ===' -ForegroundColor Magenta
Write-Host '  Step 1 (REQUIRED FIRST): add a Windows Defender exclusion for no-mistakes.exe / its install directory (admin).'
$defenderCheck = Test-DefenderExclusion
switch ($defenderCheck.Status) {
  'Present' { Write-Ok "Defender exclusion detected: $($defenderCheck.Detail)" }
  'Absent'  { Write-Warn 'No Defender exclusion for no-mistakes detected yet. Add it now before continuing - see setup/DEBUG.md #3.' }
  default   { Write-Warn "Could not verify Defender exclusion ($($defenderCheck.Detail)). Confirm manually before continuing - see setup/DEBUG.md #3." }
}
Write-Log $log "defender-exclusion=$($defenderCheck.Status)"
if ($AddDefenderExclusion -and $defenderCheck.Status -ne 'Present') {
  if (Invoke-DefenderExclusionHelper -LogPath $log -WhatIfDry:$DryRun) {
    $defenderCheck = Test-DefenderExclusion
    if ($defenderCheck.Status -eq 'Present') {
      Write-Ok "Defender exclusion now present: $($defenderCheck.Detail)"
    } else {
      Write-Warn "Exclusion still not visible ($($defenderCheck.Detail)); non-admin sessions cannot read it - verify from an elevated shell."
    }
    Write-Log $log "defender-exclusion-after-helper=$($defenderCheck.Status)"
  }
}
Write-Host '  Step 2 (ONLY AFTER Step 1): install or reinstall no-mistakes.'
$nmVer = Get-ToolVersion 'no-mistakes' @('--version')
if ($nmVer) {
  Write-Ok "no-mistakes detected: $nmVer"
  Write-Log $log "tool no-mistakes=$nmVer"
} else {
  Write-Warn 'no-mistakes not detected on PATH.'
  Write-Warn 'If no-mistakes worked before and is missing now (binary present yesterday, gone today), suspect Defender quarantine: check Get-MpThreatDetection BEFORE reinstalling - see setup/DEBUG.md #3.'
  Write-Log $log 'tool no-mistakes=MISSING'
}
Write-Host '  Full recovery steps: setup/DEBUG.md #3'

$primary = Get-PrimaryChoice -Forced $Primary
Write-Info "Primary harness choice: $primary"
Write-Log $log "primary=$primary"

# Foundation tools via winget (true Windows installs; PATH lands machine-wide
# after a shell restart). Only offers what is missing.
if (-not $SkipWinget -and -not $DryRun -and (Test-CommandExists 'winget')) {
  $wingetIds = @()
  if ($missing -contains 'gh')   { $wingetIds += 'GitHub.cli' }
  if ($missing -contains 'node') { $wingetIds += 'OpenJS.NodeJS.LTS' }
  if ($missing -contains 'jq')   { $wingetIds += 'jqlang.jq' }
  if ($wingetIds.Count -gt 0) {
    Write-Info ("Winget installs available for: {0}" -f ($wingetIds -join ', '))
    if (Read-YesNo 'Run winget install for the packages listed above?' $false) {
      foreach ($id in $wingetIds) {
        Write-Info "winget install $id"
        winget install --id $id --accept-source-agreements --accept-package-agreements 2>&1 |
          Tee-Object -FilePath $log -Append | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Warn "winget failed for $id" }
      }
      Write-Warn 'New winget installs need a FULL shell restart before they appear on PATH.'
    }
  }
} elseif ($DryRun) {
  Write-Info 'DRY: skipped winget install offers'
}

if (-not $SkipNpmInstall -and -not $DryRun) {
  $npmTargets = @()
  if ($missing -contains 'pi') { $npmTargets += '@earendil-works/pi-coding-agent' }
  if ($missing -contains 'claude') { $npmTargets += '@anthropic-ai/claude-code' }
  if ($missing -contains 'codex') { $npmTargets += '@openai/codex' }
  foreach ($pkg in @('gh-axi', 'lavish-axi', 'quota-axi', 'tasks-axi', 'chrome-devtools-axi')) {
    if (-not (Test-CommandExists $pkg)) { $npmTargets += $pkg }
  }
  $npmAskDefault = $true
  if ($OneShot) { $npmAskDefault = $false }
  if ($npmTargets.Count -gt 0 -and (Test-CommandExists 'npm')) {
    Write-Info ("Optional npm globals: {0}" -f ($npmTargets -join ', '))
    if (Read-YesNo 'Run npm install -g for the packages listed above?' $npmAskDefault) {
      foreach ($pkg in $npmTargets) {
        Write-Info "npm install -g $pkg"
        npm install -g $pkg 2>&1 | Tee-Object -FilePath $log -Append | Out-Host
      }
    }
  } elseif ($npmTargets.Count -gt 0) {
    Write-Warn ("npm not available; cannot offer: {0} (install Node first, restart, re-run)" -f ($npmTargets -join ', '))
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
Write-Host '  no-mistakes: see the Defender-first gate above (setup/DEBUG.md #3)'

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
Write-Info 'Verification rescan'
$ready = $true
$verifyMissing = @()
$verifyTools = @('node', 'npm', 'git', 'gh', 'jq', 'herdr', 'no-mistakes')
if ($primary -eq 'pi') { $verifyTools += 'pi' } else { $verifyTools += 'claude' }
foreach ($t in $verifyTools) {
  if (Test-CommandExists $t) {
    Write-Ok "verified: $t"
  } else {
    $verifyMissing += $t
    $ready = $false
  }
}
if ($verifyMissing.Count -gt 0) {
  Write-Warn ("Still missing: {0}" -f ($verifyMissing -join ', '))
  Write-Warn 'Fresh winget/npm installs need a FULL shell restart to land on PATH; restart and re-run to verify.'
}
Write-Log $log ("verify-missing={0}" -f $(if ($verifyMissing.Count) { $verifyMissing -join ',' } else { 'none' }))

# Auth is interactive by design (honest boundary); sequence it, don't fake it.
$ghAuth = 'unknown'
if (Test-CommandExists 'gh') {
  gh auth status *> $null
  if ($LASTEXITCODE -eq 0) { $ghAuth = 'ok' } else { $ghAuth = 'needed' }
}
Write-Log $log "gh-auth=$ghAuth"

Write-Host ''
if ($ready -and $ghAuth -eq 'ok') {
  Write-Ok 'READY: tools present and gh authenticated. Remaining steps are the interactive ones below.'
} else {
  Write-Info 'NOT READY yet - finish the steps below, restart shells, then re-run with -DryRun to confirm.'
}
Write-Info 'Next steps (in order)'
$step = 1
Write-Host "  $step. Fix any WARN above (especially Git Bash PATH) and FULLY restart terminals/IDE/Herdr/agents."; $step++
if ($ghAuth -ne 'ok') {
  Write-Host "  $step. gh auth login   # GitHub CLI auth"; $step++
}
Write-Host "  $step. Vendor auth as needed: claude / codex / grok / herdr (each is interactive)."; $step++
Write-Host "  $step. Open setup/CHECKLIST.md and run the smoke pass (setup/smoke.ps1 or setup/smoke.sh)."; $step++
if ($primary -eq 'pi') {
  Write-Host "  $step. cd `"$($paths.HomeDir)`" ; pi"
  Write-Host '     Approve project trust (or use -e fallback in setup/README.md).'
} else {
  Write-Host "  $step. cd `"$($paths.HomeDir)`" ; claude"
  Write-Host '     Folder trust, then bypass-permissions (Down+Enter if default is No/exit).'
}
$step++
Write-Host "  $step. Log file: $log"
Write-Host '  Problems: setup/DEBUG.md'
Write-Log $log "done ready=$ready"
Write-Ok 'Setup script finished.'
exit 0
