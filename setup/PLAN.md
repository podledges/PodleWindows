# PODLES Firstmate setup kit — plan

**Repo:** [`podledges/podles-firstmate`](https://github.com/podledges/podles-firstmate) (private)  
**Path:** `setup/` on `main`  
**Audience:** future captain + other humans replicating the PODLES Windows agent stack  
**Status:** Kit + hardening shipped (`0f0a01a`+, then one-shot mode, version manifest, Defender helper, smoke scripts). Remaining work is the clean-machine proof run / CI lane—not greenfield rebuild.

## Goal

A portable **one-action-ish** Windows bootstrap so an operator can recreate:

| Layer | Choice |
|---|---|
| Orchestrator | Firstmate home (`AGENTS.md`) |
| Crew terminal backend | **Herdr** |
| Primary agent | **Installer prompt** (see below) |
| Workers | Pi, Claude, Codex, Grok via crew-dispatch |
| Worktrees | treehouse |
| Ship gate | no-mistakes (Defender exclusion **before** install) |

Honest boundary: vendor **auth is interactive**; the kit automates detection, config templates, prompts, and checklists—not silent logins.

## Primary prompt (product rule)

Installer asks:

> Do you have a lot of GPT usage remaining, or little/no Claude usage left?

| Answer | `config/crew-harness` | Posture |
|---|---|---|
| **Yes** | `pi` | Pi primary; crew leans **Grok** + **GPT/Codex** |
| **No** | `claude` | **Claude primary** (subscription over API burn); Pi/Codex/Grok remain crew |

Both branches: `config/backend` = `herdr` unless overridden. Never overwrite live config without confirm.

## Path / branding rules

- Discover firstmate home as **parent of `setup/`** (or `FM_HOME` / env)—**no hardcoded user profile paths**.
- Branding: **PODLES**, home name **`PODLES-agent-workspace`**, org **`podledges`**.
- Secrets never in `setup/`.

## Deliverable layout (canonical)

```text
setup/
  PLAN.md              this file
  README.md            install + integration
  DEBUG.md             Windows failures (PATH, Defender, trust, dialogs)
  CHECKLIST.md         post-install smoke
  install.ps1          Windows bootstrap
  install.sh           Git Bash only (refuse WSL)
  smoke.ps1            scripted post-install verification (Windows)
  smoke.sh             scripted post-install verification (Git Bash / CI)
  versions.manifest    known-good tool floors for smoke
  config/
    backend.example
    crew-harness.example                 # pi
    crew-harness.claude.example          # claude
    crew-dispatch.json.example           # default pi
    crew-dispatch.claude-primary.json.example
    captain.md.example
```

## DEBUG must cover (captain-confirmed + learnings)

1. **Git Bash above WSL on PATH**, then **full restart** of terminals/IDE/Herdr/agents.
2. Defender quarantine of no-mistakes: **exclusion before reinstall**.
3. Pi project trust / extensions / read-only lock (“harness process in ancestry”).
4. Claude dual first-launch dialogs (trust, then bypass-permissions default No/exit).
5. Herdr backend checks; Windows shell/cwd notes at high level.
6. Grok missing binary = blocker; fm-send false-negative → read pane before resend.

## Success criteria

- Operator runs `setup/install.ps1` or `setup/install.sh` from a firstmate home.
- Prompt selects Pi or Claude primary; examples/applied config match.
- CHECKLIST smoke: tools on PATH, auth done, primary session healthy, optional crew phrase works under Herdr.
- No secrets; no per-user absolute paths in kit files.

## Out of scope

- Upstream PR to `kunchenguid/firstmate`
- Packaging ObbyVault / PODLEPROJECTS / PodlesPlugin
- Antigravity (`agy`) harness verification
- Full private home snapshot (`data/`, live `config/`, `.env`)
- True one-click including all vendor auths

## Shipped vs remaining

| Area | State |
|---|---|
| Docs + examples + installers | **Shipped** on `main` |
| Dry-run, primary prompt, apply-config, logs, Git Bash guard | **Shipped** |
| Hardening (version manifest, stronger install verification, Defender helper, one-shot mode) | **Shipped** (`versions.manifest`, verification rescan + READY/NOT READY verdict, `--add-defender-exclusion`, `--one-shot`) |
| Smoke script (`smoke.sh` / `smoke.ps1`, `--strict` for proof runs) | **Shipped** (behavior tests: `tests/setup-smoke.test.sh`) |
| Regression: no hardcoded user paths | **Shipped** (smoke kit-hygiene check) |
| Clean-machine smoke proof run / CI lane | **Not done** (run smoke `--strict` on a fresh machine) |

## Ticketization intent

Tracer-bullet vertical slices for **remaining** value and any re-verification of the shipped path. Each ticket demoable alone; blocking edges explicit. Prefer GitHub issues on **this** private repo with `ready-for-agent` when agent-grabbable.

## References in-repo

- `setup/README.md`
- `setup/DEBUG.md`
- `setup/CHECKLIST.md`
- `setup/install.ps1` / `setup/install.sh`
- `setup/config/*.example`
- Firstmate: `docs/herdr-backend.md`, `docs/configuration.md` (link, don’t fork)
