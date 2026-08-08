#!/usr/bin/env node
// Claude Code status line — fleet-ui skin (config-driven).
// $ctx:  "190K·19% ▓▓░░░░░░"
// $left: default/Fable → "81% left · 5d:18h" (rose % · mint sep · cyan period)
//        Sonnet/Opus   → "95% left · 4h:20m" (session window)

"use strict";

const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  loadConfig,
  providerConfig,
  clampPct,
  remainingFromUsed,
  formatCtx,
  formatLeft,
  ansiPalette,
} = require("./format.js");

const ADHD_FLAG = path.join(__dirname, "state", "adhd-mode.on");
const ADHD_BADGE_PLAIN = "⚡ ADHD MODE · BLUF · lists · no filler";

const ADHD_PALETTE = [
  "\x1b[38;2;255;45;149m",
  "\x1b[38;2;108;255;212m",
  "\x1b[38;2;255;214;10m",
  "\x1b[38;2;0;212;255m",
  "\x1b[38;2;179;71;255m",
  "\x1b[38;2;255;110;64m",
];

function isAdhdOn() {
  try {
    return fs.existsSync(ADHD_FLAG);
  } catch (_) {
    return false;
  }
}

function paintMixed(text) {
  const { BOLD, RESET } = ansiPalette();
  let out = BOLD;
  for (let i = 0; i < text.length; i++) {
    out += ADHD_PALETTE[i % ADHD_PALETTE.length] + text[i];
  }
  return out + RESET;
}

function adhdBannerAnsi() {
  const { BOLD, REVERSE, RESET } = ansiPalette();
  const left = `${REVERSE}${BOLD}\x1b[38;2;10;10;18m\x1b[48;2;255;45;149m ADHD ${RESET}`;
  const mid = paintMixed(" ◆ FOCUS · BLUF · LISTS · ZERO FILLER ◆ ");
  const right = `${REVERSE}${BOLD}\x1b[38;2;10;10;18m\x1b[48;2;108;255;212m MODE ${RESET}`;
  return `${left}${mid}${right}`;
}

function readStdin() {
  return new Promise((resolve) => {
    let raw = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c) => (raw += c));
    process.stdin.on("end", () => resolve(raw));
    process.stdin.on("error", () => resolve(raw));
  });
}

function fireHerdrReport(ctxToken, leftToken, adhdOn) {
  if (process.env.HERDR_ENV !== "1" || !process.env.HERDR_PANE_ID) return;
  const p = providerConfig("claude");
  if (p && p.enabled === false) return;
  try {
    const script = path.join(__dirname, "report-herdr.js");
    const args = [script];
    if (!p || p.reportCtx !== false) args.push("--ctx", ctxToken);
    if (!p || p.reportLeft !== false) args.push("--left", leftToken);
    if (adhdOn) args.push("--adhd", ADHD_BADGE_PLAIN);
    else args.push("--token", "adhd=");
    const child = spawn(process.execPath, args, {
      stdio: "ignore",
      detached: true,
      windowsHide: true,
      env: process.env,
    });
    child.unref();
  } catch (_) {
    // never break the status line
  }
}

function pick(obj, keys) {
  for (const k of keys) {
    if (obj && obj[k] != null && obj[k] !== "") return obj[k];
  }
  return null;
}

