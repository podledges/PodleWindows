#!/usr/bin/env bash
# podle-scribe.sh - decoupled language-transformer harness for the ObbyVault pipeline.
#
# Usage: podle-scribe.sh <grok|gemini> < draft.md > rewritten.md
#
# Reads a finished documentation draft on stdin, applies the constant rewrite
# prompt (config/scribe-prompt.md), and prints the plain-language rewrite to
# stdout via the chosen provider's headless CLI mode.
#
# Deliberately NOT an fm-spawn adapter: a one-shot text transform needs no
# supervision, busy-state, or fleet wiring. If it is ever wanted as a crewmate,
# fm-spawn's raw-launch-command escape hatch accepts it without registration.
#
# Providers:
#   grok    grok --single (single-turn print mode) with --system-prompt-override
#   gemini  agy --print (Antigravity headless print mode); the constant prompt
#           is prepended to the draft because agy has no system-prompt flag.
#           Override the model with PODLE_SCRIBE_GEMINI_MODEL if needed.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROMPT_FILE="$SCRIPT_DIR/../config/scribe-prompt.md"

die() { echo "podle-scribe: $*" >&2; exit 1; }

provider=${1:-}
case "$provider" in
  grok|gemini) ;;
  *) die "usage: podle-scribe.sh <grok|gemini> < draft.md > rewritten.md" ;;
esac
[ -f "$PROMPT_FILE" ] || die "constant prompt not found: $PROMPT_FILE"

draft=$(mktemp)
trap 'rm -f "$draft"' EXIT
cat > "$draft"
[ -s "$draft" ] || die "empty draft on stdin"

case "$provider" in
  grok)
    command -v grok >/dev/null 2>&1 || die "grok CLI not on PATH"
    exec grok --single "$(cat "$draft")" --system-prompt-override "$(cat "$PROMPT_FILE")"
    ;;
  gemini)
    command -v agy >/dev/null 2>&1 || die "agy CLI not on PATH (Antigravity provides the gemini backend)"
    model_args=()
    [ -z "${PODLE_SCRIBE_GEMINI_MODEL:-}" ] || model_args=(--model "$PODLE_SCRIBE_GEMINI_MODEL")
    # Flags must precede --print: agy treats everything after --print as prompt text.
    exec agy --output-format text --disable-slash-commands "${model_args[@]+"${model_args[@]}"}" --print \
      "$(cat "$PROMPT_FILE"; printf '\n\n--- THE DRAFT TO REWRITE FOLLOWS ---\n\n'; cat "$draft")"
    ;;
esac
