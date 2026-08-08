#!/usr/bin/env node
// Shared fleet-ui formatters for Herdr sidebar tokens ($ctx, $left).
// Config lives in config.json next to this file — edit that to retheme or add providers.

"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");

const CONFIG_PATH = path.join(__dirname, "config.json");

const ANSI = {
  RESET: "\x1b[0m",
  BOLD: "\x1b[1m",
  UNDERLINE: "\x1b[4m",
  REVERSE: "\x1b[7m",
};

let _cfg = null;

function loadConfig() {
  if (_cfg) return _cfg;
  try {
    const raw = fs.readFileSync(CONFIG_PATH, "utf8").replace(/^\uFEFF/, "");
    _cfg = JSON.parse(raw);
  } catch (_) {
    _cfg = {
      format: {
        ctx: "{used}·{pct}% {bar}",
        ctxMissing: "· {bar}",
        left: "{bits}",
        leftEmpty: "·",
        leftBit: "{label} {rem}%",
        leftSep: " · ",
        barWidth: 8,
        barFilled: "▓",
        barEmpty: "░",
        tokenUnit: "K",
      },
      colors: {
        ctx: "#6CFFD4",
        left: "#FF5CAD",
        leftBody: "#E8C4FF",
        leftPct: "#FF5CAD",
        leftDays: "#FFD36E",
      },
      ansi: {
        ctx: [108, 255, 212],
        left: [255, 92, 173],
        leftBody: [232, 196, 255],
        leftPct: [255, 92, 173],
        leftDays: [255, 211, 110],
      },
      leftStyles: {
        bits: { mode: "bits" },
        "weekly-narrative": {
          mode: "narrative",
          template: "{pct}% left for {days} days",
          preferWindow: "week",
          windowDays: { wk: 6, week: 6, weekly: 6, "7d": 6 },
          defaultDays: 6,
          underlineDigits: true,
          ansiRich: true,
        },
      },
      providers: {},
      defaults: { contextWindow: {}, leftStyle: "bits" },
    };
  }
  return _cfg;
}

function reloadConfig() {
  _cfg = null;
  return loadConfig();
}

function providerConfig(name) {
  const cfg = loadConfig();
  const key = String(name || "").toLowerCase();
  return (cfg.providers && cfg.providers[key]) || null;
}

function expandHome(p) {
  if (!p) return p;
  if (p === "~") return os.homedir();
  if (p.startsWith("~/") || p.startsWith("~\\")) {
    return path.join(os.homedir(), p.slice(2));
  }
  return p;
}

function clampPct(n) {
  if (n == null || Number.isNaN(Number(n))) return null;
  return Math.max(0, Math.min(100, Math.round(Number(n))));
}

function remainingFromUsed(used) {
  const u = clampPct(used);
  if (u == null) return null;
  return 100 - u;
}

/** Compact token count for sidebar: 0 → 0K, 1600 → 2K, 1_200_000 → 1.2M */
function formatUsedTokens(n, unit) {
  if (n == null || !Number.isFinite(Number(n))) return null;
  const v = Math.max(0, Number(n));
  const u = (unit || loadConfig().format.tokenUnit || "K").toUpperCase();
  if (v >= 1_000_000) {
    const m = v / 1_000_000;
    return `${m >= 10 ? Math.round(m) : m.toFixed(1).replace(/\.0$/, "")}M`;
  }
  if (u === "K" || u === "k") {
    return `${Math.round(v / 1000)}K`;
  }
  if (v >= 1000) return `${Math.round(v / 1000)}k`;
  return String(Math.round(v));
}

function bar(pct, width, filled, empty) {
  const fmt = loadConfig().format || {};
  const w = width != null ? width : fmt.barWidth || 8;
  const f = filled != null ? filled : fmt.barFilled || "▓";
  const e = empty != null ? empty : fmt.barEmpty || "░";
  if (pct == null) return e.repeat(w);
  const filledN = Math.max(0, Math.min(w, Math.round((pct / 100) * w)));
  return f.repeat(filledN) + e.repeat(Math.max(0, w - filledN));
}

function fill(template, vars) {
  return String(template || "").replace(/\{(\w+)\}/g, (_, k) =>
    vars[k] != null ? String(vars[k]) : ""
  );
}

/**
 * Build plain $ctx token: e.g. "0K·16% ▓░░░░░░░"
 */
