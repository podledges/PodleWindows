# PODLES setup checklist

Work top to bottom after `setup/install.ps1` or `setup/install.sh`.  
Check boxes in your notes; this file is a template (safe to copy).

## A. Host prerequisites

### A1. `bash` is Git Bash (not WSL) — see DEBUG.md §1

Run these in a **new** terminal after any PATH change (old processes cache PATH):

```sh
which bash
command -v bash
bash --version | head -1
# Expect a Git for Windows / MSYS path shape, for example:
#   /usr/bin/bash
#   /c/Program Files/Git/usr/bin/bash
#   /c/Program Files/Git/bin/bash
# NOT:
#   /c/Windows/System32/bash.exe
#   .../WindowsApps/...
#   anything WSL-branded
```

```powershell
where.exe bash
Get-Command bash | Select-Object -ExpandProperty Source
# Expect the *first* hit under Git for Windows, for example:
#   C:\Program Files\Git\usr\bin\bash.exe
#   C:\Program Files\Git\bin\bash.exe
# NOT first:
#   C:\Windows\System32\bash.exe
#   C:\Windows\SysWOW64\bash.exe
#   ...\WindowsApps\...
#   ...\wsl.exe
```

- [ ] `which bash` / first `where.exe bash` hit matches a **Git for Windows** path shape (`...\Git\...` or Git Bash `/usr/bin/bash`)
- [ ] Git for Windows entries sit **above** WSL on user and/or system Path
- [ ] Every terminal, IDE, Herdr, and agent host was **fully restarted** after the PATH fix (not just `hash -r`)
- [ ] Node.js + npm available (`node -v`, `npm -v`)
- [ ] Running commands from firstmate home (`AGENTS.md` + `setup/` both present)

## B. no-mistakes Defender-first gate (do this before section C's no-mistakes check)

Stop here before installing or trusting `no-mistakes`. Order matters — exclusion first,
install second, never the reverse. See DEBUG.md §3.

- [ ] Windows Defender exclusion added for `no-mistakes.exe` and/or its install directory (**admin**)
- [ ] Exclusion verified read-only (no install/reinstall yet):
      ```powershell
      Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
      Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess
      ```
      Confirm an entry matches `no-mistakes` before proceeding.
- [ ] **Only now**: no-mistakes installed or reinstalled
- [ ] Daemon starts and stays up
- [ ] `Get-MpThreatDetection | Select-Object -First 20` shows no fresh quarantine after start
- [ ] If `no-mistakes --version` was working before and is now MISSING with no other change, treat it as a quarantine tell (DEBUG.md §3) — re-check the exclusion above before reinstalling, don't just reinstall

## C. Tools on PATH

Run and confirm each prints a version (not “not found”):

```sh
pi --version
claude --version
codex --version
grok --version
herdr --version
gh --version
treehouse --version
no-mistakes --version 2>/dev/null || no-mistakes version
node -v
npm -v
jq --version
```

- [ ] Pi
- [ ] Claude Code
- [ ] Codex
- [ ] Grok Build CLI
- [ ] Herdr
- [ ] gh
- [ ] treehouse
- [ ] no-mistakes (section B's Defender gate must be checked off first — DEBUG.md §3)
- [ ] jq
- [ ] axi helpers optional but recommended: `gh-axi`, `tasks-axi`, `quota-axi`, `lavish-axi`

## D. Auth (interactive — script cannot finish these)

- [ ] `gh auth login` (and `gh auth status` clean)
- [ ] Claude Code logged in / subscription active
- [ ] Codex CLI logged in
- [ ] Grok CLI authenticated
- [ ] Herdr installed and usable (`herdr status`)
- [ ] Pi can start in the home

## E. Firstmate home config

- [ ] `config/backend` → `herdr`
- [ ] `config/crew-harness` → `pi` **or** `claude` (matches your installer answer)
- [ ] `config/crew-dispatch.json` present (from example; defaults match primary choice)
- [ ] `data/captain.md` present (example or your prefs)
- [ ] No secrets committed; `.env` only if you opt into Relay later

Primary choice reminder:

| Situation | crew-harness |
|---|---|
| Lots of GPT left / little Claude left | `pi` |
| Claude usage available / prefer subscription | `claude` |

## F. Primary session smoke

### If primary is Pi

- [ ] `cd` home → `pi`
- [ ] Project trust approved (or `-e` fallback from README)
- [ ] Session start is **not** read-only
- [ ] Watch / turnend extensions loaded (no “not loaded” banner)

### If primary is Claude

- [ ] `cd` home → `claude`
- [ ] Folder trust + bypass-permissions handled (DEBUG.md §5)
- [ ] Session start healthy

## G. Crew smoke

- [ ] Ask firstmate for a trivial check (e.g. bearings / status) 
- [ ] Optional: `use grok` on a tiny read-only question — worker appears in Herdr
- [ ] Optional: `use codex` / `use claude` / `use pi` phrase routing works
- [ ] No double-send after a flaky fm-send (read pane first — DEBUG.md §9)

## H. Done when

- [ ] You can open the home, talk to one primary agent, and it can see Herdr + dispatch workers
- [ ] DEBUG.md bookmarked for PATH / Defender / trust issues
- [ ] Install log kept if the script wrote one (temp `podles-setup-*.log`)

---

**Stop and open DEBUG.md** if any of: wrong bash, Defender quarantine, Pi read-only, Claude instant exit, Herdr missing workers.
