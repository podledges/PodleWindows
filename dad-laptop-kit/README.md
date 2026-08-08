# dad-laptop-kit — replicate the PODLES stack on a second Windows machine

**What this sets up:** Podles-firstmate home + Herdr crew backend + **Claude Code as primary** + **Pi crew wrapped to Grok** (`bin/pi-grok`) + the `go-next` vault pipeline + the `i-have-adhd` focus profile (auto-start hook + fleet-ui banner/statusline).

**Why this kit exists:** the repo's own `setup/` kit installs tools and home config, but several pieces live OUTSIDE git on the original machine and would be lost in a plain clone:

| Piece | Original location | Carried here as |
|---|---|---|
| go-next skill | `~/.claude/skills/go-next/` | `user-claude/skills/go-next/` (paths templatized) |
| i-have-adhd skill | `~/.claude/skills/i-have-adhd/` | `user-claude/skills/i-have-adhd/` |
| ADHD auto-start hook | `~/.claude/hooks/adhd-autostart.sh` + settings.json | `user-claude/hooks/` + installer merge |
| herdr-fleet-ui (banner, statusline) | `~/.herdr-fleet-ui/` (no git repo) | `herdr-fleet-ui/` |
| podle-scribe | `bin/podle-scribe.sh` (untracked) | `bin/podle-scribe.sh` |
| scribe prompt | `config/scribe-prompt.md` (untracked) | `config/scribe-prompt.md` |
| Vault contract | `ObbyVault/AGENTS.md` (untracked) | `vault-seed/AGENTS.md` (paths templatized) |
| Pi→Grok wrapper | — (new) | `bin/pi-grok` |
| Claude-primary + pi-on-grok dispatch | — (new variant) | `home-config/crew-dispatch.json` |

## Install checklist (top to bottom on the new laptop)

### 1. Prerequisites

1. Windows 10/11, admin access for installers.
2. [Git for Windows](https://git-scm.com/download/win) — Git Bash must win over WSL on PATH (`setup/DEBUG.md` §1).
3. Node.js LTS + npm.
4. GitHub CLI: `winget install GitHub.cli`, then `gh auth login` (any GitHub account — `podledges/podles-firstmate` is public).

### 2. Get the firstmate home onto the machine

Option A (git, preferred):

```powershell
cd $env:USERPROFILE
gh repo clone podledges/podles-firstmate PODLES-agent-workspace
```

Option B (no GitHub account): zip the whole `PODLES-agent-workspace` folder on the original machine and unzip it to `C:\Users\<dad>\PODLES-agent-workspace`.

This kit folder (`dad-laptop-kit/`) ships in the repo, so a clone includes it.

### 3. Run the main setup kit (tools + primary choice)

```powershell
cd $env:USERPROFILE\PODLES-agent-workspace
powershell -ExecutionPolicy Bypass -File .\setup\install.ps1 -Primary claude
```

This detects/installs tools and writes base config. Claude-primary means day-to-day orchestration burns the Claude **subscription**, not API credits.

### 4. Run THIS kit's installer (the out-of-git pieces)

```powershell
powershell -ExecutionPolicy Bypass -File .\dad-laptop-kit\install.ps1
```

It writes: skills → `~\.claude\skills`, ADHD hook → `~\.claude\hooks`, fleet-ui → `~\.herdr-fleet-ui`, home config (`backend=herdr`, `crew-harness=claude`, pi-on-grok `crew-dispatch.json`), `podle-scribe.sh` + `pi-grok` → `bin\`, vault seed → `ObbyVault\`, and wires the SessionStart hook + statusline into `~\.claude\settings.json` (prints a manual-merge snippet instead if settings.json already exists). `-DryRun` to preview, `-Force` to overwrite.

**Note:** this kit's `crew-dispatch.json` (default = pi-on-grok crew) intentionally replaces the `setup/` kit's claude-primary example. If step 3 already wrote one, rerun with `-Force` or copy `dad-laptop-kit\home-config\crew-dispatch.json` over `config\crew-dispatch.json` by hand.

### 5. Install + authenticate the individual tools

1. **Claude Code**: `npm install -g @anthropic-ai/claude-code`, then `claude` → log in with the subscription account.
2. **Pi**: `npm install -g @earendil-works/pi-coding-agent`.
3. **Grok Build CLI**: vendor installer, then authenticate (`grok` on PATH is required — missing binary is a blocker, not a silent fallback).
4. **Pi→Grok wrapper**: launch `pi` once, run `/model`, and note the exact Grok model id your account exposes. If it isn't `grok-4`, set `PI_GROK_MODEL=<real-id>` in your shell profile **and** update the three `"model": "grok-4"` fields in `config\crew-dispatch.json`. Pi needs the xAI provider authenticated (`XAI_API_KEY` or Pi's login flow).
5. **Herdr**: install from [herdr.dev](https://herdr.dev), license/auth in its UI, confirm `herdr --version` works. Herdr ≥ 0.8.0 recommended (workspace projection fixes).
6. **gh**: `gh auth status` clean.
7. Optional axi helpers: `npm install -g gh-axi lavish-axi quota-axi tasks-axi`.
8. **no-mistakes** (only if shipping with the gate): add the Windows Defender exclusion FIRST, then install — see `setup/DEBUG.md` §3. Skipping this on day one is fine.

### 6. Smoke test

1. Work through `setup/CHECKLIST.md` sections A–D and F–G (Claude-primary branch).
2. New terminal → `cd %USERPROFILE%\PODLES-agent-workspace` → `claude`. First launch: approve folder trust + the bypass-permissions dialog.
3. Confirm the session starts with the **ADHD MODE AUTO-START** context (the hook fired) and the fleet-ui statusline renders.
4. Ask firstmate for a trivial crew task — a **Pi worker tab should appear in Herdr** running a Grok model. Phrase overrides: `use grok`, `use pi`, `use claude`.
5. End the session with `/go-next` (or `/go-next grok`) — confirm it writes `ObbyVault\PODLES-agent-workspace\` five-file folder and the scribe pass runs (`bash bin/podle-scribe.sh grok` needs the Grok CLI; `gemini` needs the Antigravity `agy` CLI — if neither is installed the skill lands untransformed drafts and says so, which is fine).

### 7. Known deltas vs the original machine

- The **claude-glow** notification hooks (glow.exe on Notification/PreToolUse/etc.) are NOT included — they depend on a Python venv under `PodlePlugins`. Add later if wanted.
- `herdr-sessionstart.sh` (Herdr agent-state reporting) is NOT included for the same reason (depends on claude-glow's pythonw venv).
- The vault seed contains only `AGENTS.md` (the writing contract). Project folders lazy-create on first `/go-next`.
- `go-next` expects sibling projects under `<home>\PODLEPROJECTS\` on this machine (templatized from the original's `Documents\.PODLEPROJECTS`).
- omp (symbolic code extractor used opportunistically by go-next) is not bundled; go-next works without it.
