#!/usr/bin/env bash
# tests/fm-lock-detached-bg.test.sh - foreground-only fleet control for
# detached Claude background jobs (bin/fm-session-lock-lib.sh + bin/fm-lock.sh
# + the fm-spawn herdr preflight).
#
# Claude Code 2.1.232+ hosts interactive herdr panes as daemon "spare" workers
# with CLAUDE_JOB_DIR and a --bg-pty-host chain - the same hosting shape true
# background ("fleet") jobs use. Classification is therefore attachment-aware:
# CLAUDE_JOB_DIR / --bg-pty-host are hosting evidence only; foreground requires
# live exact pane-attachment proof; roster source=fleet, stale/mismatched pane,
# or no proof stays refused. Everything here drives the real scripts behind
# deterministic fake ps + fake herdr + fixture Claude metadata.
# shellcheck disable=SC2016 # single quotes are deliberate: expansion happens inside the fixture child
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-lock-detached-bg)

LIB="$ROOT/bin/fm-session-lock-lib.sh"

SESSION_ID='abc12345-e5c5-47e2-97c5-ae79ae38f814'
JOB_SHORT='abc12345'
JOB_NAME='herdr firstmate fleet audit'
PANE_ID='wC:pM'
# Attach-client liveness is checked with kill -0; use this test shell's pid so
# the acquire path (which does not stub kill) sees a genuinely live process.
ATTACH_PID=$$

# Run one library expression behind fake process table <fakebin>.
# HOME is pointed at the fixture tree so Claude metadata reads stay sandboxed.
# CLAUDE_JOB_DIR / HERDR_PANE_ID are left to the caller so each case can model
# the real daemon-hosted attach topology or a true background job.
# Ambient session identity and pane env are cleared first: the suite itself may
# run inside a daemon-hosted Claude session whose real CLAUDE_CODE_SESSION_ID /
# HERDR_PANE_ID / CLAUDE_JOB_DIR would otherwise leak into the fixture and
# override the modeled topology (observed: the real session id definitively
# mismatched the fake pane's agent_session and flipped the verdict). Caller
# assignments come after the blanks, so each case still sets what it models.
lib_eval() {  # <fakebin> <home> <expression> [env assignments...]
  local fakebin=$1 home=$2 expr=$3
  shift 3
  env -u CLAUDE_CODE_SESSION_ID -u CODEX_COMPANION_SESSION_ID \
    -u CLAUDE_JOB_DIR -u HERDR_PANE_ID -u CLAUDE_CONFIG_DIR \
    HOME="$home" PATH="$fakebin:$PATH" "$@" bash -c "
    . \"\$0\"
    kill() { return 0; }
    $expr
  " "$LIB"
}

# Daemon-hosted ancestry: shell -> session (700) -> pty host (800) -> daemon (600).
# This shape is shared by interactive spare workers AND true fleet jobs.
make_daemon_hosted_fakebin() {  # <dir>
  local fakebin
  fakebin=$(fm_fakebin "$1")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field" in
  700:comm=) printf '%s\n' claude ;;
  700:args=) printf '%s\n' 'claude --session-id abc12345-e5c5-47e2-97c5-ae79ae38f814 --agent claude' ;;
  700:ppid=) printf '%s\n' 800 ;;
  800:comm=) printf '%s\n' claude ;;
  800:args=) printf '%s\n' 'claude --bg-pty-host pipe 49 37 -- claude' ;;
  800:ppid=) printf '%s\n' 600 ;;
  600:comm=) printf '%s\n' claude ;;
  600:args=) printf '%s\n' 'claude daemon run --origin transient' ;;
  600:ppid=) printf '%s\n' 1 ;;
  *:comm=) printf '%s\n' bash ;;
  *:args=) printf '%s\n' bash ;;
  *:ppid=) printf '%s\n' 700 ;;
esac
SH
  chmod +x "$fakebin/ps"
  printf '%s\n' "$fakebin"
}