function formatCtx(opts = {}) {
  const fmt = loadConfig().format || {};
  let usedPct = clampPct(opts.usedPct);
  let usedTokens =
    opts.usedTokens != null && Number.isFinite(Number(opts.usedTokens))
      ? Number(opts.usedTokens)
      : null;
  const total =
    opts.totalTokens != null && Number.isFinite(Number(opts.totalTokens))
      ? Number(opts.totalTokens)
      : null;

  if (
    (usedTokens == null || (usedTokens === 0 && usedPct != null && usedPct > 0)) &&
    usedPct != null &&
    total
  ) {
    usedTokens = Math.round((usedPct / 100) * total);
  }
  if (usedPct == null && usedTokens != null && total) {
    usedPct = clampPct((usedTokens / total) * 100);
  }

  const barStr = bar(usedPct);
  if (usedPct == null && usedTokens == null) {
    return fill(fmt.ctxMissing || "· {bar}", { bar: barStr });
  }

  const usedStr = formatUsedTokens(usedTokens != null ? usedTokens : 0, fmt.tokenUnit);
  const pctStr = usedPct != null ? String(usedPct) : "·";
  let out = fill(fmt.ctx || "{used}·{pct}% {bar}", {
    used: usedStr,
    pct: pctStr,
    bar: barStr,
  });

  if (fmt.showTotalInCtx && total) {
    const totalStr = formatUsedTokens(total, fmt.tokenUnit);
    out = `${usedStr}/${totalStr}·${pctStr}% ${barStr}`;
  }
  return out;
}

/** Resolve left style name for provider + optional model display name. */
function resolveLeftStyleName(provider, modelName) {
  const cfg = loadConfig();
  const p = providerConfig(provider) || {};
  const model = String(modelName || "");
  const rules = Array.isArray(p.modelRules) ? p.modelRules : [];
  for (const rule of rules) {
    if (!rule || !rule.match) continue;
    try {
      if (new RegExp(rule.match, "i").test(model)) {
        return rule.leftStyle || p.leftStyle || cfg.defaults?.leftStyle || "bits";
      }
    } catch (_) {
      if (model.toLowerCase().includes(String(rule.match).toLowerCase())) {
        return rule.leftStyle || p.leftStyle || cfg.defaults?.leftStyle || "bits";
      }
    }
  }
  return p.leftStyle || cfg.defaults?.leftStyle || "bits";
}

function getLeftStyle(styleName) {
  const cfg = loadConfig();
  const styles = cfg.leftStyles || {};
  return styles[styleName] || styles.bits || { mode: "bits" };
}

function isWeekLabel(label) {
  return /^(wk|week|weekly|7d|mdl|fable)$/i.test(String(label || ""));
}

function isSessionLabel(label) {
  return /^(5h|session|sess)$/i.test(String(label || ""));
}

function isCreditsLabel(label) {
  return /^(cr|credits)$/i.test(String(label || ""));
}

function filterSkippedBits(bits, style) {
  const skip = new Set(
    (style && style.skip ? style.skip : []).map((s) => String(s).toLowerCase())
  );
  if (!skip.size) return bits || [];
  return (bits || []).filter(
    (b) => b && !skip.has(String(b.label || "").toLowerCase())
  );
}

/**
 * Pick which remaining bit drives a narrative line.
 * preferWindow: "week" | "session" | "min" | "credits" | "first"
 */
function pickNarrativeBit(bits, style) {
  const list = filterSkippedBits(bits, style).filter((b) => b && b.rem != null);
  if (!list.length) return null;
  const prefer = (style.preferWindow || "week").toLowerCase();
  if (prefer === "min" || style.preferMinRemaining) {
    return list.reduce((a, b) => (a.rem <= b.rem ? a : b));
  }
  if (prefer === "session" || prefer === "5h") {
    return list.find((b) => isSessionLabel(b.label)) || list[0];
  }
  if (prefer === "credits" || prefer === "cr") {
    return list.find((b) => isCreditsLabel(b.label)) || list[0];
  }
  if (prefer === "first") return list[0];
  // week default (includes model-week labels like fable)
  return (
    list.find((b) => isWeekLabel(b.label)) ||
    list[list.length - 1] ||
    list[0]
  );
}

