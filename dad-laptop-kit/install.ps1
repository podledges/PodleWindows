# dad-laptop-kit installer (PowerShell 5.1+)
# Installs the user-level PODLES pieces that the main setup kit (setup/install.ps1)
# does NOT cover: go-next + i-have-adhd skills, the ADHD auto-start hook,
# herdr-fleet-ui (banner + Claude statusline), podle-scribe, pi-grok wrapper,
# PODLES home config (claude primary / pi-on-grok crew / herdr backend), and
# the ObbyVault seed.
#
# Run AFTER cloning/copying the firstmate home, from anywhere:
#   powershell -ExecutionPolicy Bypass -File .\dad-laptop-kit\install.ps1
#
# Flags:
#   -FmHome <path>   firstmate home root (default: parent folder of this kit)
#   -DryRun          print actions only
#   -Force           overwrite existing config/skill files (default: skip existing)
param(
    [string]$FmHome = "",
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Kit = $PSScriptRoot
if ($FmHome -eq "") { $FmHome = Split-Path -Parent $Kit }
if (-not (Test-Path (Join-Path $FmHome "AGENTS.md"))) {
    Write-Host "ERROR: '$FmHome' does not look like a firstmate home (no AGENTS.md). Pass -FmHome." -ForegroundColor Red
    exit 1
}

$UserHome    = $env:USERPROFILE
$ClaudeDir   = Join-Path $UserHome ".claude"
$FleetUiDir  = Join-Path $UserHome ".herdr-fleet-ui"
$ProjectsWin = Join-Path $FmHome "PODLEPROJECTS"

# Placeholder values baked into templated files (Git Bash /c/... form).
$drive = $FmHome.Substring(0,1).ToLower()
$FmHomePosix = "/" + $drive + ($FmHome.Substring(2) -replace "\\", "/")

function Copy-Kit([string]$Src, [string]$Dst, [bool]$Template) {
    if ((Test-Path $Dst) -and (-not $Force)) {
        Write-Host "  skip (exists): $Dst"
        return
    }
    if ($DryRun) { Write-Host "  would write: $Dst"; return }
    $dir = Split-Path -Parent $Dst
    New-Item -ItemType Directory -Force $dir | Out-Null
    if ($Template) {
        $t = [System.IO.File]::ReadAllText($Src)
        $t = $t.Replace("__FM_HOME_WIN__", $FmHome)
        $t = $t.Replace("__FM_HOME_POSIX__", $FmHomePosix)
        $t = $t.Replace("__PROJECTS_WIN__", $ProjectsWin)
        [System.IO.File]::WriteAllText($Dst, $t)
    } else {
        Copy-Item $Src $Dst -Force
    }
    Write-Host "  wrote: $Dst" -ForegroundColor Green
}

Write-Host "dad-laptop-kit install" -ForegroundColor Cyan
Write-Host "  firstmate home : $FmHome"
Write-Host "  posix form     : $FmHomePosix"
Write-Host "  projects dir   : $ProjectsWin"
Write-Host ""

Write-Host "[1/6] Skills -> $ClaudeDir\skills"
Copy-Kit (Join-Path $Kit "user-claude\skills\go-next\SKILL.md")    (Join-Path $ClaudeDir "skills\go-next\SKILL.md")    $true
Copy-Kit (Join-Path $Kit "user-claude\skills\i-have-adhd\SKILL.md") (Join-Path $ClaudeDir "skills\i-have-adhd\SKILL.md") $false

Write-Host "[2/6] Hooks -> $ClaudeDir\hooks"
Copy-Kit (Join-Path $Kit "user-claude\hooks\adhd-autostart.sh") (Join-Path $ClaudeDir "hooks\adhd-autostart.sh") $false

Write-Host "[3/6] herdr-fleet-ui -> $FleetUiDir"
Get-ChildItem (Join-Path $Kit "herdr-fleet-ui") | ForEach-Object {
    Copy-Kit $_.FullName (Join-Path $FleetUiDir $_.Name) $false
}

Write-Host "[4/6] Firstmate home config -> $FmHome"
Copy-Kit (Join-Path $Kit "home-config\backend")            (Join-Path $FmHome "config\backend")            $false
Copy-Kit (Join-Path $Kit "home-config\crew-harness")       (Join-Path $FmHome "config\crew-harness")       $false
Copy-Kit (Join-Path $Kit "home-config\crew-dispatch.json") (Join-Path $FmHome "config\crew-dispatch.json") $false
Copy-Kit (Join-Path $Kit "config\scribe-prompt.md")        (Join-Path $FmHome "config\scribe-prompt.md")   $false
Copy-Kit (Join-Path $Kit "bin\podle-scribe.sh")            (Join-Path $FmHome "bin\podle-scribe.sh")       $false
Copy-Kit (Join-Path $Kit "bin\pi-grok")                    (Join-Path $FmHome "bin\pi-grok")               $false

Write-Host "[5/6] ObbyVault seed -> $FmHome\ObbyVault"
Copy-Kit (Join-Path $Kit "vault-seed\AGENTS.md") (Join-Path $FmHome "ObbyVault\AGENTS.md") $true
if (-not $DryRun) { New-Item -ItemType Directory -Force $ProjectsWin | Out-Null }

Write-Host "[6/6] ~\.claude\settings.json - ADHD hook + statusline"
$SettingsPath = Join-Path $ClaudeDir "settings.json"
$claudeDirPosix = "/" + $ClaudeDir.Substring(0,1).ToLower() + ($ClaudeDir.Substring(2) -replace "\\","/")
$HookCmd = "bash `"$claudeDirPosix/hooks/adhd-autostart.sh`""
$StatusCmd = "node `"$FleetUiDir\statusline-claude.js`""

if (-not (Test-Path $SettingsPath)) {
    $settings = [ordered]@{
        hooks = @{ SessionStart = @( @{ matcher = "*"; hooks = @( @{ type = "command"; command = $HookCmd; timeout = 15 } ) } ) }
        statusLine = @{ type = "command"; command = $StatusCmd }
    }
    if ($DryRun) { Write-Host "  would create: $SettingsPath" }
    else {
        New-Item -ItemType Directory -Force $ClaudeDir | Out-Null
        $settings | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $SettingsPath
        Write-Host "  wrote: $SettingsPath" -ForegroundColor Green
    }
} else {
    $raw = Get-Content $SettingsPath -Raw
    $needHook   = ($raw -notmatch "adhd-autostart")
    $needStatus = ($raw -notmatch "statusline-claude")
    if (-not $needHook -and -not $needStatus) {
        Write-Host "  settings.json already wired - nothing to do"
    } else {
        Write-Host "  settings.json EXISTS - merge these by hand (kit will not rewrite a live settings file):" -ForegroundColor Yellow
        if ($needHook) {
            Write-Host '    hooks.SessionStart += { "matcher": "*", "hooks": [ { "type": "command", "command": "' -NoNewline
            Write-Host $HookCmd -NoNewline
            Write-Host '", "timeout": 15 } ] }'
        }
        if ($needStatus) {
            Write-Host '    statusLine = { "type": "command", "command": "' -NoNewline
            Write-Host ($StatusCmd -replace "\\","\\") -NoNewline
            Write-Host '" }'
        }
    }
}

Write-Host ""
Write-Host "Done. Next: run the MAIN setup kit if you haven't yet:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$FmHome\setup\install.ps1`" -Primary claude"
Write-Host "Then work through dad-laptop-kit\README.md sections 4-7 (auth + smoke)."
