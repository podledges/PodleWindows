#!/usr/bin/env bash
# Shared session-lock harness identity.
#
# ONE owner of the "which verified-harness process holds this home's session
# lock, and does the current process descend from that same harness?" decision.
# bin/fm-lock.sh uses it to acquire and inspect state/.lock;
# bin/fm-claude-stop-autoarm.sh uses it to prove a Stop hook fires inside the
# lock-owning primary session before it may arm or rewake.
# This file is sourced by scripts and has no side effects on source.
#
# Git for Windows bundles a Cygwin `ps` with no `-o` support at all (only
# -aefls/-p/-u/-W), and Cygwin/MSYS2 both report a process's parent as the
# synthetic orphan pid 1 the moment that parent was never spawned through
# their own pid database - which is exactly what happens when a native
# Windows harness such as claude.exe launches a Cygwin bash.exe. The identity
# and ancestry functions below read /proc as a same-host fallback for the
# first problem and fall through to the real Windows process table (via
# powershell.exe) for the second; every fallback triggers only after the
# platform-generic path already failed, so Linux and macOS behavior is
# unchanged.

# Known harness command names; extend when a new adapter is verified.
FM_HARNESS_RE='claude|codex|opencode|grok|kimi|^pi$|^pi-signed$'

# The same harnesses as exact executable names. Keep in sync with
# FM_HARNESS_RE. Used only for the stricter path evidence below, where the
# loose regex would also match ordinary firstmate paths such as
# bin/fm-claude-stop-autoarm.sh.
FM_HARNESS_NAMES=(claude codex opencode grok kimi pi-signed pi)