function daysForBit(bit, style) {
  const map = style.windowDays || {};
  const key = String(bit.label || "").toLowerCase();
  if (map[key] != null && Number.isFinite(Number(map[key]))) {
    return Number(map[key]);
  }
  if (isWeekLabel(key) && map.week != null) return Number(map.week);
  if (isSessionLabel(key) && map["5h"] != null) return Number(map["5h"]);
  if (bit.days != null && Number.isFinite(Number(bit.days))) return Number(bit.days);
  return Number(style.defaultDays != null ? style.defaultDays : 6);
}

function formatDays(n) {
  if (n == null || !Number.isFinite(Number(n))) return "·";
  const v = Number(n);
  // Keep whole days as integers; allow short windows as one decimal
  if (Math.abs(v - Math.round(v)) < 1e-9) return String(Math.round(v));
  return String(Math.round(v * 10) / 10);
}

/**
 * Milliseconds remaining until bit reset / end of window.
 * Prefers resetsAt, then explicit msRemaining / secondsRemaining, then days.
 */
function msUntilReset(bit, style) {
  if (!bit) return null;
  if (bit.msRemaining != null && Number.isFinite(Number(bit.msRemaining))) {
    return Math.max(0, Number(bit.msRemaining));
  }
  if (bit.secondsRemaining != null && Number.isFinite(Number(bit.secondsRemaining))) {
    return Math.max(0, Number(bit.secondsRemaining) * 1000);
  }
  if (bit.resetsAt != null && bit.resetsAt !== "") {
    // Claude Code sends resets_at as UNIX epoch SECONDS (e.g. 1786201200).
    // new Date(number) reads milliseconds, which lands in January 1970 and
    // clamps the remaining time to 0d:00h — so scale numeric seconds up.
    // ISO strings and true millisecond timestamps pass through unchanged.
    let at = bit.resetsAt;
    if (typeof at === "number" || /^[0-9]+(\.[0-9]+)?$/.test(String(at))) {
      const n = Number(at);
      at = n < 1e12 ? n * 1000 : n;
    }
    const ms = new Date(at).getTime() - Date.now();
    if (Number.isFinite(ms)) return Math.max(0, ms);
  }
  if (bit.days != null && Number.isFinite(Number(bit.days))) {
    return Math.max(0, Number(bit.days) * 86400000);
  }
  // Fall back to style window map / default (whole days only)
  if (style) {
    const d = daysForBit(bit, style);
    if (d != null && Number.isFinite(d)) return Math.max(0, d * 86400000);
  }
  return null;
}

/**
 * Compact period: long windows → "6d:17h", session windows → "4h:20m".
 * unit: "auto" | "dh" | "hm"
 */
function formatPeriod(ms, unit) {
  if (ms == null || !Number.isFinite(Number(ms))) return "·";
  const totalMs = Math.max(0, Number(ms));
  const totalMin = Math.floor(totalMs / 60000);
  const totalH = Math.floor(totalMin / 60);
  const mode = (unit || "auto").toLowerCase();

  const useHm =
    mode === "hm" ||
    mode === "hours" ||
    mode === "session" ||
    (mode === "auto" && totalH < 24);

  if (useHm) {
    const h = Math.floor(totalMin / 60);
    const m = totalMin % 60;
    return `${h}h:${String(m).padStart(2, "0")}m`;
  }

  const d = Math.floor(totalH / 24);
  const h = totalH % 24;
  return `${d}d:${String(h).padStart(2, "0")}h`;
}

/** Resolve display period string for a bit + style. */
function periodForBit(bit, style) {
  const unit =
    style.durationUnit ||
    style.periodUnit ||
    (style.preferWindow === "session" || style.preferWindow === "5h"
      ? "hm"
      : "auto");
  // Only real reset data (resetsAt / msRemaining / secondsRemaining / days on
  // the bit itself) may drive a countdown. Passing no style here keeps the
  // static windowDays/defaultDays map out: a fabricated "6d:00h" reads as a
  // live counter and misleads exactly when the data is missing.
  const ms = msUntilReset(bit, null);
  if (ms != null) return formatPeriod(ms, unit);
  return null;
}

function underlineDigits(text) {
  // ANSI underline around the whole numeric run
  return `${ANSI.UNDERLINE}${ANSI.BOLD}${text}${ANSI.RESET}`;
}

function rgb(arr) {
  if (!Array.isArray(arr) || arr.length < 3) return "\x1b[37m";
  return `\x1b[38;2;${arr[0]};${arr[1]};${arr[2]}m`;
}

