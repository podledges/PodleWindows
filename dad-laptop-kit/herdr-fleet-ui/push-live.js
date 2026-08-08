#!/usr/bin/env node
// One-shot: reformat existing pane tokens and re-report to Herdr (dev helper).
"use strict";

const { spawnSync } = require("child_process");
const f = require("./format.js");

function listPanes() {
  const r = spawnSync("herdr", ["pane", "list"], {
    encoding: "utf8",
    windowsHide: true,
    shell: false,
  });
  const text = r.stdout || "";
  try {
    const j = JSON.parse(text);
    return j?.result?.panes || j?.panes || [];
  } catch (_) {
    const m = text.match(/\{[\s\S]*"panes"[\s\S]*\}/);
    if (m) {
      try {
        return JSON.parse(m[0]).panes || [];
      } catch (__) {}
    }
  }
  return [];
}

function main() {
  f.reloadConfig();
  const panes = listPanes();
  console.log("panes", panes.length);

  // Live quota when available
  let grokBits = null;
  let claudeBits = null;
  try {
    const { spawnSync } = require("child_process");
    const npmRoot = process.env.APPDATA
      ? `${process.env.APPDATA}\\npm\\node_modules\\quota-axi\\dist\\bin\\quota-axi.js`
      : null;
    function q(provider) {
      const r = npmRoot
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
      if (r.error || r.status !== 0) return null;
      return JSON.parse(String(r.stdout || "").replace(/^\uFEFF/, "") || "{}");
    }
    const g = q("grok");
    if (g) {
      grokBits = f.formatLeftFromQuota("grok", g, { rich: false });
    }
    const c = q("claude");
    if (c) {
      claudeBits = f.formatLeftFromQuota("claude", c, {
        model: "Fable",
        rich: false,
      });
    }
  } catch (_) {}

  for (const p of panes) {
    if (!p.pane_id) continue;
    if (p.agent !== "claude" && p.agent !== "grok") continue;

    const args = [
      "pane",
      "report-metadata",
      p.pane_id,
      "--source",
      "fleet-ui",
      "--ttl-ms",
      "600000",
    ];

    if (p.agent === "claude") {
      let pct = 16;
      const old = p.tokens && p.tokens.ctx;
      if (old) {
        const m = String(old).match(/(\d+(?:\.\d+)?)\s*%/);
        if (m) pct = Math.round(Number(m[1]));
      }
      const used = Math.round((pct / 100) * 1e6);
      const ctx = f.formatCtx({
        usedTokens: used,
        usedPct: pct,
        totalTokens: 1e6,
      });
      const left =
        claudeBits ||
        f.formatLeft(
          [
            {
              label: "wk",
              rem: 81,
              resetsAt: new Date(Date.now() + 5.75 * 86400000).toISOString(),
            },
            {
              label: "5h",
              rem: 95,
              resetsAt: new Date(Date.now() + 4.33 * 3600000).toISOString(),
            },
          ],
          { provider: "claude", model: "Fable", rich: false }
        );
      args.push("--token", `ctx=${ctx}`, "--token", `left=${left}`);
      console.log("claude", p.pane_id, ctx, "|", left);
    } else {
      const used = 96585;
      const total = 500000;
      const pct = Math.round((used / total) * 100);
      const ctx = f.formatCtx({
        usedTokens: used,
        usedPct: pct,
        totalTokens: total,
      });
      const left =
        grokBits ||
        f.formatLeft(
          [
            {
              label: "cr",
              rem: 86,
              resetsAt: new Date(Date.now() + 6.17 * 86400000).toISOString(),
            },
          ],
          { provider: "grok", rich: false }
        );
      args.push("--token", `ctx=${ctx}`, "--token", `left=${left}`);
      console.log("grok", p.pane_id, ctx, "|", left);
    }

    // Never shell:true — block glyphs in $ctx would be split as extra args on Windows.
    const out = spawnSync("herdr", args, {
      encoding: "utf8",
      windowsHide: true,
      shell: false,
    });
    console.log("  status", out.status, (out.stderr || out.stdout || "").slice(0, 160));
  }
}

main();
