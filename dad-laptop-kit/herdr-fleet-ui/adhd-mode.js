#!/usr/bin/env node
// ADHD mode flag for fleet-ui indicators (Claude statusline + Herdr sidebar).
// Usage:
//   node adhd-mode.js on
//   node adhd-mode.js off
//   node adhd-mode.js toggle
//   node adhd-mode.js status

"use strict";

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

const STATE_DIR = path.join(__dirname, "state");
const FLAG = path.join(STATE_DIR, "adhd-mode.on");

// High-contrast mixed palette badge (plain text for Herdr tokens)
const BADGE_PLAIN = "⚡ ADHD MODE · BLUF · lists · no filler";

function isOn() {
  try {
    return fs.existsSync(FLAG);
  } catch (_) {
    return false;
  }
}

function setOn() {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(
    FLAG,
    JSON.stringify(
      {
        on: true,
        since: new Date().toISOString(),
        badge: BADGE_PLAIN,
      },
      null,
      2
    ) + "\n",
    "utf8"
  );
}

function setOff() {
  try {
    if (fs.existsSync(FLAG)) fs.unlinkSync(FLAG);
  } catch (_) {}
}

function reportHerdr(on) {
  if (process.env.HERDR_ENV !== "1" || !process.env.HERDR_PANE_ID) return;
  try {
    const script = path.join(__dirname, "report-herdr.js");
    const args = on
      ? [script, "--adhd", BADGE_PLAIN]
      : [script, "--clear-adhd"];
    const child = spawn(process.execPath, args, {
      stdio: "ignore",
      detached: true,
      windowsHide: true,
      env: process.env,
    });
    child.unref();
  } catch (_) {}
}

function main() {
  const cmd = (process.argv[2] || "status").toLowerCase();
  let on = isOn();

  if (cmd === "on" || cmd === "enable" || cmd === "start") {
    setOn();
    on = true;
    reportHerdr(true);
    process.stdout.write(`ADHD mode ON\n${BADGE_PLAIN}\n`);
    return;
  }
  if (cmd === "off" || cmd === "disable" || cmd === "stop") {
    setOff();
    on = false;
    reportHerdr(false);
    process.stdout.write("ADHD mode OFF\n");
    return;
  }
  if (cmd === "toggle") {
    if (on) {
      setOff();
      reportHerdr(false);
      process.stdout.write("ADHD mode OFF\n");
    } else {
      setOn();
      reportHerdr(true);
      process.stdout.write(`ADHD mode ON\n${BADGE_PLAIN}\n`);
    }
    return;
  }

  // status
  process.stdout.write(on ? `on\n${BADGE_PLAIN}\n` : "off\n");
  process.exit(on ? 0 : 1);
}

main();