/**
 * Build plain $left token from bit list.
 * @param {Array<{label: string, rem: number, days?: number, resetsAt?: string, cycleSeconds?: number}>} bits
 * @param {{ provider?: string, model?: string, styleName?: string, rich?: boolean }} opts
 */
function formatLeft(bits, opts = {}) {
  const cfg = loadConfig();
  const fmt = cfg.format || {};
  if (!Array.isArray(bits) || bits.length === 0) {
    return fmt.leftEmpty || "·";
  }

  const styleName =
    opts.styleName ||
    resolveLeftStyleName(opts.provider || "claude", opts.model || "");
  const style = getLeftStyle(styleName);
  const rich = opts.rich === true && style.ansiRich !== false;

  if (style.mode === "narrative") {
    return formatLeftNarrative(bits, style, { rich });
  }
  if (style.mode === "compound") {
    return formatLeftCompound(bits, style, { rich });
  }

  // bits mode (default multi-window)
  const sep = fmt.leftSep != null ? fmt.leftSep : " · ";
  const bitTpl = fmt.leftBit || "{label} {rem}%";
  const joined = bits
    .filter((b) => b && b.rem != null)
    .map((b) => fill(bitTpl, { label: b.label, rem: Math.round(b.rem) }))
    .join(sep);
  if (!joined) return fmt.leftEmpty || "·";
  return fill(fmt.left || "{bits}", { bits: joined });
}

/** Combining low line under every character (Herdr-safe segment underline). */
function unicodeUnderlineAll(text) {
  return Array.from(String(text))
    .map((ch) => (ch === " " ? ch : ch + "\u0332"))
    .join("");
}

/** Combining low line under digits only (legacy). */
function unicodeUnderline(text) {
  return Array.from(String(text))
    .map((ch) => (/[\d.]/.test(ch) ? ch + "\u0332" : ch))
    .join("");
}

function ansiColor(name) {
  const a = loadConfig().ansi || {};
  const map = {
    left: a.left || [255, 92, 173],
    leftBody: a.leftBody || [108, 255, 212],
    leftPct: a.leftPct || [255, 92, 173],
    leftDays: a.leftDays || [0, 229, 255],
    leftPeriod: a.leftPeriod || a.leftDays || [0, 229, 255],
    ctx: a.ctx || [108, 255, 212],
    fableName: a.fableName || [255, 211, 110],
  };
  return rgb(map[name] || map.left);
}

/**
 * Render config segments: whole phrase shares color; optional full underline.
 * vars: { pct, days, period, label }
 */
/**
 * Drop segments that would render a missing {period} (and the trailing pure
 * separator left dangling before them), so absent reset data shows as
 * "wk 54% left" instead of a fabricated countdown.
 */