# Legacy direct foreground: session (700) under a non-harness parent, no daemon.
make_legacy_foreground_fakebin() {  # <dir>
  local fakebin
  fakebin=$(fm_fakebin "$1")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field" in
  700:comm=) printf '%s\n' claude ;;
  700:args=) printf '%s\n' 'claude --session-id abc123 --agent claude' ;;
  700:ppid=) printf '%s\n' 1 ;;
  *:comm=) printf '%s\n' bash ;;
  *:args=) printf '%s\n' bash ;;
  *:ppid=) printf '%s\n' 700 ;;
esac
SH
  chmod +x "$fakebin/ps"
  printf '%s\n' "$fakebin"
}

# Fixture Claude home: roster + job state (+ optional sessions registry).
# source is "spare" (interactive) or "fleet" (true background).
make_claude_home() {  # <dir> <source>
  local home=$1 source=$2
  mkdir -p "$home/.claude/jobs/$JOB_SHORT" "$home/.claude/daemon" "$home/.claude/sessions"
  cat > "$home/.claude/daemon/roster.json" <<EOF
{
  "proto": 1,
  "workers": {
    "$JOB_SHORT": {
      "pid": 40388,
      "sessionId": "$SESSION_ID",
      "dispatch": {
        "short": "$JOB_SHORT",
        "sessionId": "$SESSION_ID",
        "source": "$source"
      }
    }
  }
}
EOF
  cat > "$home/.claude/jobs/$JOB_SHORT/state.json" <<EOF
{
  "sessionId": "$SESSION_ID",
  "resumeSessionId": "$SESSION_ID",
  "daemonShort": "$JOB_SHORT",
  "name": "$JOB_NAME",
  "backend": "daemon"
}
EOF
  cat > "$home/.claude/sessions/14460.json" <<EOF
{
  "pid": 14460,
  "sessionId": "$SESSION_ID",
  "jobId": "$JOB_SHORT",
  "kind": "bg",
  "name": "$JOB_NAME",
  "status": "busy"
}
EOF
  printf '%s\n' "$home"
}

# Fake herdr. Modes:
#   match     - live pane, agent_session.value == SESSION_ID, live attach pid
#   title     - live pane, no agent_session, title == JOB_NAME (fallback path)
#   mismatch  - live pane, agent_session.value == other session
#   gone      - pane get fails (stale / closed)
#   otherfg   - live pane, FG cmdline names a different session id
make_herdr_fakebin() {  # <fakebin_dir> <mode>
  local fakebin=$1 mode=$2
  cat > "$fakebin/herdr" <<EOF
#!/usr/bin/env bash
set -u
mode='$mode'
session_id='$SESSION_ID'
job_name='$JOB_NAME'
pane_id='$PANE_ID'
attach_pid='$ATTACH_PID'
other_sid='ffff9999-0000-0000-0000-000000000001'

# Usage shapes we emit:
#   herdr pane get <pane_id>
#   herdr pane process-info --pane <pane_id>
if [ "\${1:-}" = pane ] && [ "\${2:-}" = get ]; then
  target=\${3:-}
  if [ "\$mode" = gone ]; then
    echo "error: pane not found" >&2
    exit 1
  fi
  if [ "\$target" != "\$pane_id" ]; then
    echo "error: pane not found" >&2
    exit 1
  fi
  case "\$mode" in
    match|matchbadargv)
      cat <<JSON
{"id":"cli:pane:get","result":{"pane":{"pane_id":"\$pane_id","agent":"claude","agent_status":"working","terminal_title_stripped":"\$job_name","agent_session":{"source":"herdr:claude","agent":"claude","kind":"id","value":"\$session_id"}},"type":"pane_info"}}
JSON
      ;;
    title|titlebadargv)
      cat <<JSON
{"id":"cli:pane:get","result":{"pane":{"pane_id":"\$pane_id","agent":"claude","agent_status":"working","terminal_title_stripped":"\$job_name"},"type":"pane_info"}}
JSON
      ;;
    mismatch)
      cat <<JSON
{"id":"cli:pane:get","result":{"pane":{"pane_id":"\$pane_id","agent":"claude","agent_status":"working","terminal_title_stripped":"other session","agent_session":{"source":"herdr:claude","agent":"claude","kind":"id","value":"\$other_sid"}},"type":"pane_info"}}
JSON
      ;;
    otherfg|matchbadargv|titlebadargv)
      cat <<JSON
{"id":"cli:pane:get","result":{"pane":{"pane_id":"\$pane_id","agent":"claude","agent_status":"working","terminal_title_stripped":"other"},"type":"pane_info"}}
JSON
      ;;
    *)
      cat <<JSON
{"id":"cli:pane:get","result":{"pane":{"pane_id":"\$pane_id","agent":"claude","agent_status":"working","terminal_title_stripped":"\$job_name","agent_session":{"source":"herdr:claude","agent":"claude","kind":"id","value":"\$session_id"}},"type":"pane_info"}}
JSON
      ;;
  esac
  exit 0
