# PODLES Firstmate setup kit

Replicate the **PODLES** agent stack on Windows: Firstmate home + **Herdr** crew backend + multi-harness workers (**Pi**, **Claude**, **Codex**, **Grok**).

This kit lives at:

```text
PODLES-agent-workspace/setup/
```

It does **not** replace upstream [firstmate](https://github.com/kunchenguid/firstmate). You still need a firstmate home (this repo / your clone). This kit installs tools, applies PODLES-shaped config templates, and walks auth + smoke checks.

## TL;DR

One-shot mode (closest to a single action: auto-installs everything installable
via winget + npm, offers the Defender-exclusion helper, applies config for your
primary choice, ends with a READY / NOT READY verdict):

```powershell
# From the firstmate home root (folder that contains AGENTS.md and setup/)
cd path\to\PODLES-agent-workspace
powershell -ExecutionPolicy Bypass -File .\setup\install.ps1 -OneShot
```

Or Git Bash:

```sh
cd /path/to/PODLES-agent-workspace
./setup/install.sh --one-shot
```

Guided mode (same flow, asks before each install):

```powershell
powershell -ExecutionPolicy Bypass -File .\setup\install.ps1
```

```sh
./setup/install.sh
```

After either mode, verify with the smoke pass (tool floors from
`setup/versions.manifest`, config shape, kit hygiene):

```powershell
powershell -ExecutionPolicy Bypass -File .\setup\smoke.ps1
```

```sh
./setup/smoke.sh
```

Dry-run (no writes, no installs):

```powershell
.\setup\install.ps1 -DryRun
```

```sh
./setup/install.sh --dry-run
```

Then finish **interactive logins** (script cannot do these for you) and open your chosen primary agent **inside the firstmate home**, preferably under Herdr.

| Doc | When |
|---|---|
| [CHECKLIST.md](CHECKLIST.md) | After install — auth + smoke |
| [DEBUG.md](DEBUG.md) | Something breaks (PATH, Defender, lock, dialogs) |

## What you get

| Layer | PODLES default |
|---|---|
| Orchestrator | Firstmate (`AGENTS.md` in home) |
| Crew terminal backend | **Herdr** (`config/backend`) |
| Primary agent | **Chosen by installer prompt** (see below) |
| Workers | Pi, Claude, Codex, Grok via `config/crew-dispatch.json` |
| Worktrees | treehouse |
| Ship gate (prod-ish projects) | no-mistakes (**Defender exclusion before install**) |

### Primary prompt (API vs subscription)

The installer asks:

> Do you have a lot of GPT usage remaining, or little/no Claude usage left?

| Your answer | `config/crew-harness` | Why |
|---|---|---|
| **Yes** | `pi` | Pi primary; crew leans **Grok** + **GPT/Codex**. Uses API-oriented capacity when Claude is tight. |
| **No** | `claude` | **Claude primary** so day-to-day orchestration burns **Claude subscription**, not API credits. Pi/Codex/Grok stay available as crew. |

Both branches keep `config/backend` = `herdr` unless you override.

In a non-interactive shell (no stdin, e.g. automation/CI), both installers warn and fall back to the default answer — **No** → `claude` primary; pass `-Primary` / `--primary=` to choose explicitly.

**Honest credit note**

- Claude Code as primary → subscription-friendly for the firstmate session itself.
- Pi / Codex with GPT-class models → can burn **API** or ChatGPT/Codex quotas depending on how those CLIs are logged in.
- Grok → Grok Build CLI account/quota.
- There is no free infinite crew. Pick the primary that matches **what you have left**.

## Prerequisites

- Windows 10/11
- [Git for Windows](https://git-scm.com/download/win) (bash must be **Git Bash**, not WSL — see [DEBUG.md](DEBUG.md))
- PowerShell 5.1+ (7+ fine) for `install.ps1`
- Node.js + npm (for Pi, Claude Code CLI, several axi tools)
- Ability to run installers / approve UAC when needed
- GitHub account (`gh auth login`)

## One-action install (what the script actually does)

1. Discovers the firstmate **home** as the parent of `setup/` (no hardcoded user paths).
2. Checks that `AGENTS.md` exists there.
3. Warns if `bash` looks like WSL instead of Git Bash.
4. Detects tools on `PATH` (and common install roots via env vars only).
5. Presents the **no-mistakes install gate** (Defender-first, in dry-run and real runs alike): checks read-only whether a Defender exclusion for no-mistakes exists (never adds/removes one), states exclusion-before-install ordering, then checks for no-mistakes — flagging a previously-working-now-missing binary as a likely quarantine ([DEBUG.md](DEBUG.md) §3).
6. Asks the **primary prompt** (unless `-Primary pi|claude` / `--primary=`).
7. Offers winget installs for missing foundation tools (`gh`, Node LTS, `jq`) and npm globals for the rest (Pi, Claude Code, Codex, axi tools) — auto-yes in one-shot mode, never a silent force-overwrite of your configs.
8. With `-AddDefenderExclusion` / `--add-defender-exclusion` (implied by one-shot): offers to add the no-mistakes Defender exclusion via an **elevated** PowerShell after explicit consent + UAC. Default remains detect-only.
9. Writes missing config from examples after confirm (or `-ApplyConfig` / `--apply-config`).
10. Ends with a **verification rescan**: re-detects the stack for your chosen primary, probes `gh auth status`, and prints READY / NOT READY plus the remaining interactive steps in order.

**Not automated (honest boundary — you must do these):** vendor logins (claude / codex / grok / herdr), Herdr license/install UI, Pi project trust, full PATH reorder + shell restart.

## Manual tool map

Install whatever the script reports missing. Prefer official installers; versions drift.

| Tool | Role | Typical install |
|---|---|---|
| **Git + Git Bash** | Scripts, hooks, tree enter | git-scm.com — put Git **above** WSL on PATH |
| **gh** | GitHub CLI | `winget install GitHub.cli` then `gh auth login` |
| **Node/npm** | Pi, Claude CLI, axi | nodejs.org LTS or winget |
| **Pi** | Primary (Yes-branch) / crew | `npm install -g @earendil-works/pi-coding-agent` |
| **Claude Code** | Primary (No-branch) / crew | `npm install -g @anthropic-ai/claude-code` (confirm current package name on Anthropic docs) |
| **Codex** | Crew (GPT) | Official Codex CLI install for your account |
| **Grok** | Crew | Grok Build CLI install + auth |
| **Herdr** | Backend | [herdr.dev](https://herdr.dev) / vendor Windows installer → ensure `herdr` on PATH |
| **treehouse** | Task worktrees | Firstmate bootstrap may offer; or project releases |
| **no-mistakes** | Validation gate | **Defender exclusion first**, then install — see DEBUG |
| **axi tools** | Fleet helpers | `npm install -g gh-axi lavish-axi quota-axi tasks-axi chrome-devtools-axi` |

## Apply PODLES config (if you skip the script)

From the firstmate home:

```sh
mkdir -p config data
cp setup/config/backend.example config/backend
# Yes-branch (GPT-heavy):
cp setup/config/crew-harness.example config/crew-harness
cp setup/config/crew-dispatch.json.example config/crew-dispatch.json
# No-branch (Claude primary):
# cp setup/config/crew-harness.claude.example config/crew-harness
# cp setup/config/crew-dispatch.claude-primary.json.example config/crew-dispatch.json
cp setup/config/captain.md.example data/captain.md   # only if data/captain.md is absent
```

Never overwrite a hand-tuned `config/*` without reading the diff.

## Integrate agents with Pi and Herdr

### Herdr = where the crew appears

```sh
# home-relative
echo herdr > config/backend
# or one shot: FM_BACKEND=herdr
```

Launch your **primary** from a terminal attached to Herdr when you want workers as Herdr tabs/workspaces. Outside Herdr, Firstmate still uses Herdr for workers when `config/backend` says `herdr` (home-labeled workspace). Details: `docs/herdr-backend.md` in the firstmate home.

### Pi as primary (Yes-branch)

```sh
cd /path/to/PODLES-agent-workspace   # must contain AGENTS.md
pi
# Approve project trust once so .pi/extensions auto-load
```

Trust-free fallback:

```sh
pi -e .pi/extensions/fm-primary-turnend-guard.ts -e .pi/extensions/fm-primary-pi-watch.ts
```

### Claude as primary (No-branch)

```sh
cd /path/to/PODLES-agent-workspace
claude
```

First launch: folder trust → then bypass-permissions dialog (default is often **No, exit** — move down, then Enter).

### Crew overrides in chat (any primary)

Say any of:

- `use grok` / `run on grok` / `harness=grok`
- `use codex` / `send this to codex`
- `use claude` / `use pi`

Rules live in `config/crew-dispatch.json` (see examples under `setup/config/`).

### Grok / Codex as workers

- Grok: `grok` on PATH + authenticated; missing binary is a **blocker**, not a silent Claude fallback.
- Codex: `codex` on PATH + authenticated; dispatch example uses model `gpt-5.5` — adjust after `codex` model list if names differ on your account.

## Layout of this kit

```text
setup/
  README.md           this file
  DEBUG.md            Windows failures + fixes
  CHECKLIST.md        post-install smoke
  install.ps1         Windows bootstrap
  install.sh          Git Bash bootstrap (Windows Git Bash only)
  smoke.ps1           post-install verification (Windows)
  smoke.sh            post-install verification (Git Bash / Linux CI)
  versions.manifest   known-good tool floors smoke checks against
  config/
    backend.example
    crew-harness.example              # pi
    crew-harness.claude.example       # claude
    crew-dispatch.json.example        # default pi
    crew-dispatch.claude-primary.json.example
    captain.md.example
```

## After install

1. Work through [CHECKLIST.md](CHECKLIST.md).
2. Start primary in the home.
3. Ask firstmate to add a project or run a tiny scout — confirm a Herdr worker tab appears.
4. Keep secrets in gitignored `.env` / vendor CLIs only — never in `setup/`.

## Branding

- Home folder name: **`PODLES-agent-workspace`**
- Org (remotes): **`podledges`**
- Upstream distro: **`kunchenguid/firstmate`**

## Flags reference

The scripts own their exact flag lists - ask them directly instead of trusting a prose copy:

```sh
./setup/install.sh --help
./setup/smoke.sh --help
```

```powershell
Get-Help .\setup\install.ps1 -Detailed
Get-Help .\setup\smoke.ps1 -Detailed
```

Key modes (`-OneShot` / `--one-shot`, `-DryRun` / `--dry-run`, `-AddDefenderExclusion` / `--add-defender-exclusion`, smoke `-Strict` / `--strict`) are described in the sections above.
