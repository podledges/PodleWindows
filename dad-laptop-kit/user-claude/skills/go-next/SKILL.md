---
name: go-next
description: Session-boundary sync of the ObbyVault second brain. Run instead of a bare /compact or /clear. Summarizes the session, updates the five vault docs for every project the session touched (one pipeline, one subagent per file where possible), passes new prose through the podle-scribe language transformer, then declares the session safe to compact or clear. Argument = transformer provider (grok | gemini; default gemini).
---

# go-next

The session-boundary command. The captain runs `/go-next <provider>` when a chat is winding down, INSTEAD of a bare `/compact` or `/clear`. It flushes everything worth keeping into the ObbyVault second brain, then tells the captain it is safe to compact/clear. Supplementary mid-session vault updates are welcome too — this skill is the guaranteed boundary sync.

**Vault:** `__FM_HOME_WIN__\ObbyVault` (canonical). The per-file contracts live in the vault's `AGENTS.md` — read it before writing anything, it always wins over this skill's summary of it.

**Argument:** `<provider>` = `grok` or `gemini` — which LLM the language transformer uses. Default `gemini` when omitted.

## Pipeline (one pass, in order)

1. **Summarize the session** — write one relay summary: intuitive, complete, informative. What the captain asked (each distinct ask), what was decided, what was delivered (paths, PRs, commands), what remains open. This relay is the single source every file-writer consumes.

2. **Identify touched projects** — every project under `__PROJECTS_WIN__\` (plus `PODLES-agent-workspace`) whose files this session read, edited, or substantively discussed. The current working directory's project always counts.

3. **Lazy-create folders** — for each touched project missing from the vault: create `ObbyVault/<project>/` with the five skeleton files per the vault `AGENTS.md`.

4. **Fan out file updates** — for each touched project, update `SESSIONS.md`, `PROJECT_LOG.md`, `IDEAS.md`, `SPEC.md` (contracts in vault `AGENTS.md`). Preferred: one subagent per file (Agent tool), each given (a) the relay summary, (b) that file's contract, (c) the file's current content — returning the new entry (SESSIONS/PROJECT_LOG: new entry only) or the full updated document (IDEAS/SPEC). **In PODLES-agent-workspace the firstmate hook blocks the Agent tool** (`FM_ALLOW_SUBAGENT=1` at launch is the only sanctioned exception): when the Agent tool is denied, do NOT fight the hook — write the four files sequentially yourself following the same contracts. Use `omp --symbolic <file>` / `omp --project --json <dir>` for deterministic code context where it helps (py/ts/tsx/js/jsx/go).

5. **Language-transformer pass** — every NEW block of prose (new SESSIONS/PROJECT_LOG entries; changed sections of IDEAS/SPEC) goes through the scribe before landing in the vault:
   ```bash
   bash "__FM_HOME_POSIX__/bin/podle-scribe.sh" <provider> < draft.md > rewritten.md
   ```
   Transform only the new prose — never re-transform existing entries. If the scribe fails (provider down), land the untransformed draft and say so; a synced vault beats a pretty one.

6. **prompts.md** — the MAIN agent (not a subagent) prepends the raw-log block: `## <YYYY-MM-DD> <HH:MM>` then every captain prompt from this session, verbatim, as `> ` blockquotes, in order. Verbatim means verbatim — no cleanup, no transformer pass.

7. **Close** — end with exactly this shape, as the final line:
   `Vault synced for <project list>. Safe to /compact or /clear now.`
   A skill cannot press /compact or /clear itself; this line is the handshake that nothing will be lost.

## Rules

- Touch ONLY the vault folders of touched projects. Nothing else in the vault, ever, without an explicit ask.
- Never rewrite vault history: SESSIONS/PROJECT_LOG/prompts prepend; corrections are new entries.
- SPEC.md is living truth: append new asks, REMOVE dropped ones.
- If the session touched zero project files (pure chat), still log the session under the cwd project — decisions count as work.