async function main() {
  loadConfig();
  const colors = ansiPalette();
  const { RESET, BOLD, GREEN, GREEN_DIM, MAGENTA, MAGENTA_DIM, FRAME, WHITE } =
    colors;

  const raw = await readStdin();
  let data = {};
  try {
    data = JSON.parse(raw || "{}");
  } catch (_) {
    data = {};
  }

  // Diagnostic tap: keep the latest raw payload on disk so field-shape drift
  // in what Claude Code sends (rate limit windows, reset timestamps) can be
  // diagnosed from the file instead of guessed. Never breaks the status line.
  try {
    fs.writeFileSync(
      path.join(__dirname, "state", "last-input.json"),
      raw || "{}"
    );
  } catch (_) {}

  const adhdOn = isAdhdOn();
  const model =
    (data.model && (data.model.display_name || data.model.id)) || "Claude";

  const cw = data.context_window || {};
  const usedPct =
    clampPct(cw.used_percentage) ??
    clampPct(cw.percent_used) ??
    clampPct(cw.usage_percentage);

  const totalTokens =
    Number(
      pick(cw, [
        "context_window_size",
        "total_tokens",
        "window_size",
        "max_tokens",
      ])
    ) || null;
  let usedTokens = Number(
    pick(cw, ["used_tokens", "current_tokens", "tokens_used", "input_tokens"])
  );
  if (!Number.isFinite(usedTokens)) usedTokens = null;

  const ctxPlain = formatCtx({
    usedTokens,
    usedPct,
    totalTokens,
  });

  const rl = data.rate_limits || data.rateLimits || {};
  const five = rl.five_hour || rl.fiveHour || rl["5h"] || {};
  const week = rl.seven_day || rl.sevenDay || rl.weekly || rl["7d"] || {};

  const fiveLeft =
    clampPct(five.remaining_percentage) ??
    remainingFromUsed(five.used_percentage) ??
    clampPct(five.remainingPercentage) ??
    remainingFromUsed(five.usedPercentage);
  const weekLeft =
    clampPct(week.remaining_percentage) ??
    remainingFromUsed(week.used_percentage) ??
    clampPct(week.remainingPercentage) ??
    remainingFromUsed(week.usedPercentage);

  function resetFields(win) {
    if (!win || typeof win !== "object") return {};
    const out = {};
    const resetsAt =
      win.resets_at ||
      win.resetsAt ||
      win.reset_at ||
      win.resetAt ||
      win.resets_at_iso;
    if (resetsAt) out.resetsAt = resetsAt;
    const sec =
      win.seconds_remaining ??
      win.secondsRemaining ??
      win.remaining_seconds ??
      win.remainingSeconds;
    if (sec != null && Number.isFinite(Number(sec))) {
      out.secondsRemaining = Number(sec);
    }
    return out;
  }

  const leftBits = [];
  if (fiveLeft != null) {
    leftBits.push({ label: "5h", rem: fiveLeft, ...resetFields(five) });
  }
  if (weekLeft != null) {
    leftBits.push({ label: "wk", rem: weekLeft, ...resetFields(week) });
  }
  if (leftBits.length === 0 && usedPct != null) {
    const remainCtx =
      clampPct(cw.remaining_percentage) ??
      (usedPct != null ? 100 - usedPct : null);
    if (remainCtx != null) leftBits.push({ label: "ctx", rem: remainCtx });
  }

  // Sidebar (Herdr): plain + unicode underlines. Statusline: full ANSI palette.
  const leftSidebar = formatLeft(leftBits, {
    provider: "claude",
    model,
    rich: false,
  });
  const leftStatus = formatLeft(leftBits, {
    provider: "claude",
    model,
    rich: true,
  });

  fireHerdrReport(ctxPlain, leftSidebar, adhdOn);

  // Status line (inside Claude pane)
  const greenAnsi = `${GREEN}${BOLD}${ctxPlain}${RESET}`;
  // Narrative styles already carry their own colors; bits mode uses magenta wrap
  const looksRich = /\x1b\[/.test(leftStatus);
  const leftAnsi = looksRich
    ? leftStatus
    : leftBits.length > 0
      ? `${MAGENTA}${BOLD}${leftStatus}${RESET}`
      : `${MAGENTA_DIM}${leftStatus}${RESET}`;

  // Fable model name → gold; everything else stays bright white
  const isFable = /fable/i.test(String(model || ""));
  const nameAnsi = isFable
    ? `${colors.FABLE_NAME || "\x1b[38;2;255;211;110m"}${BOLD}${model}${RESET}`
    : `${WHITE}${model}${RESET}`;

  const metrics = [
    `${FRAME}╠${RESET}`,
    nameAnsi,
    `${FRAME}╣${RESET}`,
    greenAnsi,
    leftAnsi,
  ].join(" ");

  if (adhdOn) {
    process.stdout.write(`${adhdBannerAnsi()}\n${metrics}`);
  } else {
    process.stdout.write(metrics);
  }
}

main().catch(() => {
  const fallback = formatCtx({ usedTokens: 0, usedPct: 0 });
  process.stdout.write(`[Claude] ${fallback}`);
});