fi

if [ "\${1:-}" = pane ] && [ "\${2:-}" = process-info ]; then
  target=
  shift 2
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      --pane) target=\$2; shift 2 ;;
      *) shift ;;
    esac
  done
  if [ "\$mode" = gone ]; then
    exit 1
  fi
  case "\$mode" in
    otherfg|matchbadargv|titlebadargv)
      cat <<JSON
{"id":"cli:pane:process_info","result":{"process_info":{"pane_id":"\$pane_id","foreground_processes":[{"pid":\$attach_pid,"name":"claude.exe","cmdline":"claude --session-id \$other_sid --agent claude","argv0":"claude"}]},"type":"pane_process_info"}}
JSON
      ;;
    *)
      cat <<JSON
{"id":"cli:pane:process_info","result":{"process_info":{"pane_id":"\$pane_id","foreground_processes":[{"pid":\$attach_pid,"name":"claude.exe","cmdline":"claude.exe","argv0":"claude.exe"}]},"type":"pane_process_info"}}
JSON
      ;;
  esac
  exit 0
fi

echo "error: unexpected herdr invocation: \$*" >&2
exit 1
EOF
  chmod +x "$fakebin/herdr"
}

job_dir_for() {  # <home>
  printf '%s\n' "$1/.claude/jobs/$JOB_SHORT"
}

# (a) daemon-hosted + CLAUDE_JOB_DIR + --bg-pty-host + live exact attachment → ALLOWED

