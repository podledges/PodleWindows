#!/usr/bin/env bash
# PODLES Firstmate setup bootstrap — Windows Git Bash only.
# Discovers firstmate home as parent of this script's directory.
# No hardcoded user profile paths. No secrets.
set -euo pipefail

DRY_RUN=0
PRIMARY=""
APPLY_CONFIG=0
SKIP_NPM=0
YES=0

usage() {
  cat <<'EOF'
Usage: ./setup/install.sh [options]

  --dry-run              Detect only; no installs or config writes
  --primary=pi|claude    Skip primary prompt
  --apply-config         Write config from examples (prompt on overwrite)
  --skip-npm-install     Do not offer npm -g installs
  -y, --yes              Prefer yes on optional non-destructive offers
  -h, --help             Show help

Run from anywhere; home is parent of setup/. Requires AGENTS.md there.
Windows Git Bash only (refuses WSL).
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --primary=pi|--primary=claude) PRIMARY=${arg#--primary=} ;;
    --apply-config) APPLY_CONFIG=1 ;;
    --skip-npm-install) SKIP_NPM=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

log()  { printf '[podles-setup] %s\n' "$*"; }
ok()   { printf '[podles-setup] OK: %s\n' "$*"; }
warn() { printf '[podles-setup] WARN: %s\n' "$*" >&2; }
err()  { printf '[podles-setup] ERROR: %s\n' "$*" >&2; }

# Refuse WSL
if [[ -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]] || uname -r 2>/dev/null | grep -qi microsoft; then
  if [[ "$(uname -s)" == "Linux" ]]; then
    err "This installer is for Windows Git Bash, not WSL. Use Git Bash or install.ps1."
    exit 1
  fi
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
HOME_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
CONFIG_DIR="$HOME_DIR/config"
DATA_DIR="$HOME_DIR/data"
EXAMPLE_DIR="$SCRIPT_DIR/config"
AGENTS_MD="$HOME_DIR/AGENTS.md"

LOG_DIR=${TMPDIR:-${TEMP:-/tmp}}
LOG_FILE="$LOG_DIR/podles-setup-$(date +%Y%m%d-%H%M%S).log"
{
  echo "PODLES setup log $(date -Iseconds 2>/dev/null || date)"
  echo "home=$HOME_DIR setup=$SCRIPT_DIR dry=$DRY_RUN"
} >"$LOG_FILE"
log "Log: $LOG_FILE"

if [[ ! -f "$AGENTS_MD" ]]; then
  err "AGENTS.md not found at $HOME_DIR"
  err "Run inside a firstmate home that contains setup/."
  exit 1
fi
ok "Firstmate home: $HOME_DIR"

# bash identity — WSL/store launcher on PATH is the common Windows footgun.
# Prefer where.exe (true Windows PATH order) when present: Git Bash's own
# command -v is MSYS-prefixed and can hide a WSL-first Windows PATH.
bash_path_is_wsl_shadow() {
  local p
  p=$(printf '%s' "$1" | tr '\\' '/')
  printf '%s' "$p" | grep -Eqi \
    '/System32/bash(\.exe)?$|/SysWOW64/bash(\.exe)?$|/WindowsApps/|/wsl\.exe$|/[Ww]sl/|wslbash'
}

check_bash_identity() {
  local warned=0 bash_path win_bash

  bash_path=$(command -v bash 2>/dev/null || true)
  if [[ -z "$bash_path" ]]; then
    warn "bash not on PATH"
    echo "bash warn: not on PATH" >>"$LOG_FILE"
  elif bash_path_is_wsl_shadow "$bash_path"; then
    warn "bash looks like WSL/store shadow: $bash_path"
    warned=1
  fi

  if command -v where.exe >/dev/null 2>&1; then
    win_bash=$(where.exe bash 2>/dev/null | head -n 1 | tr -d '\r' || true)
    if [[ -n "$win_bash" ]] && bash_path_is_wsl_shadow "$win_bash"; then
      if [[ "$warned" -eq 0 ]]; then
        warn "Windows PATH resolves bash to WSL/store shadow: $win_bash"
      fi
      warned=1
    elif [[ -n "$win_bash" && "$warned" -eq 0 ]]; then
      ok "bash (Windows PATH): $win_bash"
      echo "bash ok: $win_bash" >>"$LOG_FILE"
      return 0
    fi
  fi

  if [[ "$warned" -eq 1 ]]; then
    warn "Move Git for Windows above WSL on PATH, then FULLY restart terminals/IDE/Herdr/agents."
    warn "See setup/DEBUG.md section 1 (Git Bash must beat WSL)."
    echo "bash warn: wsl-shadow${bash_path:+ command-v=$bash_path}${win_bash:+ where=$win_bash}" >>"$LOG_FILE"
    return 1
  fi

  if [[ -n "$bash_path" ]]; then
    ok "bash: $bash_path"
    echo "bash ok: $bash_path" >>"$LOG_FILE"
  fi
  return 0
}

