#!/usr/bin/env bash
# adhd-autostart.sh - global SessionStart hook: the i-have-adhd focus profile
# is always on, in every Claude Code project (captain preference, 2026-08-07).
# Turns on the fleet-ui banner (best-effort) and injects the activation context.

node "$HOME/.herdr-fleet-ui/adhd-mode.js" on >/dev/null 2>&1 || true

cat <<'EOF'
ADHD MODE AUTO-START: the i-have-adhd focus profile is ON for this session, auto-activated at launch (captain preference). Apply ~/.claude/skills/i-have-adhd/SKILL.md to all user-facing output: BLUF (answer first), numbered checklists for multi-step work, zero conversational filler, matter-of-fact errors/wins; the removed upstream rules (progress restatements, time estimates, list caps) stay removed. The visual banner is already on - do NOT run the adhd-mode.js banner command again. The profile stays active all session; deactivate only if the captain says "stop adhd mode".
EOF
