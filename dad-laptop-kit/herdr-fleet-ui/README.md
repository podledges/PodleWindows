# herdr-fleet-ui

Captain-local Herdr sidebar skin for agent panes.

## What you see

Each enabled agent pane reports two custom tokens:

| Token  | Example                 | Meaning                          |
|--------|-------------------------|----------------------------------|
| `$ctx` | `97K·19% ▓░░░░░░░`      | Context used (compact) + bar     |
| `$left`| `81% left · 5d:18h` (Fable/week) · `95% left · 4h:20m` (Sonnet/Opus) | Account remaining (shared compact template) |
| `$adhd`| badge when flag is on   | ADHD focus mode                  |

## Config (edit this)

**`config.json`** is the single place to retheme or add providers.

### Format

```json
"format": {
  "ctx": "{used}·{pct}% {bar}",
  "left": "{bits}",
  "barWidth": 8,
  "tokenUnit": "K"
}
```

- `{used}` → compact tokens (`0K`, `97K`, `1.2M`)
- `{pct}` → integer percent
- `{bar}` → `▓` / `░` bar

### Colors

```json
"colors": {
  "ctx": "#6CFFD4",
  "leftPct": "#FF5CAD",
  "leftPeriod": "#00E5FF",
  "fableName": "#FFD36E",
  "adhd": "#FF3DAA"
}
```

`$left` template (all narrative styles): `{pct}% left · {period}`  
— rose `% left`, mint ` · ` (same as `$ctx`), cyan period.

Herdr paints `$ctx` / `$left` with the `fg` values in  
`%APPDATA%/herdr/config.toml` under `[ui.sidebar.agents]`.  
Keep those hex values in sync with `config.json` → `colors` when you retheme  
(or re-run the color block below).

### Add another provider

1. Enable it in `config.json`:

```json
"providers": {
  "codex": {
    "enabled": true,
    "quotaProvider": "codex",
    "reportCtx": false,
    "reportLeft": true,
    "ctxSource": "none"
  }
}
```

2. Wire a hook that runs:

```text
node "%USERPROFILE%\.herdr-fleet-ui\sync-left.js" --provider codex
```

3. Ensure Herdr has a `rows_by_agent.codex` (or default) row with `$ctx` / `$left`.

4. If the agent has a statusline (like Claude), point it at a thin adapter that  
   calls `format.formatCtx(...)` and `report-herdr.js --ctx ...`.

`ctxSource` values today:

| Value             | Behavior                                      |
|-------------------|-----------------------------------------------|
| `statusline`      | Agent statusline reports `$ctx` itself        |
| `session-tokens`  | `sync-left.js` reads session token counters   |
| `none`            | No context line (quota-only / left only)      |

## Files

| File                   | Role                                              |
|------------------------|---------------------------------------------------|
| `config.json`          | Format, colors, provider registry                 |
| `format.js`            | Shared formatters (`formatCtx`, `formatLeft`)     |
| `statusline-claude.js` | Claude Code statusline + live `$ctx`/`$left`      |
| `sync-left.js`         | Stop/SessionStart: quota `$left` + optional `$ctx`|
| `report-herdr.js`      | `herdr pane report-metadata` wrapper              |
| `adhd-mode.js`         | Toggle ADHD badge                                 |

## Quick color sync into Herdr

After changing `colors` in `config.json`, update matching `fg = "#..."` lines in:

`%APPDATA%\herdr\config.toml` → `[ui.sidebar.agents]` / `rows_by_agent.*`

Default high-contrast set:

- ctx: `#6CFFD4`
- left: `#FF4AD4`
- adhd: `#FF3DAA`
