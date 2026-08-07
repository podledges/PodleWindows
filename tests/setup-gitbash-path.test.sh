#!/usr/bin/env bash
# setup/ Git Bash-over-WSL PATH footgun: installer warns on WSL bash, goes green on Git bash.
#
# Acceptance for issue #4 — simulate a bad PATH inside this process only.
# Never edits the machine user/system PATH.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$ROOT/setup/install.sh"
INSTALL_PS1="$ROOT/setup/install.ps1"
CHECKLIST="$ROOT/setup/CHECKLIST.md"
DEBUG="$ROOT/setup/DEBUG.md"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_file_contains() {
  local file=$1 needle=$2 label=$3
  grep -Fq "$needle" "$file" || fail "$label (missing '$needle' in $file)"
}

assert_re_match() {
  local text=$1 pattern=$2 label=$3
  printf '%s' "$text" | grep -Eq "$pattern" || fail "$label (pattern /$pattern/ not in output)"
}

assert_re_not_match() {
  local text=$1 pattern=$2 label=$3
  if printf '%s' "$text" | grep -Eq "$pattern"; then
    fail "$label (unexpected /$pattern/ in output)"
  fi
}

# --- docs contract -----------------------------------------------------------

test_docs_cover_fix_and_checklist() {
  assert_file_contains "$DEBUG" "Git Bash must beat WSL" "DEBUG has PATH footgun section"
  assert_file_contains "$DEBUG" "Fully restart" "DEBUG requires full restart"
  assert_file_contains "$DEBUG" "Herdr" "DEBUG names Herdr among processes that cache PATH"
  assert_file_contains "$DEBUG" "System32" "DEBUG names System32 bash launcher"
  assert_file_contains "$DEBUG" "CHECKLIST.md §A1" "DEBUG points at CHECKLIST verification"

  assert_file_contains "$CHECKLIST" "which bash" "CHECKLIST has which bash step"
  assert_file_contains "$CHECKLIST" "where.exe bash" "CHECKLIST has where.exe bash step"
  grep -Fq 'C:\Program Files\Git\usr\bin\bash.exe' "$CHECKLIST" \
    || fail "CHECKLIST shows expected Git Bash Windows path shape"
  grep -Fq 'System32\bash.exe' "$CHECKLIST" \
    || fail "CHECKLIST shows the failing System32 path shape to reject"
  assert_file_contains "$CHECKLIST" "fully restarted" "CHECKLIST requires full restart after PATH fix"

  pass "DEBUG and CHECKLIST document the PATH footgun end-to-end"
}

# --- PATH simulation helpers -------------------------------------------------

make_fake_bash_tree() {
  # $1 root — creates System32/bash(.exe) and Git/usr/bin/bash(.exe)
  local root=$1
  mkdir -p "$root/System32" "$root/Git/usr/bin"
  for dir in System32 Git/usr/bin; do
    printf '#!/bin/sh\nexit 0\n' >"$root/$dir/bash"
    printf '#!/bin/sh\nexit 0\n' >"$root/$dir/bash.exe"
    chmod +x "$root/$dir/bash" "$root/$dir/bash.exe"
  done
}

