# ObbyVault — Agent Convention (the second brain)

ObbyVault is the agent-writable Obsidian vault: a per-project second brain mirroring the captain's repos. Under the Vault Contract (see `PLANS/Podle System Overhaul Plan`), agents have full control here. This file is the convention contract for HOW agents write to it.

**Canonical vault path:** `__FM_HOME_WIN__\ObbyVault` (the copy in `Documents\.PODLEPROJECTS\ObbyVault` is deprecated).

## Layout

One folder per project, named exactly after its repo folder under `__PROJECTS_WIN__\` (plus `PODLES-agent-workspace` itself). Each project folder holds exactly these five files:

**Nested packages rule:** if a package/project lives INSIDE another project's repo (e.g. `PodleObby` inside the `PodlesPlugin` repo), the vault mirrors that containment: the child gets its own five-file folder NESTED inside the parent's (`ObbyVault/PodlesPlugin/PodleObby/`), and the parent's `SPEC.md` carries a `## Contains` section with a full-path wikilink per child (e.g. `[[PodlesPlugin/PodleObby/SPEC|PodleObby]]`), while the child's `SPEC.md` links back to the parent the same way. Folder nesting mirrors the tree; the wikilinks draw the parent–child edge in Obsidian's graph. Same rule applies recursively. When a repo merely SITS inside another project's directory without being part of that repo (independent repo on disk), keep its vault folder top-level and reflect the location with a `Contains repo`/`Lives in` wikilink pair instead of nesting.

| File | What it is | Update rule |
|---|---|---|
| `SESSIONS.md` | Session records | PREPEND newest entry |
| `PROJECT_LOG.md` | Change summaries | PREPEND newest entry |
| `IDEAS.md` | Idea tracker | Edit in place |
| `SPEC.md` | Living spec ("THINGS I WANT") | Edit in place |
| `prompts.md` | Raw prompt log | PREPEND newest block |

## File contracts

### SESSIONS.md
- Newest entry FIRST. Entries separated by `---`.
- Entry header: `## <short title> — <YYYY-MM-DD> <HH:MM>`
- Body: what the captain asked, and what was delivered — summarized in the captain's familiar style, ~15 lines max (exemplar: `PodlesPlugin/PodleSkills/SESSIONS.md` in PODLES-agent-workspace).
- Never rewrite history. Corrections are appended as a new entry, not edits to old ones.

### PROJECT_LOG.md
- Newest entry FIRST, same `---` separation and dated headers.
- Each entry: what changed, where (paths), and why. Terse and factual.

### IDEAS.md
- Three sections: `## Agreed`, `## Planned`, `## Speculative`.
- Every idea is a checkbox: `- [ ]` not done, `- [x]` done.
- Ideas move between sections as their status firms up; done ideas stay (checked) for the record.

### SPEC.md
- The "THINGS I WANT" brief template: the current truth of what the captain wants from this project.
- Append new asks as they appear. REMOVE asks the captain drops. This is a living document, not a log — pruning is required; history lives in git and SESSIONS.md, not here.
- Structure: `# THINGS I WANT — <project>`, then `## Now` / `## Next` / `## Someday` sections of short imperative bullets.

### prompts.md
- Raw log: every prompt the captain sent in the session, VERBATIM, no cleanup, no curation.
- PREPEND a block per session: `## <YYYY-MM-DD> <HH:MM>` then each prompt as a `> ` blockquote, in the order sent.

## Update rules

1. Only Claude or Codex agents update these files. No other tooling writes here.
2. A run touches ONLY the folders of projects that session actually worked on. Nothing else in the vault is modified without an explicit prompt from the captain.
3. New project folder + the five files are created lazily: the first time `/go-next` runs for a project that has no folder here.
4. For code context when summarizing a project, prefer `omp` (Open Memory Protocol, on PATH): `omp --symbolic <file>` or `omp --project --json <dir>` — deterministic extraction for `.py .ts .tsx .js .jsx .go`. Fall back to reading files directly for other languages.
5. The `/go-next <provider>` skill is the primary writer (session-boundary sync). Supplementary mid-session updates by agents are welcome and follow the same contracts.
6. Drafts pass through the language transformer before landing: `bin/podle-scribe.sh <grok|gemini>` in `PODLES-agent-workspace` (constant prompt in `config/scribe-prompt.md`).

## Off-limits

- `PLANS/`, `PodleMem/`, `SHORTCUTS`, `.obsidian/` — pre-existing content, not governed by this convention; leave alone unless explicitly asked.
- `lapodle-biblioteka`'s own vault system is separate and approval-gated; this convention never writes there.

## Recommended vault plugins (captain installs manually)

- Smart Connections (community store) — semantic linking across the per-project notes.