# Print the exact harness name carried by executable path $1 - its own basename
# or any directory component - or return 1.
#
# This exists because Claude Code's native installer names the per-session
# executable by its version (~/.local/share/claude/versions/2.1.220), so the
# basename identifies nothing while the install path still says claude. Matching
# whole path components only is what keeps that widening safe: an ordinary path
# such as bin/fm-claude-stop-autoarm.sh or ~/.claude/hooks/notify.sh has no
# "claude" component and is correctly not a harness process.
fm_harness_path_name() {  # <path>
  local path=$1 name
  [ -n "$path" ] || return 1
  for name in "${FM_HARNESS_NAMES[@]}"; do
    case "/$path/" in
      */"$name"/*) printf '%s' "$name"; return 0 ;;
    esac
  done
  return 1
}

# True when the process described by command name $1 and full argument string $2
# is a verified harness. Sets FM_HARNESS_IS_CLAUDE for the ancestry walk.
#
# Evidence, in order:
#   1. the basename of the reported command name, against FM_HARNESS_RE.
#   2. an exact harness component in that command path or in argv[0]. Both are
#      needed because the two platforms report different things: macOS reports
#      argv[0] in `ps -o comm=`, while procps on Linux reports the kernel exec
#      name and ignores argv[0] entirely, so a version-named Claude Code binary
#      is identified by its install path on macOS and by argv[0] on Linux.
#   3. a bare interpreter (node, python) running a harness script path.
FM_HARNESS_IS_CLAUDE=0
fm_harness_process_matches() {  # <comm> <args>
  local comm=$1 args=$2 base argv0 name
  FM_HARNESS_IS_CLAUDE=0
  base=$(basename -- "$comm")
  if printf '%s' "$base" | grep -qE "$FM_HARNESS_RE"; then
    case "$base" in *claude*) FM_HARNESS_IS_CLAUDE=1 ;; esac
    return 0
  fi
  argv0=${args%% *}
  if name=$(fm_harness_path_name "$comm") || name=$(fm_harness_path_name "$argv0"); then
    case "$name" in claude) FM_HARNESS_IS_CLAUDE=1 ;; esac
    return 0
  fi
  # Bare interpreter (e.g. node): match the harness name in its script path.
  case "$comm" in
    *node*|*python*)
      if printf '%s' "$args" | grep -qE "$FM_HARNESS_RE"; then
        case "$args" in *claude*) FM_HARNESS_IS_CLAUDE=1 ;; esac
        return 0
      fi
      ;;
  esac
  return 1
}

# True when harness argument string $1 describes the shared multi-session
# background daemon (`claude daemon run ...`) rather than any one session.
# Claude Code hosts every background job on a machine inside one such daemon,
# so its pid identifies the host, not a session: a lock naming it would make
# sibling background jobs look like one session and would stay "live" for as
# long as ANY job keeps the daemon up. Only the tokens immediately after argv0
# are examined, because a bg-pty-host's argument string embeds the session's
# own prompt text, which may contain anything - including these words. An argv0
# containing unquoted spaces defeats the token split; that case degrades to
# shared-host NOT detected - exactly the pre-detection behavior - never to a
# false positive.
fm_harness_args_is_shared_host() {  # <args>
  local args=$1 rest
  case "$args" in
    \"*) rest=${args#\"}; rest=${rest#*\"} ;;
    \'*) rest=${args#\'}; rest=${rest#*\'} ;;
    *) rest=${args#*[[:space:]]} ;;
  esac
  rest="${rest#"${rest%%[![:space:]]*}"}"
  case "$rest" in
    'daemon run'|'daemon run '*) return 0 ;;
    # The transient (on-demand) daemon hosts each spare/fleet worker as its own
    # 'claude --bg-pty-host <pipe> ...' child instead of a single foreground
    # 'daemon run' process, so a lock holder with this argv shape is the same
    # shared-host case under the newer daemon architecture, not an unrelated
    # live session.
    --bg-pty-host|--bg-pty-host\ *) return 0 ;;
  esac
  return 1
}

# Print the real Windows pid backing Cygwin/MSYS2 pid $1, or return 1 when this
# host has no such mapping (native Linux/macOS, or the pid is gone). Both
# emulators expose /proc/<pid>/winpid; native Linux and macOS do not, which is
# what keeps this fallback confined to the platforms that actually need it.
fm_harness_native_winpid() {  # <pid>
  local wp
  wp=$(cat "/proc/$1/winpid" 2>/dev/null) || return 1
  [ -n "$wp" ] || return 1
  printf '%s\n' "$wp"
}

# Print "<winpid>\t<name>\t<commandline>" for Windows pid $1 and every real
# ancestor above it (up to 16 hops), or return 1 when powershell.exe is
# unavailable. CommandLine has embedded whitespace (including any literal
# newline) collapsed to single spaces so each process is exactly one line.
#
# This exists only for the Cygwin/MSYS2 boundary: their own ancestry tracking
# stops at the synthetic orphan pid 1 the moment the real parent was never
# spawned through their pid database (see the file header). Win32_Process is
# the interface that can still read that real ancestry, so one PowerShell call
# walks the whole remaining chain instead of one call per hop.
fm_harness_windows_ancestry_rows() {  # <start-winpid>
  local start=$1
  case "$start" in ''|*[!0-9]*) return 1 ;; esac
  command -v powershell.exe >/dev/null 2>&1 || return 1
  powershell.exe -NoProfile -NonInteractive -Command "
    \$wp = $start
    for (\$i = 0; \$i -lt 16; \$i++) {
      \$p = Get-CimInstance Win32_Process -Filter \"ProcessId=\$wp\" -ErrorAction SilentlyContinue
      if (-not \$p) { break }
      \$cmd = (\$p.CommandLine -replace '\s+', ' ')
      \"\$(\$p.ProcessId)\`t\$(\$p.Name)\`t\$cmd\"
      \$wp = \$p.ParentProcessId
      if (-not \$wp -or \$wp -eq 0) { break }
    }
  " 2>/dev/null
}

# Walk the current process ancestry (up to 16 hops) and print this session's
# contiguous verified-harness ancestry, innermost first, one row per process:
# "<pid>\t<kind>", where kind is "session" for an ordinary harness process and
# "shared-host" for the multi-session background daemon recognized by
# fm_harness_args_is_shared_host.
#
# The walk climbs freely until the first harness match, because the caller is
# normally an ordinary shell several levels below its session. After that first
# match it stops at the first non-harness ancestor, so it can never cross a gap
# into an unrelated harness further up the real process tree - for example the
# live session that launched a test as its own subprocess.
#
# For every harness except Claude the innermost match is the session, which is
# where e.g. Pi's shared signed-wrapper ancestry actually holds the lock: a
# "pi-signed" launcher can be the direct parent of the inner "pi" engine pid that
# owns the lock, and the wrapper pid above it is not that owner. Claude Code
# instead runs hooks several levels below the session inside its own nested
# worker chain (hook shell -> claude bg-spare -> claude bg-pty-host -> claude ->
# claude), with no non-harness process between them. Which pid in that run is the
# session cannot be read off the ancestry at all, so the whole contiguous run is
# reported and the callers below decide what they need from it.
#
# `ps -o` is tried first on every pid, unchanged from every other platform;
# /proc is read only when that produced nothing (Cygwin's `ps`, see the file
# header). If the walk still reaches the top with no match at all, and the last
# pid it could read has a real Windows pid behind it, the walk continues into
# the real Windows ancestry above the synthetic boundary.
fm_harness_ancestry_rows() {
  local pid=$$ comm args ppid extending=0 printed=0 prev_pid=$$ kind last_winpid wpid wcomm wargs
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null)
    args=$(ps -o args= -p "$pid" 2>/dev/null)
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$comm" ] && [ -r "/proc/$pid/exename" ]; then
      comm=$(cat "/proc/$pid/exename" 2>/dev/null)
      args=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
      args=${args% }
      ppid=$(cat "/proc/$pid/ppid" 2>/dev/null | tr -d '[:space:]')
      [ -n "$ppid" ] || ppid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)
    fi
    [ -n "$comm" ] || break

    if fm_harness_process_matches "$comm" "$args"; then
      kind=session
      if [ "$FM_HARNESS_IS_CLAUDE" -eq 1 ] && fm_harness_args_is_shared_host "$args"; then
        kind=shared-host
      fi
      printf '%s\t%s\n' "$pid" "$kind"
      printed=1
      [ "$FM_HARNESS_IS_CLAUDE" -eq 1 ] || break
      extending=1
    elif [ "$extending" -eq 1 ]; then
      break
    fi

    prev_pid=$pid
    case "$ppid" in
      ''|*[!0-9]*) break ;;
    esac
    [ "$ppid" -gt 1 ] || break
    pid=$ppid
  done

  if [ "$printed" -eq 0 ] && last_winpid=$(fm_harness_native_winpid "$prev_pid"); then
    while IFS=$'\t' read -r wpid wcomm wargs; do
      [ -n "$wpid" ] || continue
      wcomm="${wcomm//\\//}"
      wcomm="${wcomm%.exe}"
      wargs="${wargs//\\//}"
      if fm_harness_process_matches "$wcomm" "$wargs"; then
        kind=session
        if [ "$FM_HARNESS_IS_CLAUDE" -eq 1 ] && fm_harness_args_is_shared_host "$wargs"; then
          kind=shared-host
        fi
        printf '%s\t%s\n' "$wpid" "$kind"
        printed=1
        [ "$FM_HARNESS_IS_CLAUDE" -eq 1 ] || break
        extending=1
      elif [ "$extending" -eq 1 ]; then
        break
      fi
    done < <(fm_harness_windows_ancestry_rows "$last_winpid")
  fi

  [ "$printed" -eq 1 ]
}

# Claude Code config home (jobs/, daemon/roster.json, sessions/). Overridable
# for tests; defaults to $HOME/.claude. Formats under this tree are
# version-volatile - every reader below probes defensively and treats
# absent or unparseable metadata as no evidence, never as authority.
fm_session_claude_home() {
  printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

# Print this process's Claude session identity as "<session_id>\t<job_short>".
# Either field may be empty when only one side is known; both empty is failure.
#
# Sources, in order: CLAUDE_CODE_SESSION_ID, CODEX_COMPANION_SESSION_ID (hook
# ambient), CLAUDE_JOB_DIR basename as job_short, then Claude's local job state
# and daemon roster to fill the missing half. Never invents an identity.
fm_session_claude_identity() {
  local home sid job state roster
  home=$(fm_session_claude_home)
  sid=${CLAUDE_CODE_SESSION_ID:-${CODEX_COMPANION_SESSION_ID:-}}
  job=
  if [ -n "${CLAUDE_JOB_DIR:-}" ]; then
    job=$(basename -- "$CLAUDE_JOB_DIR")
    case "$job" in ''|.|..) job= ;; esac
  fi
  if [ -z "$sid" ] && [ -n "$job" ] && command -v jq >/dev/null 2>&1; then
    state="$home/jobs/$job/state.json"
    if [ -f "$state" ]; then
      sid=$(jq -r '.sessionId // .resumeSessionId // empty' "$state" 2>/dev/null) || sid=
    fi
    if [ -z "$sid" ]; then
      roster="$home/daemon/roster.json"
      if [ -f "$roster" ]; then
        sid=$(jq -r --arg j "$job" \
          '.workers[$j].sessionId // .workers[$j].dispatch.sessionId // empty' \
          "$roster" 2>/dev/null) || sid=
      fi
    fi
  fi
  if [ -z "$job" ] && [ -n "$sid" ]; then
    case "$sid" in
      [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-*)
        job=${sid%%-*}
        ;;
    esac
  fi
  [ -n "$sid" ] || [ -n "$job" ] || return 1
  printf '%s\t%s\n' "$sid" "$job"
}

# Print the daemon roster dispatch.source for job short-id $1 (e.g. spare or
# fleet), or return 1 when the roster is absent, unreadable, or has no entry.
# source=fleet is the observed true background-job launch path; source=spare
# is the interactive/daemon-hosted-attach path. Unparseable → no evidence.
fm_session_claude_roster_source() {  # <job_short> [<session_id>]
  local job=$1 sid=${2:-} home roster src rsid
  [ -n "$job" ] || return 1
  home=$(fm_session_claude_home)
  roster="$home/daemon/roster.json"
  [ -f "$roster" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  src=$(jq -r --arg j "$job" '.workers[$j].dispatch.source // empty' \
    "$roster" 2>/dev/null) || return 1
  [ -n "$src" ] || return 1
  # Identity consistency: when both this session's id and the roster entry's
  # are known, a mismatch means the entry describes a DIFFERENT session that
  # happens to share the job short-id; that is not a positive parse for this
  # session and must not feed the authorization gate.
  if [ -n "$sid" ]; then
    rsid=$(jq -r --arg j "$job" \
      '.workers[$j].sessionId // .workers[$j].dispatch.sessionId // empty' \
      "$roster" 2>/dev/null) || rsid=
    if [ -n "$rsid" ] && [ "$rsid" != "$sid" ]; then
      return 1
    fi
  fi
  printf '%s\n' "$src"
}

# Print the registered display name for job short-id $1 from job state or the
# sessions registry, or return 1. Used only as a last-resort pane binding when
# herdr has no agent_session id and the attach client's argv carries no id.
fm_session_claude_job_name() {  # <job_short>
  local job=$1 home state name f
  [ -n "$job" ] || return 1
  home=$(fm_session_claude_home)
  command -v jq >/dev/null 2>&1 || return 1
  state="$home/jobs/$job/state.json"
  if [ -f "$state" ]; then
    name=$(jq -r '.name // empty' "$state" 2>/dev/null) || name=
    if [ -n "$name" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  fi
  if [ -d "$home/sessions" ]; then
    for f in "$home/sessions"/*.json; do
      [ -f "$f" ] || continue
      name=$(jq -r --arg j "$job" \
        'select((.jobId // "") == $j) | .name // empty' \
        "$f" 2>/dev/null) || name=
      if [ -n "$name" ]; then
        printf '%s\n' "$name"
        return 0
      fi
    done
  fi
  return 1
}

# True when pid $1 is alive. Tries POSIX kill -0 first, then the Windows-pid
# harness probe (herdr process-info returns native Windows pids that MSYS kill
# cannot see). A non-harness live pid on Windows still counts if tasklist sees
# it - attach clients are harness-named claude.exe so the harness probe is the
# common path.
fm_session_pid_alive() {  # <pid>
  local pid=$1
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null && return 0
  fm_harness_winpid_alive "$pid" && return 0
  return 1
}

# True when this Claude session has LIVE, EXACT herdr pane-attachment proof:
#   1. HERDR_PANE_ID names a pane that herdr can read right now
#   2. that pane's foreground client pid is live and is a claude process
#   3. the pane's attached agent/session identity matches THIS session exactly
#
# Identity match (first hit wins):
#   a. pane.agent_session.value equals this session id or job short-id
#      (herdr integration report-agent-session; strongest, current binding)
#   b. the pane foreground argv contains this full session id
#      (legacy direct-in-pane claude, or an attach client that names the id)
#   c. pane.agent_session is ABSENT, and the pane's stripped terminal title
#      equals this job's registered name while we hold both session id and
#      job short-id - last resort when Claude's herdr integration has not
#      reported agent_session yet (daemon-hosted attach topology on 2.1.232).
#      A PRESENT agent_session that disagrees is always a mismatch (refuse),
#      never falls through to the title fallback.
#
# Returns 1 (no proof) on missing herdr/jq, missing identity, dead/gone pane,
# dead attach pid, non-claude foreground, or any identity mismatch. Callers
# treat no-proof as fail-closed when hosting evidence is present.
fm_session_has_live_claude_pane_attachment() {
  local pane identity sid job pane_json proc_json agent_val title fg_pid fg_cmd
  local fg_name name title_stripped argv_sid
  pane=${HERDR_PANE_ID:-}
  [ -n "$pane" ] || return 1
  command -v herdr >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  identity=$(fm_session_claude_identity) || return 1
  IFS=$'\t' read -r sid job <<EOF
$identity
EOF
  [ -n "$sid" ] || [ -n "$job" ] || return 1

  pane_json=$(herdr pane get "$pane" 2>/dev/null) || return 1
  printf '%s' "$pane_json" | jq -e --arg p "$pane" \
    '(.result.pane.pane_id // "") == $p' >/dev/null 2>&1 || return 1

  agent_val=$(printf '%s' "$pane_json" | jq -r \
    '.result.pane.agent_session.value // empty' 2>/dev/null) || agent_val=
  title=$(printf '%s' "$pane_json" | jq -r \
    '.result.pane.terminal_title_stripped // .result.pane.terminal_title // empty' \
    2>/dev/null) || title=

  proc_json=$(herdr pane process-info --pane "$pane" 2>/dev/null) || return 1
  fg_pid=$(printf '%s' "$proc_json" | jq -r \
    '.result.process_info.foreground_processes[0].pid // empty' 2>/dev/null) || fg_pid=
  fg_cmd=$(printf '%s' "$proc_json" | jq -r \
    '.result.process_info.foreground_processes[0].cmdline // .result.process_info.foreground_processes[0].argv0 // empty' \
    2>/dev/null) || fg_cmd=
  fg_name=$(printf '%s' "$proc_json" | jq -r \
    '.result.process_info.foreground_processes[0].name // empty' 2>/dev/null) || fg_name=
  case "$fg_pid" in ''|*[!0-9]*) return 1 ;; esac
  fm_session_pid_alive "$fg_pid" || return 1
  case "$fg_name $fg_cmd" in
    *[Cc]laude*) ;;
    *) return 1 ;;
  esac

  # An attach argv that explicitly names a session id is definitive evidence
  # of WHICH session occupies the pane. If it names a different session than
  # this one, that contradiction refuses outright - even when a (possibly
  # stale) agent_session record would otherwise match. Contradictory metadata
  # never authorizes.
  argv_sid=$(printf '%s\n' "$fg_cmd" | sed -n \
    's/.*--session-id[= ]\([0-9a-fA-F-]\{36\}\).*/\1/p')
  if [ -n "$argv_sid" ] && [ -n "$sid" ] && [ "$argv_sid" != "$sid" ]; then
    return 1
  fi

  # (a) herdr-reported agent_session: exact match or definitive mismatch.
  if [ -n "$agent_val" ]; then
    if [ -n "$sid" ] && [ "$agent_val" = "$sid" ]; then
      return 0
    fi
    if [ -n "$job" ] && [ "$agent_val" = "$job" ]; then
      return 0
    fi
    return 1
  fi

  # (b) foreground argv carries the full session id.
  if [ -n "$sid" ]; then
    case "$fg_cmd" in
      *"$sid"*) return 0 ;;
    esac
  fi

  # (c) title equals registered job name - the weakest tier, kept because
  # herdr 0.8.0-preview reports agent_session=null for real claude panes
  # (verified live 2026-08-14 on pane wC:pM), so for current installs this is
  # the only binding a genuine foreground pane can present. It is allowed
  # only when NO stronger evidence exists to contradict it: no agent_session
  # record (handled above) and no session id anywhere in the attach argv -
  # an argv that names any session id must prove itself via (b), not fall
  # through to a display-name match. Callers additionally gate this whole
  # function behind a positively parsed non-fleet roster entry.
  if [ -n "$argv_sid" ]; then
    return 1
  fi
  if [ -n "$sid" ] && [ -n "$job" ] && [ -n "$title" ]; then
    name=$(fm_session_claude_job_name "$job") || name=
    if [ -n "$name" ]; then
      # Strip leading spinner/status glyphs Claude puts on the OSC title.
      title_stripped=$title
      while [ -n "$title_stripped" ]; do
        case "$title_stripped" in
          [[:alnum:]]*) break ;;
          ?*) title_stripped=${title_stripped#?} ;;
          *) break ;;
        esac
      done
      title_stripped=${title_stripped#"${title_stripped%%[![:space:]]*}"}
      if [ "$title_stripped" = "$name" ] || [ "$title" = "$name" ]; then
        return 0
      fi
    fi
  fi

  return 1
}

