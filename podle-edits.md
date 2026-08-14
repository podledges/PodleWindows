# podle-edits — podles-firstmate changes, 2026-08-14

Summary of the changes landed on `podledges/podles-firstmate` `main` today (all pushed, `6aec4dd..39d1e12`).

## The problem

Claude Code 2.1.232 changed its architecture: **every** session — including the interactive one in your herdr pane — is now hosted by the background daemon as a "spare" worker, with `CLAUDE_JOB_DIR` injected and a `claude --bg-pty-host` process ancestry. The morning's foreground-only lock fix (`313900f`, `58b866f`, `6aec4dd`) treated exactly those signals as proof of a *detached background job*, so after the Claude update **every session on the machine was refused fleet control**. The fleet became unownable: following "relaunch claude in a pane" could never work.

## The fix — `39d1e12` fix(lock): classify daemon-hosted foreground panes by live pane attachment

`CLAUDE_JOB_DIR` / `--bg-pty-host` are demoted to evidence of daemon *hosting*, never detachment. Classification (`fm_session_is_detached_claude_bg` in `bin/fm-session-lock-lib.sh`, the single contract owner) is now attachment-aware and fail-closed:

1. `CLAUDE_JOB_DIR` present but **empty** → refused (mangled marker, not legacy).
2. Daemon roster `dispatch.source: "fleet"` → refused (true background job).
3. Roster **positively parsed, identity-consistent, `source: "spare"`** + **live exact pane attachment** → foreground. Attachment proof requires: the `HERDR_PANE_ID` pane exists now, its foreground client is a live claude process, and identity matches with **no contradiction** (an attach argv naming a different session id always refuses). Because herdr 0.8.0-preview reports `agent_session: null` for real claude panes, a title↔registered-job-name match is the accepted weakest tier — gated behind the roster check and contradiction-free argv.
4. Hosting evidence without that proof → refused (Windows Stop hooks keep exactly their old authority).
5. No hosting evidence at all → legacy direct foreground, allowed as before.

Absent/malformed/missing-entry/unknown-source roster data grants **no** attachment authority. `FM_ALLOW_DETACHED_FLEET_CONTROL=1` override semantics unchanged.

Also in the commit:

- Callers aligned: `fm-lock.sh`, `fm-spawn.sh` herdr preflight, `fm-turnend-guard.sh`, `backends/herdr.sh`.
- `tests/fm-lock-detached-bg.test.sh`: 10 contract cases (attached-foreground allowed; fleet-source / stale pane / identity mismatch / broken-roster / contradiction / empty-marker refused; legacy allowed; override preserved), with ambient-env isolation so the suite passes inside daemon-hosted sessions, plus an env-gated live guard (`FM_LIVE_CLAUDE_ATTACH=1`) run against the real machine.
- `docs/verification/runtime-backends.md`: dated vendor-fact evidence (roster `spare` vs `fleet`, `agent_session: null`).
- `setup/DEBUG.md` §12 trimmed to symptom + remediation with a pointer to the contract owner; duplicate section number fixed.

Provenance: implemented by a pi/grok-4.5 crewmate, finished by the primary after the crew harness died, hardened per a codex (gpt-5.6-sol) cross-review that caught two fail-open paths (broken-roster fallthrough, contradictory/title-only bindings) before merge. Verified live: the real pane session classifies foreground with no override; hidden or stale pane refuses.

## Housekeeping — `e01204b` chore: land standing local drift

- `.gitignore` now covers all personal workspace dirs (`ObbyVault/`, `PODLEPROJECTS/`, `PodleVault/`, `PodlesPlugin/`, `PodleDesign/`, `PodleSkills/`, `.tmp.driveupload/`, `.podle-tags.json`) so they can never be accidentally committed into firstmate.
- Removed the unsafe `Bash(taskkill *)` permission allowance from `.claude/settings.json`.
- Dropped the upstream Questions/Discord section from `CONTRIBUTING.md`.
- `bin/podle-scribe.sh` (second-brain language transformer, in use since 2026-08-07) is now tracked.

## Related but not in this repo

- `~/.codex/hooks.json` had a UTF-8 BOM that made codex reject the whole hooks config every launch; stripped (backup: `hooks.json.bak-bom`).
- The queued `firstmate-pr1864-replacement-ship` task targets **upstream** `kunchenguid/firstmate` (nested clone `firstmate/`, branch `fix/windows-cygwin-session-lock-ancestry`) — same session-lock subsystem, different repo, not part of today's merge.