check_bash_identity || true

tool_ver() {
  local name=$1; shift
  if ! command -v "$name" >/dev/null 2>&1; then
    return 1
  fi
  "$name" "$@" 2>&1 | head -n 1 | tr -d '\r'
}

log "Tool detection"
MISSING=()
check_tool() {
  local name=$1; shift
  local ver
  if ver=$(tool_ver "$name" "$@"); then
    ok "$(printf '%-12s %s' "$name" "$ver")"
    echo "tool $name=$ver" >>"$LOG_FILE"
  else
    warn "$(printf '%-12s MISSING' "$name")"
    echo "tool $name=MISSING" >>"$LOG_FILE"
    MISSING+=("$name")
  fi
}

check_tool node -v || true
check_tool npm -v || true
check_tool git --version || true
check_tool gh --version || true
check_tool jq --version || true
check_tool pi --version || true
check_tool claude --version || true
check_tool codex --version || true
check_tool grok --version || true
check_tool herdr --version || true
check_tool treehouse --version || true

# Read-only inspection only. Never adds/removes exclusions.
check_defender_exclusion() {
  if ! command -v powershell.exe >/dev/null 2>&1; then
    printf 'unknown|powershell.exe not found'
    return
  fi
  local out
  out=$(powershell.exe -NoProfile -Command "(Get-MpPreference -ErrorAction Stop | ForEach-Object { \$_.ExclusionPath + \$_.ExclusionProcess }) -join '; '" 2>/dev/null) || {
    printf 'unknown|could not read Defender preferences'
    return
  }
  if printf '%s' "$out" | grep -qi 'no-mistakes'; then
    printf 'present|%s' "$out"
  else
    printf 'absent|no exclusion matching "no-mistakes" found'
  fi
}

ask_yn() {
  # $1 prompt  $2 default_no=1
  local prompt=$1
  local default_no=${2:-1}
  local suffix reply
  if [[ "$default_no" -eq 1 ]]; then suffix='[y/N]'; else suffix='[Y/n]'; fi
  if [[ "$YES" -eq 1 && "$default_no" -eq 0 ]]; then
    return 0
  fi
  read -r -p "$prompt $suffix " reply || true
  reply=$(printf '%s' "${reply:-}" | tr '[:upper:]' '[:lower:]')
  if [[ -z "$reply" ]]; then
    [[ "$default_no" -eq 0 ]]
    return
  fi
  [[ "$reply" == y || "$reply" == yes ]]
}

choose_primary() {
  if [[ -n "$PRIMARY" ]]; then
    printf '%s' "$PRIMARY"
    return
  fi
  echo "" >&2
  echo "Primary agent choice (credits / quota)" >&2
  echo "  Yes = lots of GPT remaining, OR little/no Claude left  -> Pi primary (crew: Grok + GPT/Codex)" >&2
  echo "  No  = Claude usage still available / prefer subscription -> Claude primary (save API credits)" >&2
  echo "" >&2
  local reply
  read -r -p "Do you have a lot of GPT usage remaining, or little/no Claude usage left? [y/N] " reply || true
  reply=$(printf '%s' "${reply:-}" | tr '[:upper:]' '[:lower:]')
  if [[ "$reply" == y || "$reply" == yes ]]; then
    printf 'pi'
  else
    printf 'claude'
  fi
}

echo ""
log "=== no-mistakes install gate (Defender-first — do not skip) ==="
log "Step 1 (REQUIRED FIRST): add a Windows Defender exclusion for no-mistakes.exe / its install directory (admin)."
DEFENDER_RESULT=$(check_defender_exclusion)
DEFENDER_STATUS=${DEFENDER_RESULT%%|*}
DEFENDER_DETAIL=${DEFENDER_RESULT#*|}
case "$DEFENDER_STATUS" in
  present) ok "Defender exclusion detected: $DEFENDER_DETAIL" ;;
  absent) warn "No Defender exclusion for no-mistakes detected yet. Add it now before continuing — see setup/DEBUG.md #3." ;;
  *) warn "Could not verify Defender exclusion ($DEFENDER_DETAIL). Confirm manually before continuing — see setup/DEBUG.md #3." ;;
esac
echo "defender-exclusion=$DEFENDER_STATUS" >>"$LOG_FILE"
log "Step 2 (ONLY AFTER Step 1): install or reinstall no-mistakes."
NM_VER=$(tool_ver no-mistakes --version) || NM_VER=$(tool_ver no-mistakes version) || NM_VER=""
if [[ -n "$NM_VER" ]]; then
  ok "no-mistakes detected: $NM_VER"
  echo "tool no-mistakes=$NM_VER" >>"$LOG_FILE"
