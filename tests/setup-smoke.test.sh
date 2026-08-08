#!/usr/bin/env bash
# Prove setup/smoke.sh verifies a home for real (issue: setup smoke script):
#   - passes on a healthy fake home whose config matches the applied templates
#   - fails when a required manifest tool is missing from PATH
#   - fails when a required tool sits below its manifest version floor
#   - fails on unexpected config values (wrong backend / harness / broken JSON)
#   - fails when a kit file leaks a hardcoded per-user absolute path
#   - --strict escalates WARNs (unapplied config) to failure
#   - one-shot flags parse: install.sh --one-shot --dry-run stays read-only
#
# Runs only against disposable fake homes under the test temp root. Tool
# verdicts are driven through --manifest fixtures naming fmtest-* tools whose
# stubs (plain bash scripts, portable on MSYS and Linux) are prepended to PATH,
# so results depend on the fixture, never on what the host has installed.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot setup-smoke)
EXAMPLE_DIR="$ROOT/setup/config"

make_fake_home() {
  local name=$1 home
  home="$TMP_ROOT/$name"
  rm -rf "$home"
  mkdir -p "$home/bin"
  printf '# test home\n' >"$home/AGENTS.md"
  cp -a "$ROOT/setup" "$home/setup"
  chmod +x "$home/setup/smoke.sh" "$home/setup/install.sh"
  printf '%s\n' "$home"
}

apply_good_config() {
  local home=$1
  mkdir -p "$home/config"
  tr -d '\r' <"$EXAMPLE_DIR/backend.example" >"$home/config/backend"
  tr -d '\r' <"$EXAMPLE_DIR/crew-harness.example" >"$home/config/crew-harness"
  tr -d '\r' <"$EXAMPLE_DIR/crew-dispatch.json.example" >"$home/config/crew-dispatch.json"
}

# Stub dir with fmtest-* tools as bash scripts printing a chosen version.
# Names are namespaced so they can never collide with real host tools.
make_stubs() {
  local name=$1 stubdir
  stubdir="$TMP_ROOT/$name-stubs"
  rm -rf "$stubdir"
  mkdir -p "$stubdir"
  printf '#!/usr/bin/env bash\necho "fmtest-good version 9.9.9"\n' >"$stubdir/fmtest-good"
  printf '#!/usr/bin/env bash\necho "fmtest-old version 1.0.0"\n' >"$stubdir/fmtest-old"
  chmod +x "$stubdir/fmtest-good" "$stubdir/fmtest-old"
  printf '%s\n' "$stubdir"
}

write_manifest() {  # <path> <lines...>
  local path=$1; shift
  printf '%s\n' '# test manifest' "$@" >"$path"
}

run_smoke() {
  local home=$1 stubdir=$2
  shift 2
  (cd "$home" && PATH="$stubdir:$PATH" bash setup/smoke.sh "$@")
}

test_smoke_passes_on_healthy_home() {
  local home stubdir manifest out status=0
  home=$(make_fake_home healthy)
  apply_good_config "$home"
  stubdir=$(make_stubs healthy)
  manifest="$TMP_ROOT/healthy.manifest"
  write_manifest "$manifest" 'fmtest-good 2.0.0 required --version'
  out=$(run_smoke "$home" "$stubdir" --manifest "$manifest" 2>&1) || status=$?
  [ "$status" -eq 0 ] || fail "smoke failed on a healthy home (status $status): $out"
  printf '%s' "$out" | grep -q 'SMOKE PASSED' || fail "healthy home did not report SMOKE PASSED: $out"
  printf '%s' "$out" | grep -q 'fmtest-good' || fail "manifest tool row missing from output: $out"
  pass "smoke passes on a healthy configured home"
}

