#!/usr/bin/env bash
# fm-win-tree-enter.sh: Windows (Git Bash/MSYS) replacement for the bare
# `treehouse get` fm-spawn types into a fresh worker pane.
#
# Why this exists (all three facts verified live on Windows herdr, 2026-08-07):
# - The pane's default shell is PowerShell and a bare `treehouse get` there
#   opens a cmd.exe subshell, because treehouse falls back to %COMSPEC% when
#   SHELL does not name a resolvable executable.
# - fm-spawn's worktree discovery reads the pane's live cwd from herdr, and
#   the Windows herdr build tracks a pane's cwd ONLY from OSC 9;9 sequences
#   emitted by the pane's own shell; cmd.exe never emits them, so discovery
#   times out even though the subshell entered the worktree.
# - The launch command fm-spawn later types into the subshell uses POSIX
#   shell syntax (env-var prefixes, $(...) substitution), which cmd.exe
#   cannot parse.
#
# So: run treehouse with SHELL pointing at Git bash (Windows path so Go's
# exec can resolve it), and export a PROMPT_COMMAND that emits OSC 9;9 with
# the Windows form of the cwd on every prompt. The subshell bash inherits
# both from the environment, herdr's cwd tracking stays live, and the later
# POSIX launch command lands in a shell that understands it.
set -e
SHELL="$(cygpath -w /usr/bin/bash)"
export SHELL
export PROMPT_COMMAND='printf "\033]9;9;%s\033\\" "$(cygpath -w "$PWD")"'
exec treehouse get