run_install_sh() {
  # Runs install.sh dry-run with a caller-supplied PATH prefix. Non-interactive.
  # Invoke the real Git Bash interpreter by absolute path so the shebang does
  # not pick up the fake WSL bash we deliberately put first on PATH.
  local path_prefix=$1
  local out real_bash
  real_bash=$(command -v -p bash 2>/dev/null || true)
  if [[ -z "$real_bash" || "$real_bash" == */System32/* ]]; then
    real_bash=/usr/bin/bash
  fi
  [[ -x "$real_bash" ]] || real_bash=$(type -P bash)
  out=$(
    PATH="$path_prefix:$PATH" \
      "$real_bash" "$INSTALL_SH" --dry-run --primary=pi --skip-npm-install </dev/null 2>&1
  ) || true
  printf '%s' "$out"
}

# --- install.sh: bad then good PATH -----------------------------------------

test_install_sh_warns_when_wsl_bash_wins() {
  local tmp out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/setup-gitbash-bad.XXXXXX") || fail "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  make_fake_bash_tree "$tmp"

  out=$(run_install_sh "$tmp/System32")
  assert_re_match "$out" 'WARN:.*(WSL/store shadow|Windows PATH resolves bash)' \
    "install.sh should WARN when System32 bash wins PATH"
  assert_re_match "$out" 'DEBUG\.md' \
    "install.sh WARN should point at DEBUG.md"
  assert_re_match "$out" 'System32' \
    "install.sh WARN should mention the System32 path"
  assert_re_not_match "$out" 'OK: bash \(Windows PATH\):.*System32' \
    "install.sh must not OK a System32 bash as Git-friendly"

  pass "install.sh warns when WSL/System32 bash wins PATH"
}

test_install_sh_ok_when_git_bash_wins() {
  local tmp out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/setup-gitbash-good.XXXXXX") || fail "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  make_fake_bash_tree "$tmp"

  # Git fake first, System32 still present later — proves order matters.
  out=$(run_install_sh "$tmp/Git/usr/bin:$tmp/System32")
  assert_re_match "$out" 'OK: bash' \
    "install.sh should OK when Git bash wins PATH"
  assert_re_not_match "$out" 'WARN:.*WSL/store shadow' \
    "install.sh must not WARN WSL shadow when Git bash is first"
  assert_re_not_match "$out" 'WARN:.*Windows PATH resolves bash' \
    "install.sh must not WARN Windows PATH when Git bash is first"

  pass "install.sh goes green when Git bash wins PATH"
}

# --- install.ps1: bad then good PATH ----------------------------------------

test_install_ps1_warns_and_recovers() {
  command -v powershell.exe >/dev/null 2>&1 \
    || { pass "install.ps1 checks skipped (no powershell.exe)"; return 0; }

  local tmp tmp_win ps_script out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/setup-gitbash-ps.XXXXXX") || fail "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  make_fake_bash_tree "$tmp"

  if command -v cygpath >/dev/null 2>&1; then
    tmp_win=$(cygpath -w "$tmp")
  else
    tmp_win=$tmp
  fi

  ps_script="$tmp/run-bash-check.ps1"
  # Extract the real detector functions from install.ps1 into a tiny driver.
  # Full install.ps1 prompts; we unit-check Test-BashIsGitFriendly under PATH control.
  {
    printf '%s\n' "\$ErrorActionPreference = 'Stop'"
    sed -n '/^function Test-BashPathIsWslShadow/,/^}/p' "$INSTALL_PS1"
    sed -n '/^function Test-BashIsGitFriendly/,/^}/p' "$INSTALL_PS1"
    cat <<'PSEOF'
$root = $args[0]
$bad = Join-Path $root 'System32'
$good = Join-Path $root 'Git\usr\bin'
$saved = $env:PATH

try {
  $env:PATH = "$bad;$saved"
  $r = Test-BashIsGitFriendly
  if ($r.Ok) { Write-Output "FAIL-bad-ok:$($r.Detail)"; exit 2 }
  if ($r.Detail -notmatch 'WSL/store shadow') { Write-Output "FAIL-bad-detail:$($r.Detail)"; exit 3 }
  Write-Output "bad:$($r.Detail)"

  $env:PATH = "$good;$bad;$saved"
  $r = Test-BashIsGitFriendly
  if (-not $r.Ok) { Write-Output "FAIL-good-not-ok:$($r.Detail)"; exit 4 }
  if ($r.Detail -match 'System32') { Write-Output "FAIL-good-system32:$($r.Detail)"; exit 5 }
  Write-Output "good:$($r.Detail)"
  exit 0
} finally {
  $env:PATH = $saved
}
PSEOF
  } >"$ps_script"
  grep -q '^function Test-BashPathIsWslShadow' "$ps_script" \
    || fail "could not extract Test-BashPathIsWslShadow from install.ps1"
  grep -q '^function Test-BashIsGitFriendly' "$ps_script" \
    || fail "could not extract Test-BashIsGitFriendly from install.ps1"

  out=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps_script" "$tmp_win" 2>&1) || true
  assert_re_match "$out" 'bad:.*WSL/store shadow' \
    "install.ps1 detector should flag System32-first PATH ($out)"
  assert_re_match "$out" 'good:' \
    "install.ps1 detector should accept Git-first PATH ($out)"
  assert_re_not_match "$out" 'FAIL-' \
    "install.ps1 detector simulation should not report FAIL ($out)"

  pass "install.ps1 detector warns on WSL-first PATH and goes green after Git-first reorder"
}

# --- pattern parity: install.sh function vs known shapes --------------------

test_detector_pattern_shapes() {
  # Source just the detector by extracting and eval'ing the function from install.sh
  local tmp snippet
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/setup-gitbash-pat.XXXXXX") || fail "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  snippet="$tmp/det.sh"
  # Extract bash_path_is_wsl_shadow function body from install.sh
  sed -n '/^bash_path_is_wsl_shadow()/,/^}/p' "$INSTALL_SH" >"$snippet"
  grep -q 'bash_path_is_wsl_shadow' "$snippet" || fail "could not extract bash_path_is_wsl_shadow from install.sh"
  # shellcheck disable=SC1090
  . "$snippet"

  bash_path_is_wsl_shadow '/c/Windows/System32/bash.exe' \
    || fail "should flag /c/Windows/System32/bash.exe"
  bash_path_is_wsl_shadow 'C:\Windows\System32\bash.exe' \
    || fail "should flag C:\\Windows\\System32\\bash.exe"
  bash_path_is_wsl_shadow 'C:\Windows\SysWOW64\bash.exe' \
    || fail "should flag SysWOW64 bash.exe"
  bash_path_is_wsl_shadow 'C:\Program Files\WindowsApps\Something\bash.exe' \
    || fail "should flag WindowsApps bash"
  bash_path_is_wsl_shadow 'C:\Windows\System32\wsl.exe' \
    || fail "should flag wsl.exe"
  bash_path_is_wsl_shadow '/usr/bin/bash' \
    && fail "must NOT flag /usr/bin/bash"
  bash_path_is_wsl_shadow 'C:\Program Files\Git\usr\bin\bash.exe' \
    && fail "must NOT flag Git usr\\bin\\bash.exe"
  bash_path_is_wsl_shadow 'C:\Program Files\Git\bin\bash.exe' \
    && fail "must NOT flag Git bin\\bash.exe"

  pass "bash_path_is_wsl_shadow matches WSL shapes and spares Git Bash shapes"
}

# --- run ---------------------------------------------------------------------

test_docs_cover_fix_and_checklist
test_detector_pattern_shapes
test_install_sh_warns_when_wsl_bash_wins
test_install_sh_ok_when_git_bash_wins
test_install_ps1_warns_and_recovers

printf 'All setup-gitbash-path tests passed.\n'