else
  warn "no-mistakes not detected on PATH."
  warn "If no-mistakes worked before and is missing now (binary present yesterday, gone today), suspect Defender quarantine: check Get-MpThreatDetection BEFORE reinstalling — see setup/DEBUG.md #3."
  echo "tool no-mistakes=MISSING" >>"$LOG_FILE"
fi
log "Full recovery steps: setup/DEBUG.md #3"

PRIMARY=$(choose_primary)
log "Primary harness choice: $PRIMARY"
echo "primary=$PRIMARY" >>"$LOG_FILE"

if [[ "$SKIP_NPM" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
  NPM_PKGS=()
  for p in gh-axi lavish-axi quota-axi tasks-axi chrome-devtools-axi; do
    command -v "$p" >/dev/null 2>&1 || NPM_PKGS+=("$p")
  done
  if printf '%s\n' "${MISSING[@]+"${MISSING[@]}"}" | grep -qx pi; then
    NPM_PKGS+=('@earendil-works/pi-coding-agent')
  fi
  if printf '%s\n' "${MISSING[@]+"${MISSING[@]}"}" | grep -qx claude; then
    warn "Claude Code missing: install via current Anthropic docs, then re-run."
  fi
  if [[ ${#NPM_PKGS[@]} -gt 0 ]] && command -v npm >/dev/null 2>&1; then
    log "Optional npm globals: ${NPM_PKGS[*]}"
    if ask_yn "Run npm install -g for the packages listed above?" 1; then
      for pkg in "${NPM_PKGS[@]}"; do
        log "npm install -g $pkg"
        npm install -g "$pkg" 2>&1 | tee -a "$LOG_FILE" || warn "npm failed for $pkg"
      done
    fi
  fi
elif [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY: skipped npm install offers"
fi

echo ""
log "Manual installs if MISSING"
echo "  Herdr:     https://herdr.dev"
echo "  Codex:     official Codex CLI"
echo "  Grok:      Grok Build CLI + auth"
echo "  treehouse: firstmate bootstrap or releases"
echo "  gh:        winget install GitHub.cli"
echo "  no-mistakes: see the Defender-first gate above (setup/DEBUG.md #3)"

copy_example() {
  local src=$1 dest=$2
  if [[ ! -f "$src" ]]; then
    warn "Missing example: $src"
    return
  fi
  mkdir -p "$(dirname -- "$dest")"
  if [[ -f "$dest" ]]; then
    if cmp -s "$src" "$dest" 2>/dev/null; then
      ok "Unchanged: $dest"
      return
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY: would prompt overwrite $dest"
      return
    fi
    if ! ask_yn "Overwrite existing $dest ?" 1; then
      log "Kept existing $dest"
      echo "skip overwrite $dest" >>"$LOG_FILE"
      return
    fi
  elif [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY: copy $src -> $dest"
    return
  fi
  cp -- "$src" "$dest"
  ok "Wrote $dest"
  echo "wrote $dest" >>"$LOG_FILE"
}

if [[ "$APPLY_CONFIG" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
  if ask_yn "Apply PODLES config templates into config/ (prompt before overwrite)?" 0; then
    APPLY_CONFIG=1
  fi
fi

if [[ "$APPLY_CONFIG" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
  echo ""
  log "Config templates"
  copy_example "$EXAMPLE_DIR/backend.example" "$CONFIG_DIR/backend"
  if [[ "$PRIMARY" == claude ]]; then
    copy_example "$EXAMPLE_DIR/crew-harness.claude.example" "$CONFIG_DIR/crew-harness"
    copy_example "$EXAMPLE_DIR/crew-dispatch.claude-primary.json.example" "$CONFIG_DIR/crew-dispatch.json"
  else
    copy_example "$EXAMPLE_DIR/crew-harness.example" "$CONFIG_DIR/crew-harness"
    copy_example "$EXAMPLE_DIR/crew-dispatch.json.example" "$CONFIG_DIR/crew-dispatch.json"
  fi
  if [[ ! -f "$DATA_DIR/captain.md" ]]; then
    copy_example "$EXAMPLE_DIR/captain.md.example" "$DATA_DIR/captain.md"
  else
    ok "Left existing data/captain.md in place"
  fi
fi

echo ""
log "Next steps"
echo "  1. Fix WARNs (Git Bash PATH) and FULLY restart shells."
echo "  2. Auth: gh auth login; claude/codex/grok; herdr."
echo "  3. Open setup/CHECKLIST.md"
if [[ "$PRIMARY" == pi ]]; then
  echo "  4. cd \"$HOME_DIR\" && pi   # approve project trust"
else
  echo "  4. cd \"$HOME_DIR\" && claude  # trust + bypass-permissions dialogs"
fi
echo "  5. Log: $LOG_FILE"
echo "  6. Problems: setup/DEBUG.md"
echo "done" >>"$LOG_FILE"
ok "Setup script finished."