# True when the current process runs inside a DETACHED Claude background job
# that must not take fleet control. Attachment-aware (Claude Code 2.1.232+):
#
# Claude now hosts interactive herdr/WezTerm panes as daemon "spare" workers
# with CLAUDE_JOB_DIR set and a --bg-pty-host ancestry chain - the same shape
# true background ("fleet") jobs use. CLAUDE_JOB_DIR and --bg-pty-host are
# therefore evidence of daemon HOSTING only, never proof of detachment.
#
# Classification order (fail closed - no new authority on unreadable state):
#   1. CLAUDE_JOB_DIR present but EMPTY → detached (mangled hosting marker).
#   2. roster dispatch.source == "fleet" → detached (true background job).
#   3. roster positively parsed, identity-consistent, source == "spare" AND
#      live exact herdr pane-attachment proof → NOT detached (foreground),
#      even when CLAUDE_JOB_DIR is set and ancestry shows --bg-pty-host.
#      Absent, malformed, missing-entry, inconsistent, or unknown-source
#      roster data grants NO attachment authority.
#   4. hosting evidence without that proof (CLAUDE_JOB_DIR set, or ancestry
#      contains a shared-host row) → detached. Covers Windows Stop hooks
#      whose parent chain is already reaped: CLAUDE_JOB_DIR survives and,
#      without a live pane binding, still refuses - same authority as before.
#   5. no hosting evidence → NOT detached (legacy direct foreground session).
#
# An unresolvable ancestry with no CLAUDE_JOB_DIR returns 1 (not detached):
# callers use this to REFUSE extra authority, and plain cannot-locate-harness
# refusals already cover the unreadable case. Ambiguous attachment metadata
# never grants foreground.
fm_session_is_detached_claude_bg() {
  local identity sid job src rows pid kind

  # A present-but-EMPTY CLAUDE_JOB_DIR is a mangled hosting marker, not a
  # legacy session: something injected the variable and its value was lost.
  # Ambiguous hosting evidence refuses, it never falls through to legacy.
  if [ "${CLAUDE_JOB_DIR+x}" = x ] && [ -z "$CLAUDE_JOB_DIR" ]; then
    return 0
  fi

  identity=$(fm_session_claude_identity 2>/dev/null) || identity=
  if [ -n "$identity" ]; then
    IFS=$'\t' read -r sid job <<EOF
$identity
EOF
    if [ -n "$job" ]; then
      # Attachment may authorize ONLY behind a positively parsed,
      # identity-consistent, non-fleet roster entry. Absent, malformed,
      # missing-entry, inconsistent, or unknown-source roster data is
      # ambiguity: with hosting evidence in play it refuses below rather
      # than letting a pane binding speak for a session the daemon does
      # not positively describe as an interactive spare.
      if src=$(fm_session_claude_roster_source "$job" "$sid" 2>/dev/null); then
        case "$src" in
          fleet)
            return 0
            ;;
          spare)
            if fm_session_has_live_claude_pane_attachment; then
              return 1
            fi
            ;;
        esac
      fi
    fi
  fi

  [ -n "${CLAUDE_JOB_DIR:-}" ] && return 0

  rows=$(fm_harness_ancestry_rows) || return 1
  while IFS=$'\t' read -r pid kind; do
    [ "$kind" = shared-host ] && return 0
  done <<EOF
