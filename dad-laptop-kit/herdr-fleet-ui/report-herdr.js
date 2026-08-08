#!/usr/bin/env node
// Shared Herdr pane metadata reporter for fleet-ui.
// Safe no-op outside Herdr or when herdr is missing.
// Usage:
//   node report-herdr.js --ctx "..." --left "..." --adhd "..."
//   node report-herdr.js --clear
//   node report-herdr.js --clear-adhd

"use strict";

const { spawn } = require("child_process");

const SOURCE = "fleet-ui";
const TTL_MS = process.env.HERDR_FLEET_UI_TTL_MS || "600000";

function parseArgs(argv) {
  const out = {
    clear: false,
    clearAdhd: false,
    tokens: {},
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--clear") out.clear = true;
    else if (a === "--clear-adhd") out.clearAdhd = true;
    else if (a === "--ctx" && argv[i + 1]) out.tokens.ctx = argv[++i];
    else if (a === "--left" && argv[i + 1]) out.tokens.left = argv[++i];
    else if (a === "--usage" && argv[i + 1]) out.tokens.usage = argv[++i];
    else if (a === "--adhd" && argv[i + 1]) out.tokens.adhd = argv[++i];
    else if (a === "--token" && argv[i + 1]) {
      const pair = argv[++i];
      const eq = pair.indexOf("=");
      if (eq > 0) out.tokens[pair.slice(0, eq)] = pair.slice(eq + 1);
    }
  }
  return out;
}

function runHerdr(args) {
  return new Promise((resolve) => {
    try {
      const bin = process.env.HERDR_BIN_PATH || "herdr";
      // shell:false required: $ctx values contain ▓/░ which Windows cmd would re-split.
      const child = spawn(bin, args, {
        stdio: "ignore",
        windowsHide: true,
        shell: false,
      });
      child.on("error", () => resolve());
      child.on("close", () => resolve());
      setTimeout(() => {
        try {
          child.kill();
        } catch (_) {}
        resolve();
      }, 2500);
    } catch (_) {
      resolve();
    }
  });
}

async function main() {
  const paneId = (process.env.HERDR_PANE_ID || "").trim();
  if (!paneId || process.env.HERDR_ENV !== "1") return;

  const opts = parseArgs(process.argv);

  if (opts.clear) {
    await runHerdr([
      "pane",
      "report-metadata",
      paneId,
      "--source",
      SOURCE,
      "--clear-token",
      "ctx",
      "--clear-token",
      "left",
      "--clear-token",
      "usage",
      "--clear-token",
      "adhd",
    ]);
    return;
  }

  if (opts.clearAdhd) {
    await runHerdr([
      "pane",
      "report-metadata",
      paneId,
      "--source",
      SOURCE,
      "--clear-token",
      "adhd",
    ]);
    return;
  }

  const args = [
    "pane",
    "report-metadata",
    paneId,
    "--source",
    SOURCE,
    "--ttl-ms",
    String(TTL_MS),
  ];

  for (const [name, value] of Object.entries(opts.tokens)) {
    if (value == null || value === "") {
      args.push("--clear-token", name);
    } else {
      args.push("--token", `${name}=${value}`);
    }
  }

  if (args.length <= 6) return;
  await runHerdr(args);
}

main().catch(() => {});