function pruneSegmentsForVars(segments, vars) {
  if (!Array.isArray(segments)) return segments;
  if (vars && (vars.period == null || vars.period === "")) {
    const kept = [];
    for (const seg of segments) {
      if (seg && seg.template && seg.template.includes("{period}")) {
        // Also drop a dangling separator segment right before the period:
        // a template with no substitutions and no word characters.
        const prev = kept[kept.length - 1];
        if (
          prev &&
          prev.template &&
          !/\{/.test(prev.template) &&
          !/\w/.test(prev.template)
        ) {
          kept.pop();
        }
        continue;
      }
      kept.push(seg);
    }
    return kept;
  }
  return segments;
}

function renderSegments(segments, vars, { rich } = {}) {
  segments = pruneSegmentsForVars(segments, vars);
  if (!Array.isArray(segments) || !segments.length) return "";
  const { RESET, BOLD, UNDERLINE } = ANSI;
  let out = "";
  for (const seg of segments) {
    if (!seg || !seg.template) continue;
    const text = fill(seg.template, vars);
    const underline = seg.underline === true;
    if (rich) {
      const color = ansiColor(seg.color || "leftPct");
      out +=
        color +
        BOLD +
        (underline ? UNDERLINE : "") +
        text +
        RESET;
    } else {
      out += underline ? unicodeUnderlineAll(text) : text;
    }
  }
  return out;
}

/**
 * Days until reset / cycle length for a bit.
 * Prefers bit.days, then resetsAt horizon, then cycleSeconds, then style default.
 */
function resolveBitDays(bit, stylePart) {
  if (bit && bit.days != null && Number.isFinite(Number(bit.days))) {
    return Number(bit.days);
  }
  if (stylePart && stylePart.useResetDays !== false && bit && bit.resetsAt) {
    const ms = new Date(bit.resetsAt).getTime() - Date.now();
    if (Number.isFinite(ms) && ms > 0) {
      const d = ms / 86400000;
      return d >= 1 ? Math.round(d) : Math.max(0.1, Math.round(d * 10) / 10);
    }
  }
  if (bit && bit.cycleSeconds != null && Number.isFinite(Number(bit.cycleSeconds))) {
    return Math.max(1, Math.round(Number(bit.cycleSeconds) / 86400));
  }
  if (stylePart && stylePart.defaultDays != null) return Number(stylePart.defaultDays);
  return 7;
}

/** Shared segment vars for narrative / compound period lines. */
function periodVars(bit, styleOrPart) {
  const pct = Math.round(bit.rem);
  const days = formatDays(
    bit.days != null && Number.isFinite(Number(bit.days))
      ? Number(bit.days)
      : resolveBitDays(bit, styleOrPart)
  );
  const period = periodForBit(bit, styleOrPart || {});
  return { pct, days, period, label: bit.label || "" };
}

/**
 * Narrative remaining via segments:
 *   rose "87% left" + mint " · " + cyan "6d:17h" (or session "4h:20m")
 */
function formatLeftNarrative(bits, style, { rich } = {}) {
  const bit = pickNarrativeBit(bits, style);
  if (!bit || bit.rem == null) {
    return (loadConfig().format || {}).leftEmpty || "·";
  }
  const vars = periodVars(bit, style);

  if (Array.isArray(style.segments) && style.segments.length) {
    return renderSegments(style.segments, vars, { rich });
  }

  // Fallback compact template
  const tpl = style.template || "{pct}% left · {period}";
  return renderSegments(
    [
      { template: tpl, color: "leftPct", underline: style.underlineSegments !== false },
    ],
    vars,
    { rich }
  );
}

/**
 * Compound remaining: each matched part can render its own period segments.
 * Default part shape matches the shared compact design.
 */
function formatLeftCompound(bits, style, { rich } = {}) {
  const parts = Array.isArray(style.parts) ? style.parts : [];
  const skip = new Set(
    (style.skip || []).map((s) => String(s).toLowerCase())
  );
  const sep = style.sep != null ? style.sep : " · ";
  const out = [];

  for (const part of parts) {
    if (!part || !part.match) continue;
    let re;
    try {
      re = new RegExp(part.match, "i");
    } catch (_) {
      continue;
    }
    const bit = bits.find(
      (b) =>
        b &&
        b.rem != null &&
        re.test(String(b.label || "")) &&
        !skip.has(String(b.label || "").toLowerCase())
    );
    if (!bit) continue;

    // Allow per-part durationUnit / preferWindow overrides
    const partStyle = {
      ...(style || {}),
      ...(part || {}),
      windowDays: part.windowDays || style.windowDays,
      defaultDays: part.defaultDays != null ? part.defaultDays : style.defaultDays,
      durationUnit: part.durationUnit || part.periodUnit || style.durationUnit,
    };
    const vars = periodVars(bit, partStyle);
    const segs = part.segments || style.segments || [
      { template: "{pct}% left", color: "leftPct", underline: true },
      { template: " · ", color: "ctx", underline: false },
      { template: "{period}", color: "leftPeriod", underline: true },
    ];
    const rendered = renderSegments(segs, vars, { rich });
    if (rendered) out.push(rendered);
  }

  if (!out.length) {
    const first = bits.find(
      (b) => b && b.rem != null && !skip.has(String(b.label || "").toLowerCase())
    );
    if (!first) return (loadConfig().format || {}).leftEmpty || "·";
    const vars = periodVars(first, style);
    return renderSegments(
      style.segments || [
        { template: "{pct}% left", color: "leftPct", underline: true },
        { template: " · ", color: "ctx", underline: false },
        { template: "{period}", color: "leftPeriod", underline: true },
      ],
      vars,
      { rich }
    );
  }
  return out.join(sep);
}

/** Strip ANSI for surfaces that only want plain text */
function stripAnsi(s) {
  return String(s || "").replace(/\x1b\[[0-9;]*m/g, "");
}

/** quota-axi window → short label */
function shortQuotaLabel(w) {
  let label = (w.label || w.id || "?").toString();
  if (/five|session|5h/i.test(label) || w.kind === "session") return "5h";
  if (/week|seven|7d/i.test(label) || w.kind === "weekly") return "wk";
  if (/credit/i.test(label)) return "cr";
  if (/build/i.test(label)) return "build";
  if (/chat/i.test(label)) return "chat";
  if (/fable|model/i.test(label) || w.kind === "model") {
    return label.length > 8 ? "mdl" : label.toLowerCase().replace(/\s+/g, "");
  }
  return label.slice(0, 6).toLowerCase();
}

/**
 * Format remaining usage from quota-axi JSON for a provider name.
 */
function formatLeftFromQuota(provider, data, opts = {}) {
  const providers = (data && data.providers) || [];
  const p = providers.find((x) => x.provider === provider);
  if (!p || !Array.isArray(p.windows) || p.windows.length === 0) return null;

  const bits = [];
  for (const w of p.windows) {
    const rem =
      w.percentRemaining != null
        ? Math.round(w.percentRemaining)
        : w.percentUsed != null
          ? Math.round(100 - w.percentUsed)
          : null;
    if (rem == null) continue;
    const label = shortQuotaLabel(w);
    const bit = { label, rem };
    if (w.resetsInDays != null) bit.days = Number(w.resetsInDays);
    else if (w.daysRemaining != null) bit.days = Number(w.daysRemaining);
    if (w.resetsAt) bit.resetsAt = w.resetsAt;
    if (w.pace && w.pace.cycleSeconds != null) {
      bit.cycleSeconds = Number(w.pace.cycleSeconds);
    } else if (w.cycleSeconds != null) {
      bit.cycleSeconds = Number(w.cycleSeconds);
    } else if (w.windowSeconds != null) {
      bit.cycleSeconds = Number(w.windowSeconds);
    }
    if (w.secondsRemaining != null) bit.secondsRemaining = Number(w.secondsRemaining);
    if (w.msRemaining != null) bit.msRemaining = Number(w.msRemaining);
    bits.push(bit);
  }
  if (!bits.length) return null;
  return formatLeft(bits, {
    provider,
    model: opts.model,
    styleName: opts.styleName,
    // default plain for Herdr; callers opt into rich for statuslines
    rich: opts.rich === true,
  });
}

function ansiPalette() {
  const a = loadConfig().ansi || {};
  return {
    RESET: ANSI.RESET,
    BOLD: ANSI.BOLD,
    UNDERLINE: ANSI.UNDERLINE,
    REVERSE: ANSI.REVERSE,
    GREEN: rgb(a.ctx || [108, 255, 212]),
    GREEN_DIM: rgb(a.ctxDim || [40, 200, 150]),
    MAGENTA: rgb(a.left || [255, 92, 173]),
    MAGENTA_DIM: rgb(a.leftDim || [200, 50, 130]),
    LEFT_BODY: rgb(a.leftBody || a.ctx || [108, 255, 212]),
    LEFT_PCT: rgb(a.leftPct || [255, 92, 173]),
    LEFT_DAYS: rgb(a.leftDays || a.leftPeriod || [0, 229, 255]),
    LEFT_PERIOD: rgb(a.leftPeriod || a.leftDays || [0, 229, 255]),
    FABLE_NAME: rgb(a.fableName || [255, 211, 110]),
    FRAME: rgb(a.frame || [140, 110, 180]),
    WHITE: rgb(a.white || [245, 245, 250]),
  };
}

function contextWindowFor(provider) {
  const cfg = loadConfig();
  const p = providerConfig(provider);
  if (p && p.contextWindow) return Number(p.contextWindow);
  const d = (cfg.defaults && cfg.defaults.contextWindow) || {};
  return Number(d[provider] || d.default || 0) || null;
}

module.exports = {
  CONFIG_PATH,
  loadConfig,
  reloadConfig,
  providerConfig,
  expandHome,
  clampPct,
  remainingFromUsed,
  formatUsedTokens,
  bar,
  formatCtx,
  formatLeft,
  formatLeftNarrative,
  formatLeftCompound,
  formatLeftFromQuota,
  formatPeriod,
  periodForBit,
  msUntilReset,
  resolveLeftStyleName,
  getLeftStyle,
  shortQuotaLabel,
  stripAnsi,
  ansiPalette,
  contextWindowFor,
};