$rows
EOF
  return 1
}

# Shared spawn preflight: refuse herdr placement from a detached Claude
# background job BEFORE any worktree, container, or task record exists. Herdr
# placement needs a live launcher pane whose attached session is this one;
# a true background job (or a daemon-hosted session without live attachment
# proof) cannot satisfy that, so failing here with the real reason beats
# failing later with a stale-pane read error.
# FM_ALLOW_DETACHED_FLEET_CONTROL=1 is the deliberate unattended-supervision
# override (e.g. away-mode automation on a non-pane backend path).
fm_session_refuse_detached_herdr_spawn() {  # <backend>
  [ "${1:-}" = herdr ] || return 0
  [ "${FM_ALLOW_DETACHED_FLEET_CONTROL:-0}" = 1 ] && return 0
  fm_session_is_detached_claude_bg || return 0
  echo "error: this spawn is running inside a detached Claude background job; herdr placement is foreground-only - re-issue this request from the foreground Claude pane" >&2
  return 1
}

# Pids-only view of the same walk, innermost first, for callers that need the
# contiguous run's membership rather than one chosen identity.
fm_harness_ancestry_pids() {
  local rows
  rows=$(fm_harness_ancestry_rows) || return 1
  printf '%s\n' "$rows" | cut -f1
}

