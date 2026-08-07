#!/usr/bin/env bash
# Prove setup/install.sh primary branches apply the matching PODLES config.
#
# Acceptance (issue #3 / setup/PLAN.md primary prompt):
#   Yes  -> pi crew-harness + default crew-dispatch templates
#   No   -> claude crew-harness + claude-primary crew-dispatch templates
#   Both -> backend herdr (from backend.example) unless existing file is kept
#   Existing live config is never overwritten without an explicit confirm
#   README quoted primary prompt matches the installer question text
#
# Runs only against a disposable fake home under the test temp root.
# Never touches a real firstmate home's config/.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot setup-install-primary-branches)
INSTALL_SH="$ROOT/setup/install.sh"
EXAMPLE_DIR="$ROOT/setup/config"
SETUP_README="$ROOT/setup/README.md"
PROMPT_TEXT='Do you have a lot of GPT usage remaining, or little/no Claude usage left?'

assert_file_eq() {
  local expected=$1 actual=$2 label=$3
  # Normalize CRLF so Windows-checked-in examples compare cleanly on either checkout.
  if ! diff -u \
    <(tr -d '\r' <"$expected") \
    <(tr -d '\r' <"$actual") >/dev/null; then
    fail "$label: $actual does not match $expected"
  fi
}

assert_file_contains_exact_line() {
  local file=$1 needle=$2 label=$3
  if ! tr -d '\r' <"$file" | grep -Fxq "$needle"; then
    fail "$label: expected exact line not found in $file: $needle"
  fi
}

make_fake_home() {
  local name=$1 home
  home="$TMP_ROOT/$name"
  rm -rf "$home"
  mkdir -p "$home"
  # Minimal firstmate home: AGENTS.md + a copy of setup/ (installer discovers
  # home as parent of setup/).
  printf '# test home\n' >"$home/AGENTS.md"
  cp -a "$ROOT/setup" "$home/setup"
  # Ensure the install script under the fake home is executable.
  chmod +x "$home/setup/install.sh"
  printf '%s\n' "$home"
}

run_install() {
  local home=$1
  shift
  # Drive from fake home so relative log messages stay local; stdin may feed prompts.
  (cd "$home" && ./setup/install.sh "$@")
}

test_readme_prompt_matches_installer() {
  # Word-for-word where the docs quote the prompt (blockquote body, no markdown bold).
  local quoted
  # GNU grep ERE: \> is end-of-word, so match a literal '>' without backslash.
  quoted=$(grep -E '^> Do you have a lot of GPT usage remaining' "$SETUP_README" | head -n1 | sed 's/^> //' | tr -d '\r')
  [ "$quoted" = "$PROMPT_TEXT" ] \
    || fail "setup/README.md quoted prompt mismatch: got [$quoted] want [$PROMPT_TEXT]"

  grep -Fq "$PROMPT_TEXT" "$INSTALL_SH" \
    || fail "setup/install.sh missing exact primary prompt text"
  grep -Fq "$PROMPT_TEXT" "$ROOT/setup/install.ps1" \
    || fail "setup/install.ps1 missing exact primary prompt text"
  grep -Fq "$PROMPT_TEXT" "$ROOT/setup/PLAN.md" \
    || fail "setup/PLAN.md missing exact primary prompt text"

  # README must not bold-decorate words inside the quoted prompt (would break word-for-word).
  if grep -E '^> Do you have a lot of GPT usage remaining, \*\*' "$SETUP_README" >/dev/null; then
    fail "setup/README.md quotes the primary prompt with markdown emphasis inside the quote"
  fi

  pass "README/PLAN/installer primary prompt text matches word-for-word"
}

test_yes_branch_applies_pi_templates() {
  local home
  home=$(make_fake_home yes-pi)
  run_install "$home" --primary=pi --apply-config --skip-npm-install </dev/null >/dev/null \
    || fail "install.sh --primary=pi --apply-config failed"

  assert_file_eq "$EXAMPLE_DIR/backend.example" "$home/config/backend" "Yes-branch backend"
  assert_file_eq "$EXAMPLE_DIR/crew-harness.example" "$home/config/crew-harness" "Yes-branch crew-harness"
  assert_file_eq "$EXAMPLE_DIR/crew-dispatch.json.example" "$home/config/crew-dispatch.json" "Yes-branch crew-dispatch"
  assert_file_contains_exact_line "$home/config/crew-harness" "pi" "Yes-branch harness value"
  assert_file_contains_exact_line "$home/config/backend" "herdr" "Yes-branch backend value"
  grep -E '"default".*"harness": "pi"' "$home/config/crew-dispatch.json" >/dev/null \
    || fail "Yes-branch dispatch default is not pi"

  pass "Yes/pi branch applies pi harness + default dispatch + herdr backend"
}

test_no_branch_applies_claude_templates() {
  local home
  home=$(make_fake_home no-claude)
  run_install "$home" --primary=claude --apply-config --skip-npm-install </dev/null >/dev/null \
    || fail "install.sh --primary=claude --apply-config failed"

  assert_file_eq "$EXAMPLE_DIR/backend.example" "$home/config/backend" "No-branch backend"
  assert_file_eq "$EXAMPLE_DIR/crew-harness.claude.example" "$home/config/crew-harness" "No-branch crew-harness"
  assert_file_eq "$EXAMPLE_DIR/crew-dispatch.claude-primary.json.example" \
    "$home/config/crew-dispatch.json" "No-branch crew-dispatch"
  assert_file_contains_exact_line "$home/config/crew-harness" "claude" "No-branch harness value"
  assert_file_contains_exact_line "$home/config/backend" "herdr" "No-branch backend value"
  grep -E '"default".*"harness": "claude"' "$home/config/crew-dispatch.json" >/dev/null \
    || fail "No-branch dispatch default is not claude"

  pass "No/claude branch applies claude harness + claude-primary dispatch + herdr backend"
}

