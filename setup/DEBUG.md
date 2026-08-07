# PODLES Firstmate setup — debug guide

Windows-first. Paths are patterns and commands, not one user’s profile.

## 1. Git Bash must beat WSL on PATH (common footgun)

The installer (`install.ps1` / `install.sh`) warns early when `bash` resolves to the WSL launcher (`System32\bash.exe`, Store/`WindowsApps` shim, or other WSL-branded hit) and points here. Do not ignore that WARN — later failures look unrelated.

### Symptom

- `bash` is WSL, not Git for Windows
- Firstmate / Herdr / treehouse / hooks misbehave
- Scripts that expect MSYS paths fail oddly
- `which bash` / first `where.exe bash` → `System32\bash.exe`, `WindowsApps`, or WSL
- Installer: `WARN: bash looks like WSL/store shadow` / `Windows PATH resolves bash to WSL/store shadow`

### Fix

1. Windows search → **Environment Variables** → edit **Path** (user and/or system).
2. Move **Git for Windows** entries **above** WSL-related entries:
   - Keep high: `...\Git\cmd`, `...\Git\bin`, `...\Git\usr\bin`
   - Below those: WSL, or anything that ships a competing `bash.exe`
3. **Fully restart** every process that caches PATH after the change:
   - every terminal window/tab
   - the IDE (VS Code / Cursor / etc.)
   - Herdr
   - every agent host (Pi, Claude, Codex, Grok, firstmate session)
   - Old processes keep the old PATH. A single `hash -r` is **not** enough for the whole stack.
4. Verify in a **new** shell (Git Bash and/or PowerShell):

```sh
which bash
command -v bash
bash --version | head -1
# Expect Git for Windows / MSYS path shape, e.g.:
#   /usr/bin/bash
#   /c/Program Files/Git/usr/bin/bash
#   /c/Program Files/Git/bin/bash
# NOT: /c/Windows/System32/bash.exe or WindowsApps / WSL paths
```

```powershell
where.exe bash
Get-Command bash | Select-Object -ExpandProperty Source
# Expect first hit like:
#   C:\Program Files\Git\usr\bin\bash.exe
#   C:\Program Files\Git\bin\bash.exe
# NOT first: C:\Windows\System32\bash.exe, SysWOW64, WindowsApps, wsl.exe
```

If `where.exe bash` still lists WSL/`System32` first, reorder PATH again and restart everything in step 3.

CHECKLIST.md §A1 is the operator checkbox for this verification.

---

## 2. Installer / home discovery

### Symptom

Installer says it cannot find the firstmate home.

### Fix

- Run from the home that contains **both** `AGENTS.md` and `setup/`.
- Do not run the script from inside a random copy of `setup/` alone.
- Home is always: parent directory of `setup/` (script location), never a hardcoded username path.

```sh
# Git Bash: from home
test -f AGENTS.md && test -d setup && echo OK
```

---

## 3. Windows Defender vs no-mistakes

### Symptom

- `no-mistakes.exe` vanishes
- daemon dies
- install directory empties mid-install
- Threat name often looks like a behavioral / persistence heuristic (false positive class)

### Fix (order matters)

1. **Add a Windows Defender exclusion** for `no-mistakes.exe` and/or its install directory (**admin**).
2. **Only then** install or reinstall no-mistakes and start the daemon.
3. If the daemon dies later, check Defender history **before** reconfiguring Firstmate:

```powershell
Get-MpThreatDetection | Select-Object -First 20
```

Exclusion **after** quarantine is too late for that install attempt — exclude, then reinstall.

---

## 4. Pi: project trust, extensions, read-only / lock

### Symptom

- Session start: read-only / cannot locate harness process in ancestry
- `PI_WATCH_EXTENSION: not loaded`
- Cannot spawn or steer workers

### Fix

1. Quit Pi fully.
2. Start from the firstmate home:

