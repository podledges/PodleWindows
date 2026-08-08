#!/usr/bin/env bash
# PODLES setup smoke — post-install verification (issue: setup smoke script).
# Read-only: verifies tool versions against setup/versions.manifest, config
# shape, and the no-hardcoded-user-paths rule. Exit 0 = smoke passed,
# 1 = failures, 2 = usage. Portable: Git Bash on Windows and Linux CI.
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
HOME_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
MANIFEST="$SCRIPT_DIR/versions.manifest"
FAIL=0
WARNED=0

log()  { printf '[podles-smoke] %s\n' "$*"; }
ok()   { printf '[podles-smoke] OK: %s\n' "$*"; }
warn() { printf '[podles-smoke] WARN: %s\n' "$*" >&2; WARNED=1; }
fail() { printf '[podles-smoke] FAIL: %s\n' "$*" >&2; FAIL=1; }

STRICT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;   # WARNs also fail (clean-machine proof runs)
    --manifest)
      # Alternate manifest (tests point this at fixture manifests).
      [ "$#" -gt 1 ] || { echo "--manifest requires a path" >&2; exit 2; }
      MANIFEST=$2; shift 2 ;;
    -h|--help)
      echo "Usage: ./setup/smoke.sh [--strict] [--manifest <path>]"
      echo "Verifies tools vs setup/versions.manifest, config shape, and kit hygiene."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- 1. Home shape ----------------------------------------------------------
[ -f "$HOME_DIR/AGENTS.md" ] && ok "AGENTS.md present" || fail "AGENTS.md missing at $HOME_DIR"
[ -d "$HOME_DIR/bin" ] && ok "bin/ present" || fail "bin/ missing"

# --- 2. Tool versions vs manifest -------------------------------------------
# manifest lines: <tool> <min-version> <required|optional> [version-args...]
ver_ge() {
  # True when $1 >= $2 as dotted numeric versions.
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

extract_version() {
  # First dotted-numeric token in the first line, 'v' prefix tolerated.
  head -n 1 | tr -d '\r' | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1
}

if [ ! -f "$MANIFEST" ]; then
  fail "versions.manifest missing at $MANIFEST"
else
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    tool=$(printf '%s' "$line" | awk '{print $1}')
    min=$(printf '%s' "$line" | awk '{print $2}')
    requirement=$(printf '%s' "$line" | awk '{print $3}')
    args=$(printf '%s' "$line" | awk '{for (i=4; i<=NF; i++) printf "%s ", $i}')
    if ! command -v "$tool" >/dev/null 2>&1; then
      if [ "$requirement" = required ]; then
        fail "$tool missing (required, min $min)"
      else
        warn "$tool missing (optional, min $min)"
      fi
      continue
    fi
    # shellcheck disable=SC2086 # manifest args are intentionally word-split
    got=$("$tool" $args 2>&1 | extract_version || true)
    if [ -z "$got" ]; then
      warn "$tool present but version unreadable"
    elif ver_ge "$got" "$min"; then
      ok "$(printf '%-12s %s (min %s)' "$tool" "$got" "$min")"
    else
      fail "$tool version $got below manifest minimum $min"
    fi
  done < "$MANIFEST"
fi

# --- 3. Config shape --------------------------------------------------------
CONFIG_DIR="$HOME_DIR/config"
if [ -f "$CONFIG_DIR/backend" ]; then
  backend=$(tr -d '[:space:]\r' < "$CONFIG_DIR/backend")
  case "$backend" in
    herdr|tmux|cmux) ok "config/backend = $backend" ;;
    *) fail "config/backend has unexpected value '$backend'" ;;
  esac
else
  warn "config/backend not applied yet (run install with --apply-config)"
fi
if [ -f "$CONFIG_DIR/crew-harness" ]; then
  harness=$(tr -d '[:space:]\r' < "$CONFIG_DIR/crew-harness")
  case "$harness" in
    pi|claude) ok "config/crew-harness = $harness" ;;
    *) fail "config/crew-harness has unexpected value '$harness'" ;;
  esac
else
  warn "config/crew-harness not applied yet"
fi
if [ -f "$CONFIG_DIR/crew-dispatch.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$CONFIG_DIR/crew-dispatch.json" >/dev/null 2>&1; then
      ok "config/crew-dispatch.json is valid JSON"
    else
      fail "config/crew-dispatch.json is not valid JSON"
    fi
  else
    warn "jq missing; skipped crew-dispatch.json validation"
  fi
else
  warn "config/crew-dispatch.json not applied yet"
fi

# --- 4. Kit hygiene: no per-user absolute paths in setup/ -------------------
# Catches C:\Users\<name> and /c/Users/<name> and /Users/<name> style leaks in
# kit files. Examples and docs are covered too: the kit must stay portable.
hits=$(grep -RInE '([A-Za-z]:\\+Users\\+|/[a-z]/Users/|(^|[^A-Za-z])/Users/)[A-Za-z0-9._-]+' \
  "$SCRIPT_DIR" --include='*.sh' --include='*.ps1' --include='*.md' --include='*.example' \
  --include='*.manifest' 2>/dev/null \
  | grep -v 'Users/<' | grep -v 'Users\\\\<' || true)
if [ -n "$hits" ]; then
  fail "hardcoded user-profile paths found in setup/:"
  printf '%s\n' "$hits" | head -10 >&2
else
  ok "no hardcoded user-profile paths in setup/"
fi

# --- 5. Result --------------------------------------------------------------
if [ "$STRICT" -eq 1 ] && [ "$WARNED" -eq 1 ]; then
  fail "strict mode: WARNs present"
fi
if [ "$FAIL" -eq 1 ]; then
  log "SMOKE FAILED"
  exit 1
fi
log "SMOKE PASSED"