# Print the one pid that identifies this session when the session lock is being
# WRITTEN: the outermost pid of the contiguous run that is not the shared
# background-session daemon. The outermost pid lives as long as the session - a
# Claude worker several levels in is reaped when its hook returns, and a lock
# naming it would look stale moments later while the session is still running.
# But the daemon above a background session both outlives that session and is
# shared by every sibling background job, so recording it would let siblings
# claim each other's home and would keep the lock "live" long after the owning
# session ended; the outermost NON-daemon pid (the session's own pty host or
# session process) carries exactly the intended lifetime. When the whole run is
# shared-host processes (a script running directly under the daemon), fall back
# to the outermost pid unchanged. Every non-Claude harness reports a single
# session row, so this stays its innermost match.
fm_harness_ancestry_pid() {
  local rows pid kind outermost='' outermost_session=''
  rows=$(fm_harness_ancestry_rows) || return 1
  while IFS=$'\t' read -r pid kind; do
    [ -n "$pid" ] || continue
    outermost=$pid
    [ "$kind" = shared-host ] || outermost_session=$pid
  done <<EOF
$rows
EOF
  if [ -n "$outermost_session" ]; then
    printf '%s\n' "$outermost_session"
    return 0
  fi
  [ -n "$outermost" ] || return 1
  printf '%s\n' "$outermost"
}