```sh
cd /path/to/PODLES-agent-workspace
pi
```

3. Approve **project trust** once per clone.
4. Confirm session start is **not** read-only and extensions loaded.

Trust-free fallback (home-relative):

```sh
pi -e .pi/extensions/fm-primary-turnend-guard.ts -e .pi/extensions/fm-primary-pi-watch.ts
```

Do not try to spawn/steer/merge from a read-only session — restart with trust instead.

---

## 5. Claude first-launch dialogs

Claude Code often shows **two** dialogs in order:

1. **Folder trust** → Enter  
2. **Bypass permissions** — default is often **“No, exit”** → press **Down**, then **Enter**

If the worker “vanishes,” it may have exited on the second dialog.

---

## 6. Herdr backend

### Checks

```sh
herdr --version
herdr status --json
cat config/backend   # expect: herdr
```

### Windows notes (high level)

- Prefer **Git Bash** as the shell Herdr/tasks use (ties back to PATH section 1).
- Drive-letter socket paths and cwd probing needed Firstmate-side fixes on recent main — keep firstmate home updated (`/updatefirstmate` when available).
- Workers should appear as Herdr tabs/workspaces when backend is `herdr`.

If spawn fails: read the spawn error, confirm `jq` exists, confirm Herdr protocol is new enough (see home `docs/herdr-backend.md`).

---

## 7. Tool on PATH but “not found” in agent

### Fix

- Fully restart the agent host after installing CLIs (same as PATH restart).
- Confirm the same shell the agent uses:

```sh
command -v pi claude codex grok herdr gh treehouse no-mistakes
```

- npm globals: ensure npm global bin dir is on user PATH (`npm bin -g` / `%APPDATA%\npm` pattern).

---

## 8. Grok / Codex dispatch fails

- **Grok:** missing `grok` binary is a blocker — install + auth; Firstmate should not silently fall back to Claude.
- **Codex:** confirm `codex` login; model names in `crew-dispatch.json` must match what your CLI accepts — edit the example if your account lists different IDs.

---

## 9. fm-send “failed” but worker acted (Windows Herdr)

Occasional false-negative submit verification: steer landed, CLI still exited nonzero / pending.

**Before re-sending:** read the worker pane. Avoid double instructions.

---

## 10. no-mistakes JSON / agent path on Windows

If no-mistakes spawns agents via npm cmd-shims and mangles `--json-schema`, point its config at the native agent binary (e.g. package `claude.exe`) via vendor `agent_path_override`, then restart the no-mistakes daemon. See home learnings / no-mistakes docs for the current key name.

---

## 11. Quick decision tree

| Failure | First check |
|---|---|
| Wrong bash / weird scripts | §1 PATH Git vs WSL + full restart |
| no-mistakes vanished / daemon dead | §3 Defender history + exclusion-before-install |
| Pi read-only / no spawn | §4 trust + extensions |
| Claude worker exits immediately | §5 second dialog default |
| No worker UI | §6 `config/backend` + `herdr` + restart |
| `use grok` fails | §8 `grok` on PATH + auth |
| Double steers | §9 pane read before resend |

---

## 12. Collecting a support bundle (no secrets)

```sh
cd /path/to/PODLES-agent-workspace
echo "=== home ===" && pwd && test -f AGENTS.md && test -d setup
echo "=== bash ===" && which bash && bash --version | head -1
echo "=== tools ===" && for c in pi claude codex grok herdr gh treehouse no-mistakes node npm jq; do printf '%s: ' "$c"; command -v "$c" || echo MISSING; done
echo "=== config ===" && for f in config/backend config/crew-harness; do echo "-- $f"; cat "$f" 2>/dev/null || echo ABSENT; done
echo "=== herdr ===" && herdr --version 2>/dev/null; herdr status --json 2>/dev/null | head -c 500
```

Do **not** paste `.env`, tokens, or full `data/` backlog into chats.