# Corrected-contract negatives: attachment authority requires a positively
# parsed, identity-consistent, non-fleet roster entry and contradiction-free
# pane evidence; a present-but-empty hosting marker is ambiguity, not legacy.
test_roster_and_contradiction_negatives() {
  local home fakebin job_dir
  home=$(make_claude_home "$TMP_ROOT/roster-absent" spare)
  rm -f "$home/.claude/daemon/roster.json"
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/roster-absent-bin")
  make_herdr_fakebin "$fakebin" match
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "absent roster granted attachment authority"

  home=$(make_claude_home "$TMP_ROOT/roster-junk" spare)
  printf 'not json\n' > "$home/.claude/daemon/roster.json"
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/roster-junk-bin")
  make_herdr_fakebin "$fakebin" match
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "malformed roster granted attachment authority"

  home=$(make_claude_home "$TMP_ROOT/roster-unknown" mystery)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/roster-unknown-bin")
  make_herdr_fakebin "$fakebin" match
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "unknown roster source granted attachment authority"

  home=$(make_claude_home "$TMP_ROOT/roster-inconsistent" spare)
  sed -i "s/$SESSION_ID/ffff9999-0000-0000-0000-000000000001/g" \
    "$home/.claude/daemon/roster.json"
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/roster-inconsistent-bin")
  make_herdr_fakebin "$fakebin" match
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "identity-inconsistent roster granted attachment authority"

  home=$(make_claude_home "$TMP_ROOT/argv-contra" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/argv-contra-bin")
  make_herdr_fakebin "$fakebin" matchbadargv
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "matching agent_session with contradictory attach argv authorized"

  make_herdr_fakebin "$fakebin" titlebadargv
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "title match with contradictory attach argv authorized"

  home=$(make_claude_home "$TMP_ROOT/empty-marker" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/empty-marker-bin")
  make_herdr_fakebin "$fakebin" match
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR= HERDR_PANE_ID="$PANE_ID" \
    || fail "present-but-empty CLAUDE_JOB_DIR classified legacy/foreground"

  pass "detached-bg: broken-roster, contradiction, and empty-marker cases refuse"
}

test_daemon_hosted_with_live_attachment_is_foreground() {
  local home fakebin job_dir
  home=$(make_claude_home "$TMP_ROOT/attach-match" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/attach-match-bin")
  make_herdr_fakebin "$fakebin" match
  job_dir=$(job_dir_for "$home")

  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    && fail "daemon-hosted session with live exact attachment was classified detached"

  # title-fallback path (no agent_session) also allows when name matches
  make_herdr_fakebin "$fakebin" title
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    && fail "daemon-hosted session with title-matched live attachment was classified detached"

  pass "detached-bg: daemon-hosted + live exact pane attachment classifies foreground"
}

# (b) identical topology with source fleet OR no attachment proof → REFUSED
test_fleet_source_or_no_attachment_is_detached() {
  local home fakebin job_dir dir out rc

  # source=fleet even with a matching pane → refused
  home=$(make_claude_home "$TMP_ROOT/fleet-src" fleet)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/fleet-src-bin")
  make_herdr_fakebin "$fakebin" match
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "roster source=fleet must classify detached even with a live pane"

  # spare source but no HERDR_PANE_ID → refused
  home=$(make_claude_home "$TMP_ROOT/no-pane" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/no-pane-bin")
  make_herdr_fakebin "$fakebin" match
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" \
    || fail "daemon-hosted session without HERDR_PANE_ID must classify detached"

  # acquire path refuses
  dir="$TMP_ROOT/fleet-acquire"
  mkdir -p "$dir/state"
  out=$(env -u CLAUDE_CODE_SESSION_ID -u CODEX_COMPANION_SESSION_ID -u CLAUDE_CONFIG_DIR -u HERDR_PANE_ID -u CLAUDE_JOB_DIR HOME="$home" CLAUDE_JOB_DIR="$job_dir" PATH="$fakebin:$PATH" \
    FM_STATE_OVERRIDE="$dir/state" "$ROOT/bin/fm-lock.sh" 2>&1) || rc=$?
  rc=${rc:-0}
  expect_code 1 "$rc" "a no-attachment daemon-hosted job must be refused fleet control"
  assert_contains "$out" "fleet control is foreground-only" \
    "the refusal did not name the foreground-only rule"
  [ ! -e "$dir/state/.lock" ] || fail "a refused acquire still wrote the session lock"

  pass "detached-bg: source=fleet or missing attachment proof classifies detached"
}

# (c) stale/inherited HERDR_PANE_ID (pane gone) → REFUSED
test_stale_pane_is_detached() {
  local home fakebin job_dir
  home=$(make_claude_home "$TMP_ROOT/stale-pane" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/stale-pane-bin")
  make_herdr_fakebin "$fakebin" gone
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "stale HERDR_PANE_ID (pane gone) must classify detached"
  pass "detached-bg: stale/gone HERDR_PANE_ID classifies detached"
}

# (d) pane/session identity mismatch → REFUSED
test_identity_mismatch_is_detached() {
  local home fakebin job_dir
  home=$(make_claude_home "$TMP_ROOT/mismatch" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/mismatch-bin")
  make_herdr_fakebin "$fakebin" mismatch
  job_dir=$(job_dir_for "$home")
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "agent_session identity mismatch must classify detached"

  make_herdr_fakebin "$fakebin" otherfg
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "foreground argv bound to another session must classify detached"

  pass "detached-bg: pane/session identity mismatch classifies detached"
}

# (e) legacy direct foreground, no CLAUDE_JOB_DIR → ALLOWED
test_legacy_direct_foreground_is_allowed() {
  local home fakebin dir out rc
  home=$(make_claude_home "$TMP_ROOT/legacy-fg" spare)
  fakebin=$(make_legacy_foreground_fakebin "$TMP_ROOT/legacy-fg-bin")
  # no herdr needed; no CLAUDE_JOB_DIR
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    && fail "legacy direct foreground was misclassified as detached"

  dir="$TMP_ROOT/legacy-acquire"
  mkdir -p "$dir/state"
  out=$(env -u CLAUDE_CODE_SESSION_ID -u CODEX_COMPANION_SESSION_ID -u CLAUDE_CONFIG_DIR -u HERDR_PANE_ID -u CLAUDE_JOB_DIR HOME="$home" PATH="$fakebin:$PATH" \
    FM_STATE_OVERRIDE="$dir/state" "$ROOT/bin/fm-lock.sh" 2>&1)
  rc=$?
  expect_code 0 "$rc" "a legacy foreground pane session must still acquire normally"
  [ "$(tr -d '[:space:]' < "$dir/state/.lock")" = 700 ] \
    || fail "the foreground acquire did not record the session pid 700"
  pass "detached-bg: legacy direct foreground (no CLAUDE_JOB_DIR) is allowed"
}

# Daemon-hosted with live attachment acquires the lock.
test_attached_daemon_hosted_acquires() {
  local home fakebin job_dir dir out rc
  home=$(make_claude_home "$TMP_ROOT/attach-acquire" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/attach-acquire-bin")
  make_herdr_fakebin "$fakebin" match
  job_dir=$(job_dir_for "$home")
  dir="$TMP_ROOT/attach-acquire-state"
  mkdir -p "$dir/state"
  out=$(env -u CLAUDE_CODE_SESSION_ID -u CODEX_COMPANION_SESSION_ID -u CLAUDE_CONFIG_DIR -u HERDR_PANE_ID -u CLAUDE_JOB_DIR HOME="$home" CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    PATH="$fakebin:$PATH" FM_STATE_OVERRIDE="$dir/state" \
    "$ROOT/bin/fm-lock.sh" 2>&1)
  rc=$?
  expect_code 0 "$rc" "a daemon-hosted session with live attachment must acquire"
  [ "$(tr -d '[:space:]' < "$dir/state/.lock")" = 700 ] \
    || fail "attached acquire did not record session pid 700 (got: $(cat "$dir/state/.lock" 2>/dev/null))"
  pass "detached-bg: attached daemon-hosted session acquires the fleet lock"
}

test_override_still_records_the_session_pid() {
  local home fakebin job_dir dir rc
  home=$(make_claude_home "$TMP_ROOT/override" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/override-bin")
  # no herdr attachment on purpose
  job_dir=$(job_dir_for "$home")
  dir="$TMP_ROOT/override-state"
  mkdir -p "$dir/state"
  env -u CLAUDE_CODE_SESSION_ID -u CODEX_COMPANION_SESSION_ID -u CLAUDE_CONFIG_DIR -u HERDR_PANE_ID -u CLAUDE_JOB_DIR HOME="$home" CLAUDE_JOB_DIR="$job_dir" PATH="$fakebin:$PATH" \
    FM_STATE_OVERRIDE="$dir/state" FM_ALLOW_DETACHED_FLEET_CONTROL=1 \
    "$ROOT/bin/fm-lock.sh" >/dev/null 2>&1
  rc=$?
  expect_code 0 "$rc" "the deliberate override must let a detached job acquire"
  [ "$(tr -d '[:space:]' < "$dir/state/.lock")" = 700 ] \
    || fail "the override acquire did not record the session pid 700 (never the pty host or daemon)"
  pass "detached-bg: the deliberate override keeps the session-pid write semantics"
}

test_spawn_preflight_is_herdr_only_and_overridable() {
  local home fakebin job_dir out
  home=$(make_claude_home "$TMP_ROOT/preflight" spare)
  fakebin=$(make_daemon_hosted_fakebin "$TMP_ROOT/preflight-bin")
  job_dir=$(job_dir_for "$home")
  # detached (no attachment)
  out=$(lib_eval "$fakebin" "$home" 'fm_session_refuse_detached_herdr_spawn herdr' \
    CLAUDE_JOB_DIR="$job_dir" 2>&1) \
    && fail "a detached job's herdr spawn passed preflight"
  assert_contains "$out" "herdr placement is foreground-only" \
    "the spawn refusal did not name the foreground-only rule"
  lib_eval "$fakebin" "$home" 'fm_session_refuse_detached_herdr_spawn tmux' \
    CLAUDE_JOB_DIR="$job_dir" \
    || fail "the preflight refused a non-herdr backend it does not govern"
  lib_eval "$fakebin" "$home" 'FM_ALLOW_DETACHED_FLEET_CONTROL=1 fm_session_refuse_detached_herdr_spawn herdr' \
    CLAUDE_JOB_DIR="$job_dir" \
    || fail "the deliberate override did not pass the spawn preflight"

  # attached → preflight allows
  make_herdr_fakebin "$fakebin" match
  lib_eval "$fakebin" "$home" 'fm_session_refuse_detached_herdr_spawn herdr' \
    CLAUDE_JOB_DIR="$job_dir" HERDR_PANE_ID="$PANE_ID" \
    || fail "an attached daemon-hosted session was refused herdr spawn preflight"

  # legacy foreground
  fakebin=$(make_legacy_foreground_fakebin "$TMP_ROOT/preflight-legacy-bin")
  lib_eval "$fakebin" "$home" 'fm_session_refuse_detached_herdr_spawn herdr' \
    || fail "a legacy foreground pane session was refused herdr spawn preflight"
  pass "detached-bg: the spawn preflight refuses only detached herdr placement"
}

# Hosting evidence without attachment (including the Windows Stop-hook shape:
# CLAUDE_JOB_DIR set, ancestry unreadable / legacy-looking) still refuses.
# This replaces the old "env marker alone proves detachment" framing: the
# marker is hosting evidence, and without attachment proof the session stays
# refused - it does not gain new authority.
test_hosting_evidence_without_attachment_refuses() {
  local home fakebin job_dir
  home=$(make_claude_home "$TMP_ROOT/hosting-only" spare)
  fakebin=$(make_legacy_foreground_fakebin "$TMP_ROOT/hosting-only-bin")
  job_dir=$(job_dir_for "$home")
  # CLAUDE_JOB_DIR set, no HERDR_PANE_ID, ancestry looks like legacy foreground
  # (Windows Stop-hook shape: ancestry unreadable or non-daemon; job dir set).
  lib_eval "$fakebin" "$home" 'fm_session_is_detached_claude_bg' \
    CLAUDE_JOB_DIR="$job_dir" \
    || fail "CLAUDE_JOB_DIR without attachment proof must still refuse"
  pass "detached-bg: hosting evidence without attachment proof still refuses"
}

test_daemon_hosted_with_live_attachment_is_foreground
test_fleet_source_or_no_attachment_is_detached
test_stale_pane_is_detached
test_identity_mismatch_is_detached
test_legacy_direct_foreground_is_allowed
test_attached_daemon_hosted_acquires
test_override_still_records_the_session_pid
test_spawn_preflight_is_herdr_only_and_overridable
test_hosting_evidence_without_attachment_refuses
test_roster_and_contradiction_negatives

# Live-harness guard (live-harness-optin family): exercises the REAL claude
# metadata and herdr binding for the session running this suite. Self-skips
# without the gate; failures name the installed versions so rot is visible.
if [ "${FM_LIVE_CLAUDE_ATTACH:-0}" = 1 ]; then
  if [ -z "${CLAUDE_JOB_DIR:-}" ] || [ -z "${HERDR_PANE_ID:-}" ] \
    || ! command -v herdr >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    fail "FM_LIVE_CLAUDE_ATTACH=1 needs a daemon-hosted claude pane session (CLAUDE_JOB_DIR + HERDR_PANE_ID) with herdr and jq installed"
  fi
  live_versions="claude $(claude --version 2>/dev/null | head -1 || echo unknown), herdr $(herdr --version 2>/dev/null | head -1 || echo unknown)"
  bash -c ". '$LIB'; fm_session_is_detached_claude_bg" \
    && fail "live attached pane session classified detached ($live_versions)"
  env -u HERDR_PANE_ID bash -c ". '$LIB'; fm_session_is_detached_claude_bg" \
    || fail "live session without HERDR_PANE_ID classified foreground ($live_versions)"
  HERDR_PANE_ID=wZ:p9 bash -c ". '$LIB'; fm_session_is_detached_claude_bg" \
    || fail "live session with nonexistent pane classified foreground ($live_versions)"
  pass "detached-bg live: real pane attachment classifies foreground; hidden/stale pane refuses"
else
  printf '# skip: live claude attachment guard (set FM_LIVE_CLAUDE_ATTACH=1 in a daemon-hosted claude pane session)\n'
fi
