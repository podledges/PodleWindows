#!/usr/bin/env bash
# tests/fm-lock-detached-bg.test.sh - foreground-only fleet control for
# detached Claude background jobs (bin/fm-session-lock-lib.sh + bin/fm-lock.sh
# + the fm-spawn herdr preflight).
#
# A daemon-hosted (detached) background job inherits pane identity it can no
# longer prove and stays "live" for as long as its job is open, so it must
# never become the controlling firstmate session and must never attempt herdr
# placement. Everything here drives the real scripts behind a deterministic
# fake ps, in the exact real background-job ancestry shape:
# shell -> session -> pty host (--bg-pty-host) -> daemon (daemon run).
# shellcheck disable=SC2016 # single quotes are deliberate: expansion happens inside the fixture child
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-lock-detached-bg)

LIB="$ROOT/bin/fm-session-lock-lib.sh"

# Run one library expression behind fake process table <fakebin>.
lib_eval() {  # <fakebin> <expression>
  local fakebin=$1 expr=$2
  PATH="$fakebin:$PATH" bash -c "
    . \"\$0\"
    kill() { return 0; }
    $expr
  " "$LIB"
}

# The detached shape: this process climbs to a session (700) hosted by a pty
# host (800) under the shared daemon (600).
make_detached_fakebin() {  # <dir>
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

# The foreground shape: the same session (700) directly under a non-harness
# parent, with no daemon anywhere above it.
make_foreground_fakebin() {  # <dir>
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

test_classifier_tells_detached_from_foreground() {
  local detached foreground
  detached=$(make_detached_fakebin "$TMP_ROOT/classifier-detached")
  foreground=$(make_foreground_fakebin "$TMP_ROOT/classifier-foreground")
  lib_eval "$detached" 'fm_session_is_detached_claude_bg' \
    || fail "a daemon-hosted ancestry was not classified as a detached background job"
  if lib_eval "$foreground" 'fm_session_is_detached_claude_bg'; then
    fail "a foreground pane ancestry was misclassified as a detached background job"
  fi
  pass "detached-bg: the classifier is structural on the shared-host ancestry rows"
}

test_detached_acquire_is_refused_and_foreground_acquires() {
  local dir fakebin out rc
  dir="$TMP_ROOT/acquire-detached"
  fakebin=$(make_detached_fakebin "$dir")
  mkdir -p "$dir/state"
  out=$(PATH="$fakebin:$PATH" FM_STATE_OVERRIDE="$dir/state" "$ROOT/bin/fm-lock.sh" 2>&1)
  rc=$?
  expect_code 1 "$rc" "a detached background job must be refused fleet control"
  assert_contains "$out" "fleet control is foreground-only" \
    "the refusal did not name the foreground-only rule"
  assert_contains "$out" "foreground Claude pane" \
    "the refusal did not route the captain back to the foreground pane"
  [ ! -e "$dir/state/.lock" ] || fail "a refused acquire still wrote the session lock"

  dir="$TMP_ROOT/acquire-foreground"
  fakebin=$(make_foreground_fakebin "$dir")
  mkdir -p "$dir/state"
  out=$(PATH="$fakebin:$PATH" FM_STATE_OVERRIDE="$dir/state" "$ROOT/bin/fm-lock.sh" 2>&1)
  rc=$?
  expect_code 0 "$rc" "a foreground pane session must still acquire normally"
  [ "$(tr -d '[:space:]' < "$dir/state/.lock")" = 700 ] \
    || fail "the foreground acquire did not record the session pid 700"
  pass "detached-bg: acquire refuses detached jobs and stays open to foreground sessions"
}

test_override_still_records_the_session_pid() {
  local dir fakebin rc
  dir="$TMP_ROOT/acquire-override"
  fakebin=$(make_detached_fakebin "$dir")
  mkdir -p "$dir/state"
  PATH="$fakebin:$PATH" FM_STATE_OVERRIDE="$dir/state" FM_ALLOW_DETACHED_FLEET_CONTROL=1 \
    "$ROOT/bin/fm-lock.sh" >/dev/null 2>&1
  rc=$?
  expect_code 0 "$rc" "the deliberate override must let a detached job acquire"
  [ "$(tr -d '[:space:]' < "$dir/state/.lock")" = 700 ] \
    || fail "the override acquire did not record the session pid 700 (never the pty host or daemon)"
  pass "detached-bg: the deliberate override keeps the session-pid write semantics"
}

test_spawn_preflight_is_herdr_only_and_overridable() {
  local detached foreground out
  detached=$(make_detached_fakebin "$TMP_ROOT/preflight-detached")
  foreground=$(make_foreground_fakebin "$TMP_ROOT/preflight-foreground")
  out=$(lib_eval "$detached" 'fm_session_refuse_detached_herdr_spawn herdr' 2>&1) \
    && fail "a detached job's herdr spawn passed preflight"
  assert_contains "$out" "herdr placement is foreground-only" \
    "the spawn refusal did not name the foreground-only rule"
  lib_eval "$detached" 'fm_session_refuse_detached_herdr_spawn tmux' \
    || fail "the preflight refused a non-herdr backend it does not govern"
  lib_eval "$detached" 'FM_ALLOW_DETACHED_FLEET_CONTROL=1 fm_session_refuse_detached_herdr_spawn herdr' \
    || fail "the deliberate override did not pass the spawn preflight"
  lib_eval "$foreground" 'fm_session_refuse_detached_herdr_spawn herdr' \
    || fail "a foreground pane session was refused herdr spawn preflight"
  pass "detached-bg: the spawn preflight refuses only detached herdr placement"
}

test_classifier_tells_detached_from_foreground
test_detached_acquire_is_refused_and_foreground_acquires
test_override_still_records_the_session_pid
test_spawn_preflight_is_herdr_only_and_overridable