test_interactive_yes_and_no_answers() {
  local home_yes home_no
  home_yes=$(make_fake_home interactive-yes)
  # y = primary Yes (pi); y = apply config (default already Yes)
  printf 'y\ny\n' | run_install "$home_yes" --skip-npm-install >/dev/null 2>&1 \
    || fail "interactive Yes install failed"
  assert_file_contains_exact_line "$home_yes/config/crew-harness" "pi" "interactive Yes harness"
  assert_file_eq "$EXAMPLE_DIR/crew-dispatch.json.example" \
    "$home_yes/config/crew-dispatch.json" "interactive Yes dispatch"
  assert_file_contains_exact_line "$home_yes/config/backend" "herdr" "interactive Yes backend"

  home_no=$(make_fake_home interactive-no)
  printf 'n\ny\n' | run_install "$home_no" --skip-npm-install >/dev/null 2>&1 \
    || fail "interactive No install failed"
  assert_file_contains_exact_line "$home_no/config/crew-harness" "claude" "interactive No harness"
  assert_file_eq "$EXAMPLE_DIR/crew-dispatch.claude-primary.json.example" \
    "$home_no/config/crew-dispatch.json" "interactive No dispatch"
  assert_file_contains_exact_line "$home_no/config/backend" "herdr" "interactive No backend"

  pass "interactive Yes/No answers produce pi vs claude machine state"
}

test_existing_config_not_overwritten_without_confirm() {
  local home out
  home=$(make_fake_home overwrite-guard)
  mkdir -p "$home/config"
  printf 'KEEP-HARNESS\n' >"$home/config/crew-harness"
  printf 'KEEP-BACKEND\n' >"$home/config/backend"
  printf '{"keep":true}\n' >"$home/config/crew-dispatch.json"

  # Decline every overwrite prompt (default is No). --yes must not force overwrite.
  out=$(printf 'n\nn\nn\n' | run_install "$home" --primary=pi --apply-config --skip-npm-install -y 2>&1) \
    || fail "overwrite-guard install failed unexpectedly"

  assert_file_contains_exact_line "$home/config/crew-harness" "KEEP-HARNESS" "declined harness overwrite"
  assert_file_contains_exact_line "$home/config/backend" "KEEP-BACKEND" "declined backend overwrite"
  grep -Fq '"keep":true' "$home/config/crew-dispatch.json" \
    || fail "declined dispatch overwrite still mutated crew-dispatch.json"
  printf '%s' "$out" | grep -Fq 'Kept existing' \
    || fail "overwrite-guard did not report keeping existing files"

  # Explicit accept path still works on the same branch.
  printf 'y\ny\ny\n' | run_install "$home" --primary=claude --apply-config --skip-npm-install >/dev/null \
    || fail "overwrite-accept install failed"
  assert_file_eq "$EXAMPLE_DIR/crew-harness.claude.example" "$home/config/crew-harness" \
    "accepted overwrite crew-harness (claude branch)"
  assert_file_eq "$EXAMPLE_DIR/crew-dispatch.claude-primary.json.example" \
    "$home/config/crew-dispatch.json" "accepted overwrite dispatch (claude branch)"
  assert_file_eq "$EXAMPLE_DIR/backend.example" "$home/config/backend" \
    "accepted overwrite backend"

  pass "existing config requires explicit overwrite confirm on both branches; -y does not wipe"
}

test_ps1_maps_same_examples() {
  # PowerShell installer is exercised statically here: same example mapping as install.sh.
  # Full PS runtime write tests are covered by install.sh behavior + dry-run operator checks.
  local ps1="$ROOT/setup/install.ps1"
  grep -Fq 'crew-harness.example' "$ps1" || fail "install.ps1 missing pi harness example"
  grep -Fq 'crew-harness.claude.example' "$ps1" || fail "install.ps1 missing claude harness example"
  grep -Fq 'crew-dispatch.json.example' "$ps1" || fail "install.ps1 missing pi dispatch example"
  grep -Fq 'crew-dispatch.claude-primary.json.example' "$ps1" \
    || fail "install.ps1 missing claude-primary dispatch example"
  grep -Fq 'backend.example' "$ps1" || fail "install.ps1 missing backend example"
  grep -Fq "Overwrite existing" "$ps1" || fail "install.ps1 missing overwrite confirm prompt"

  # Branch selection: claude primary picks claude examples; else pi examples.
  grep -n "primary -eq 'claude'" "$ps1" | grep -q . \
    || fail "install.ps1 missing claude primary branch"
  grep -Fq "Get-PrimaryChoice" "$ps1" || fail "install.ps1 missing Get-PrimaryChoice"

  pass "install.ps1 maps the same pi/claude example files and overwrite prompt"
}

test_readme_prompt_matches_installer
test_yes_branch_applies_pi_templates
test_no_branch_applies_claude_templates
test_interactive_yes_and_no_answers
test_existing_config_not_overwritten_without_confirm
test_ps1_maps_same_examples