# True if Windows pid $1 is alive and looks like a verified harness, read from
# the real Windows process table. Companion to fm_harness_windows_ancestry_rows:
# a pid that fm_harness_ancestry_pid recorded from that fallback is a real
# Windows pid outside Cygwin/MSYS2's own pid database, so `kill -0` can never
# see it even while the process is alive.
fm_harness_winpid_alive() {  # <winpid>
  local pid=$1 line comm args
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  command -v powershell.exe >/dev/null 2>&1 || return 1
  line=$(powershell.exe -NoProfile -NonInteractive -Command "
    \$p = Get-CimInstance Win32_Process -Filter \"ProcessId=$pid\" -ErrorAction SilentlyContinue
    if (\$p) {
      \$cmd = (\$p.CommandLine -replace '\s+', ' ')
      \"\$(\$p.Name)\`t\$cmd\"
    }
  " 2>/dev/null)
  [ -n "$line" ] || return 1
  IFS=$'\t' read -r comm args <<EOF
$line
EOF
  comm="${comm//\\//}"
  comm="${comm%.exe}"
  args="${args//\\//}"
  fm_harness_process_matches "$comm" "$args"
}

# True if $1 is a live process that looks like a verified harness.
fm_harness_pid_alive() {
  local pid=$1 comm args
  if kill -0 "$pid" 2>/dev/null; then
    comm=$(ps -o comm= -p "$pid" 2>/dev/null)
    args=$(ps -o args= -p "$pid" 2>/dev/null)
    if [ -z "$comm" ] && [ -r "/proc/$pid/exename" ]; then
      comm=$(cat "/proc/$pid/exename" 2>/dev/null)
      args=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
      args=${args% }
    fi
    [ -n "$comm" ] || return 1
    fm_harness_process_matches "$comm" "$args"
    return
  fi
  fm_harness_winpid_alive "$pid"
}

# Print "<name>\t<args>" (whitespace-collapsed) for pid $1 so lock diagnostics
# can say WHO holds a lock instead of a bare pid, or return 1 when the process
# cannot be read. Reads ps, then /proc (Cygwin ps, see the file header), then
# the real Windows process table for a pid outside the emulator's pid database.
fm_harness_pid_describe() {  # <pid>
  local pid=$1 comm args line
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  comm=$(ps -o comm= -p "$pid" 2>/dev/null)
  args=$(ps -o args= -p "$pid" 2>/dev/null)
  if [ -z "$comm" ] && [ -r "/proc/$pid/exename" ]; then
    comm=$(cat "/proc/$pid/exename" 2>/dev/null)
    args=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    args=${args% }
  fi
  if [ -n "$comm" ]; then
    printf '%s\t%s\n' "$(basename -- "$comm")" "$args"
    return 0
  fi
  line=$(fm_harness_windows_ancestry_rows "$pid" | head -n 1)
  [ -n "$line" ] || return 1
  printf '%s\n' "$line" | cut -f2-
}

# True when state dir $1 holds a session lock whose pid is ANY harness ancestor
# of the current process: this script runs inside the session that owns the
# home's fleet lock. Membership is the honest test of that question, because the
# lock owner sits at an unknown depth in a contiguous Claude run - it is the
# outermost pid when the hook fires inside the session's own nested worker chain,
# and an inner pid when a harness-named daemon parents the session. Membership
# deliberately still includes a shared-host daemon pid even though the write
# path above never records one anymore: a legacy lock naming the daemon must
# keep belonging to the session it hosts until that lock naturally cycles, and
# a hook firing under the daemon chain still proves it runs inside the owning
# session. A missing lock, a malformed lock, a lock held by a harness outside
# this ancestry, or an ancestry that cannot be resolved all fail closed.
fm_session_lock_owned_by_self() {
  local state=$1 lock_pid pids pid
  lock_pid=$(cat "$state/.lock" 2>/dev/null || true)
  case "$lock_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  pids=$(fm_harness_ancestry_pids) || return 1
  while IFS= read -r pid; do
    [ "$pid" = "$lock_pid" ] && return 0
  done <<EOF
$pids
EOF
  return 1
}