test_smoke_fails_on_missing_required_tool() {
  local home stubdir manifest out status=0
  home=$(make_fake_home missing-tool)
  apply_good_config "$home"
  stubdir=$(make_stubs missing-tool)
  manifest="$TMP_ROOT/missing.manifest"
  write_manifest "$manifest" 'fmtest-absent 1.0.0 required --version'
  out=$(run_smoke "$home" "$stubdir" --manifest "$manifest" 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail "smoke passed with required tool fmtest-absent missing: $out"
  printf '%s' "$out" | grep -q 'fmtest-absent missing (required' || fail "missing tool not named: $out"
  pass "smoke fails when a required manifest tool is missing"
}

test_smoke_warns_on_missing_optional_tool() {
  local home stubdir manifest out status=0
  home=$(make_fake_home optional-tool)
  apply_good_config "$home"
  stubdir=$(make_stubs optional-tool)
  manifest="$TMP_ROOT/optional.manifest"
  write_manifest "$manifest" 'fmtest-absent 1.0.0 optional --version'
  out=$(run_smoke "$home" "$stubdir" --manifest "$manifest" 2>&1) || status=$?
  [ "$status" -eq 0 ] || fail "smoke failed on a missing OPTIONAL tool (status $status): $out"
  printf '%s' "$out" | grep -q 'fmtest-absent missing (optional' || fail "optional miss not warned: $out"
  pass "smoke only warns when an optional manifest tool is missing"
}

test_smoke_fails_below_version_floor() {
  local home stubdir manifest out status=0
  home=$(make_fake_home old-tool)
  apply_good_config "$home"
  stubdir=$(make_stubs old-tool)
  manifest="$TMP_ROOT/floor.manifest"
  write_manifest "$manifest" 'fmtest-old 2.0.0 required --version'
  out=$(run_smoke "$home" "$stubdir" --manifest "$manifest" 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail "smoke passed with fmtest-old below the manifest floor: $out"
  printf '%s' "$out" | grep -q 'fmtest-old version 1.0.0 below manifest minimum 2.0.0' \
    || fail "floor violation not named: $out"
  pass "smoke fails when a required tool sits below its version floor"
}

test_smoke_fails_on_bad_config_shape() {
  local home stubdir manifest out status=0
  home=$(make_fake_home bad-config)
  apply_good_config "$home"
  printf 'notabackend\n' >"$home/config/backend"
  printf '{ broken json\n' >"$home/config/crew-dispatch.json"
  stubdir=$(make_stubs bad-config)
  manifest="$TMP_ROOT/badconfig.manifest"
  write_manifest "$manifest" 'fmtest-good 2.0.0 required --version'
  out=$(run_smoke "$home" "$stubdir" --manifest "$manifest" 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail "smoke passed with bad config shape: $out"
  printf '%s' "$out" | grep -q "config/backend has unexpected value 'notabackend'" \
    || fail "bad backend value not named: $out"
  pass "smoke fails on unexpected config values"
}

test_smoke_fails_on_hardcoded_user_path() {
  local home stubdir manifest out status=0
  home=$(make_fake_home leaky-kit)
  apply_good_config "$home"
  printf '# helper\nlog_dir="C:\\Users\\somecaptain\\logs"\n' >"$home/setup/leaky.sh"
  stubdir=$(make_stubs leaky-kit)
  manifest="$TMP_ROOT/leaky.manifest"
  write_manifest "$manifest" 'fmtest-good 2.0.0 required --version'
  out=$(run_smoke "$home" "$stubdir" --manifest "$manifest" 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail "smoke passed with a hardcoded user path in setup/: $out"
  printf '%s' "$out" | grep -q 'hardcoded user-profile paths found' || fail "path leak not named: $out"
  pass "smoke fails when a kit file leaks a per-user absolute path"
}

test_smoke_strict_escalates_warns() {
  local home stubdir manifest out status=0 strict_status=0
  home=$(make_fake_home unapplied)
  stubdir=$(make_stubs unapplied)
  manifest="$TMP_ROOT/unapplied.manifest"
  write_manifest "$manifest" 'fmtest-good 2.0.0 required --version'
  out=$(run_smoke "$home" "$stubdir" --manifest "$manifest" 2>&1) || status=$?
  [ "$status" -eq 0 ] || fail "smoke without --strict failed on unapplied config (should warn): $out"
  out=$(run_smoke "$home" "$stubdir" --manifest "$manifest" --strict 2>&1) || strict_status=$?
  [ "$strict_status" -ne 0 ] || fail "--strict passed despite WARNs: $out"
  printf '%s' "$out" | grep -q 'strict mode: WARNs present' || fail "strict escalation not named: $out"
  pass "--strict escalates WARNs to failure while default only warns"
}

test_one_shot_dry_run_is_read_only() {
  local home out status=0 before after unamestub
  home=$(make_fake_home oneshot-dry)
  # install.sh refuses real WSL by design; this behavior test is about the
  # one-shot flag surface, so neutralize WSL markers (env + a uname stub) so
  # the same test runs on WSL dev machines. CI runners and Git Bash see no
  # difference: their uname never matched the refusal in the first place.
  unamestub="$TMP_ROOT/oneshot-uname-stub"
  mkdir -p "$unamestub"
  printf '#!/usr/bin/env bash\ncase "${1:-}" in -r) echo generic ;; *) uname_real=%s; echo Linux ;; esac\n' '' >"$unamestub/uname"
  chmod +x "$unamestub/uname"
  before=$(find "$home" -type f | wc -l)
  out=$(cd "$home" && env -u WSL_INTEROP -u WSL_DISTRO_NAME PATH="$unamestub:$PATH" \
    bash setup/install.sh --one-shot --dry-run --primary=pi </dev/null 2>&1) || status=$?
  [ "$status" -eq 0 ] || fail "--one-shot --dry-run exited nonzero ($status): $out"
  after=$(find "$home" -type f | wc -l)
  [ "$before" = "$after" ] || fail "--one-shot --dry-run changed the home ($before -> $after files)"
  [ ! -d "$home/config" ] || fail "--one-shot --dry-run created config/"
  pass "install --one-shot --dry-run parses and stays read-only"
}

test_smoke_passes_on_healthy_home
test_smoke_fails_on_missing_required_tool
test_smoke_warns_on_missing_optional_tool
test_smoke_fails_below_version_floor
test_smoke_fails_on_bad_config_shape
test_smoke_fails_on_hardcoded_user_path
test_smoke_strict_escalates_warns
test_one_shot_dry_run_is_read_only

echo "all setup-smoke tests passed"
