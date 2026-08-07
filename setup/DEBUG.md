# PODLES Firstmate setup — debug guide

Windows-first. Paths are patterns and commands, not one user’s profile.

## 1. Git Bash must beat WSL on PATH (common footgun)

### Symptom

- `bash` is WSL, not Git for Windows
- Firstmate / Herdr / treehouse / hooks misbehave
- Scripts that expect MSYS paths fail oddly
- `which bash` → something under WSL or `System32`

### Fix

1. Windows search → **Environment Variables** → edit **Path** (user and/or system).
2. Move **Git for Windows** entries **above** WSL-related entries:
   - Keep high: `...\Git\cmd`, `...\Git\bin`, `...\Git\usr\bin`
   - Below those: WSL, or anything that ships a competing `bash.exe`
3. **Fully restart** every terminal, IDE, Herdr, and agent host after changing PATH.  
   Old processes keep the old PATH. A single `hash -r` is not enough for the whole stack.
4. Verify in a **new** Git Bash:

```sh
which bash
bash --version
command -v bash
# Expect Git for Windows / MSYS bash, not WSL
```

```powershell
Get-Command bash | Format-List *
where.exe bash
```

If `where.exe bash` lists WSL first, reorder PATH again and restart.

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

### Detection note: quarantine vs "never installed"

If `no-mistakes --version` worked in a previous session (or the installer's tool-detection
step showed a version) and now comes back **MISSING** with no other config change, that is
the quarantine tell — binary present yesterday, gone today. Do not treat it as a fresh
install; go straight to the recovery order below and check Defender history first.

### Fix (order matters — exclusion, THEN (re)install, never the reverse)

1. **Add a Windows Defender exclusion** for `no-mistakes.exe` and/or its install directory (**admin**). The installer's "no-mistakes install gate" (Step 1 in `install.ps1` / `install.sh`) prints this before it ever mentions installing.
2. **Only then** install or reinstall no-mistakes and start the daemon (Step 2 of the same gate).
3. If the daemon dies later, check Defender history **before** reconfiguring Firstmate:

```powershell
Get-MpThreatDetection | Select-Object -First 20
```

Exclusion **after** quarantine is too late for that install attempt. Recovery order is always
**exclude, then reinstall** — never reinstall first and add the exclusion after.

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
