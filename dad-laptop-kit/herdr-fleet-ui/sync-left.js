#!/usr/bin/env node
// Report account remaining usage ($left) and optional context ($ctx) to Herdr.
// Provider: --provider claude|codex|grok|agy  (default: claude)
// Always exits 0 so agent Stop hooks never block.
//
// Provider behavior is driven by config.json → providers.<name>.

"use strict";

const { spawnSync, spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  loadConfig,
  providerConfig,
  expandHome,
  formatLeftFromQuota,
  formatCtx,
  contextWindowFor,
} = require("./format.js");

function argValue(flag) {
  const i = process.argv.indexOf(flag);
  if (i >= 0 && process.argv[i + 1]) return process.argv[i + 1];
  return null;
}

function readStdinSync() {
  try {
    if (process.stdin.isTTY) return "";
    return fs.readFileSync(0, "utf8");
  } catch (_) {
    return "";
  }
}

function parseHookPayload(raw) {
  if (!raw) return {};
  try {
    return JSON.parse(String(raw).replace(/^\uFEFF/, "") || "{}");
  } catch (_) {
    return {};
  }
}

// Walk ~/.grok/sessions/<cwd-encoded>/<sessionId>
function findGrokSessionDir(sessionId, sessionRoot) {
  if (!sessionId) return null;
  const root = expandHome(sessionRoot || "~/.grok/sessions");
  try {
    if (!fs.existsSync(root)) return null;
    for (const ent of fs.readdirSync(root, { withFileTypes: true })) {
      if (!ent.isDirectory()) continue;
      const cand = path.join(root, ent.name, sessionId);
      if (fs.existsSync(path.join(cand, "summary.json")) || fs.existsSync(path.join(cand, "updates.jsonl"))) {
        return cand;
      }
    }
  } catch (_) {}
  return null;
}

/** Latest totalTokens from Grok updates.jsonl (tail scan). */
function readGrokSessionTokens(sessionDir) {
  const updates = path.join(sessionDir, "updates.jsonl");
  if (!fs.existsSync(updates)) return null;
  try {
    const st = fs.statSync(updates);
    const maxRead = Math.min(st.size, 512 * 1024);
    const fd = fs.openSync(updates, "r");
    const buf = Buffer.alloc(maxRead);
    fs.readSync(fd, buf, 0, maxRead, Math.max(0, st.size - maxRead));
    fs.closeSync(fd);
    const text = buf.toString("utf8");
    const lines = text.split(/\n/).filter(Boolean);
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i];
      if (!/totalTokens/i.test(line)) continue;
      try {
        const o = JSON.parse(line);
        const t =
          o?.params?._meta?.totalTokens ??
          o?.params?.totalTokens ??
          o?._meta?.totalTokens ??
          o?.totalTokens;
        if (t != null && Number.isFinite(Number(t))) return Number(t);
      } catch (_) {
        const m = line.match(/"totalTokens"\s*:\s*(\d+)/);
        if (m) return Number(m[1]);
      }
    }
  } catch (_) {}
  return null;
}

function resolveCtxForProvider(provider, pcfg, hook) {
  if (!pcfg || pcfg.reportCtx === false) return null;
  const source = (pcfg.ctxSource || "none").toLowerCase();

  if (source === "session-tokens" && provider === "grok") {
    const sid = hook.sessionId || hook.session_id || process.env.GROK_SESSION_ID;
    const dir = findGrokSessionDir(sid, pcfg.sessionRoot);
    if (!dir) return null;
    const used = readGrokSessionTokens(dir);
    if (used == null) return null;
    const total = pcfg.contextWindow || contextWindowFor("grok") || 500000;
    const usedPct = total ? Math.round((used / total) * 100) : null;
    return formatCtx({ usedTokens: used, usedPct, totalTokens: total });
  }

  // Future: statusline / other sources report ctx themselves
  return null;
}

function runQuota(provider) {
  const npmRoot = process.env.APPDATA
    ? `${process.env.APPDATA}\\npm\\node_modules\\quota-axi\\dist\\bin\\quota-axi.js`
    : null;
  return npmRoot
    ? spawnSync(process.execPath, [npmRoot, "--provider", provider, "--json"], {
        encoding: "utf8",
        windowsHide: true,
        timeout: 12000,
      })
    : spawnSync("quota-axi", ["--provider", provider, "--json"], {
        encoding: "utf8",
        windowsHide: true,
        timeout: 12000,
        shell: process.platform === "win32",
      });
}

function main() {
  try {
    if (process.env.HERDR_ENV !== "1" || !process.env.HERDR_PANE_ID) {
      process.exit(0);
    }

    loadConfig();
    const provider = (argValue("--provider") || "claude").toLowerCase();
    const pcfg = providerConfig(provider);
    if (pcfg && pcfg.enabled === false) process.exit(0);

    const hook = parseHookPayload(readStdinSync());
    const tokens = {};

    // $left via quota-axi
    if (!pcfg || pcfg.reportLeft !== false) {
      const quotaName = (pcfg && pcfg.quotaProvider) || provider;
      const res = runQuota(quotaName);
      if (!res.error && res.status === 0) {
        try {
          const raw = String(res.stdout || "").replace(/^\uFEFF/, "");
          const data = JSON.parse(raw || "{}");
          // Sidebar surface: no ANSI (unicode underlines for narrative styles)
          const modelHint =
            hook.model ||
            hook.modelName ||
            hook.model_name ||
            (hook.model && (hook.model.display_name || hook.model.id)) ||
            "";
          const left = formatLeftFromQuota(quotaName, data, {
            model: modelHint,
            rich: false,
          });
          if (left) tokens.left = left;
        } catch (_) {}
      }
    }

    // $ctx from provider-specific source (e.g. Grok session tokens)
    if (!pcfg || pcfg.reportCtx !== false) {
      const ctx = resolveCtxForProvider(provider, pcfg || {}, hook);
      if (ctx) tokens.ctx = ctx;
    }

    if (!Object.keys(tokens).length) process.exit(0);

    const reporter = path.join(__dirname, "report-herdr.js");
    const args = [reporter];
    for (const [k, v] of Object.entries(tokens)) {
      args.push(`--${k}`, v);
    }
    const child = spawn(process.execPath, args, {
      stdio: "ignore",
      detached: true,
      windowsHide: true,
      env: process.env,
    });
    child.unref();
  } catch (_) {
    // fail open
  }
  process.exit(0);
}

main();
