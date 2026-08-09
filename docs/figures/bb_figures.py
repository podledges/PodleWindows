#!/usr/bin/env python3
"""Generate the SVG figures for docs/borrowing-base-market-knowledge.md.

Pure standard library (no numpy/matplotlib) so it runs anywhere.
Deterministic: fixed seeds, stable output bytes for a given Python version.

Usage: python3 docs/figures/bb_figures.py
Writes bb-*.svg next to this file.
"""

import heapq
import math
import os
import random

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# Reference palette (light surface), see the dataviz palette reference.
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK2 = "#52514e"
GRID = "#ecebe8"
AXIS = "#c9c8c3"
BLUE = "#2a78d6"
BLUE_DK = "#104281"
BLUE_BAND = "#cde2fb"
ORANGE = "#eb6834"
AQUA = "#1baf7a"
RED = "#e34948"
MUTED_NODE = "#d6d5d0"
MUTED_EDGE = "#e7e6e2"
FONT = "-apple-system,'Segoe UI',Helvetica,Arial,sans-serif"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Chart:
    """Minimal line-chart builder producing standalone SVG."""

    def __init__(self, width, height, title, subtitle, xlabel, ylabel,
                 xlim, ylim, xticks, yticks, yfmt=lambda v: f"{v:g}",
                 xfmt=lambda v: f"{v:g}"):
        self.w, self.h = width, height
        self.ml, self.mr, self.mt, self.mb = 62, 24, 78, 52
        self.title, self.subtitle = title, subtitle
        self.xlabel, self.ylabel = xlabel, ylabel
        self.xlim, self.ylim = xlim, ylim
        self.xticks, self.yticks = xticks, yticks
        self.xfmt, self.yfmt = xfmt, yfmt
        self.body = []
        self.legend_items = []

    def X(self, x):
        x0, x1 = self.xlim
        return self.ml + (x - x0) / (x1 - x0) * (self.w - self.ml - self.mr)

    def Y(self, y):
        y0, y1 = self.ylim
        return self.h - self.mb - (y - y0) / (y1 - y0) * (self.h - self.mt - self.mb)

    def band(self, xs, lo, hi, color=BLUE_BAND, opacity=0.55):
        pts = [f"{self.X(x):.1f},{self.Y(v):.1f}" for x, v in zip(xs, hi)]
        pts += [f"{self.X(x):.1f},{self.Y(v):.1f}" for x, v in zip(reversed(xs), list(reversed(lo)))]
        self.body.append(f'<polygon points="{" ".join(pts)}" fill="{color}" fill-opacity="{opacity}"/>')

    def line(self, xs, ys, color, label=None, dash=None, width=2.5,
             direct_label=None, dl_dy=4, dl_dx=6):
        pts = " ".join(f"{self.X(x):.1f},{self.Y(y):.1f}" for x, y in zip(xs, ys))
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.body.append(
            f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="{width}"'
            f' stroke-linecap="round" stroke-linejoin="round"{d}/>')
        if label:
            self.legend_items.append((label, color, dash))
        if direct_label:
            self.body.append(
                f'<text x="{self.X(xs[-1]) + dl_dx:.1f}" y="{self.Y(ys[-1]) + dl_dy:.1f}"'
                f' font-size="12" font-weight="600" fill="{INK}">{esc(direct_label)}</text>')

    def hline(self, y, color=INK2, dash="5 4", label=None, label_x=None):
        self.body.append(
            f'<line x1="{self.ml}" y1="{self.Y(y):.1f}" x2="{self.w - self.mr}" y2="{self.Y(y):.1f}"'
            f' stroke="{color}" stroke-width="1.4" stroke-dasharray="{dash}"/>')
        if label:
            lx = label_x if label_x is not None else self.w - self.mr - 4
            self.body.append(
                f'<text x="{lx}" y="{self.Y(y) - 6:.1f}" text-anchor="end" font-size="12"'
                f' fill="{INK2}">{esc(label)}</text>')

    def vline(self, x, color=INK2, dash="5 4", label=None):
        self.body.append(
            f'<line x1="{self.X(x):.1f}" y1="{self.mt}" x2="{self.X(x):.1f}" y2="{self.h - self.mb}"'
            f' stroke="{color}" stroke-width="1.4" stroke-dasharray="{dash}"/>')
        if label:
            self.body.append(
                f'<text x="{self.X(x) + 6:.1f}" y="{self.h - self.mb - 10}" font-size="12"'
                f' fill="{INK2}">{esc(label)}</text>')

    def note(self, x, y, lines, anchor="start", size=12, color=INK2, weight="400"):
        t = [f'<text x="{self.X(x):.1f}" y="{self.Y(y):.1f}" text-anchor="{anchor}"'
             f' font-size="{size}" font-weight="{weight}" fill="{color}">']
        for i, ln in enumerate(lines):
            t.append(f'<tspan x="{self.X(x):.1f}" dy="{0 if i == 0 else 15}">{esc(ln)}</tspan>')
        t.append("</text>")
        self.body.append("".join(t))

    def render(self):
        s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}"'
             f' viewBox="0 0 {self.w} {self.h}" font-family="{FONT}">',
             f'<rect width="{self.w}" height="{self.h}" fill="{SURFACE}"/>',
             f'<text x="{self.ml}" y="26" font-size="17" font-weight="700" fill="{INK}">{esc(self.title)}</text>',
             f'<text x="{self.ml}" y="45" font-size="12.5" fill="{INK2}">{esc(self.subtitle)}</text>']
        # legend row
        lx = self.ml
        for label, color, dash in self.legend_items:
            d = f' stroke-dasharray="{dash}"' if dash else ""
            s.append(f'<line x1="{lx}" y1="{self.mt - 14}" x2="{lx + 22}" y2="{self.mt - 14}"'
                     f' stroke="{color}" stroke-width="3" stroke-linecap="round"{d}/>')
            lx += 28
            s.append(f'<text x="{lx}" y="{self.mt - 10}" font-size="12" fill="{INK}">{esc(label)}</text>')
            lx += 7.2 * len(label) + 24
        # grid + y ticks
        for v in self.yticks:
            s.append(f'<line x1="{self.ml}" y1="{self.Y(v):.1f}" x2="{self.w - self.mr}"'
                     f' y2="{self.Y(v):.1f}" stroke="{GRID}" stroke-width="1"/>')
            s.append(f'<text x="{self.ml - 8}" y="{self.Y(v) + 4:.1f}" text-anchor="end"'
                     f' font-size="12" fill="{INK2}">{esc(self.yfmt(v))}</text>')
        # x axis + ticks
        s.append(f'<line x1="{self.ml}" y1="{self.h - self.mb}" x2="{self.w - self.mr}"'
                 f' y2="{self.h - self.mb}" stroke="{AXIS}" stroke-width="1.2"/>')
        for v in self.xticks:
            s.append(f'<line x1="{self.X(v):.1f}" y1="{self.h - self.mb}" x2="{self.X(v):.1f}"'
                     f' y2="{self.h - self.mb + 5}" stroke="{AXIS}" stroke-width="1.2"/>')
            s.append(f'<text x="{self.X(v):.1f}" y="{self.h - self.mb + 20}" text-anchor="middle"'
                     f' font-size="12" fill="{INK2}">{esc(self.xfmt(v))}</text>')
        s.append(f'<text x="{(self.ml + self.w - self.mr) / 2:.0f}" y="{self.h - 12}"'
                 f' text-anchor="middle" font-size="12.5" fill="{INK2}">{esc(self.xlabel)}</text>')
        s.append(f'<text x="18" y="{(self.mt + self.h - self.mb) / 2:.0f}" font-size="12.5" fill="{INK2}"'
                 f' transform="rotate(-90 18 {(self.mt + self.h - self.mb) / 2:.0f})"'
                 f' text-anchor="middle">{esc(self.ylabel)}</text>')
        s.extend(self.body)
        s.append("</svg>")
        return "\n".join(s)


def save(name, svg):
    path = os.path.join(OUT_DIR, name)
    with open(path, "w") as f:
        f.write(svg + "\n")
    print("wrote", path)


# ---------------------------------------------------------------- simulation

def weighted_sample(weights, k, rng):
    """k distinct indices, inclusion probability increasing in weight
    (Efraimidis-Spirakis exponential-key sampling)."""
    keys = [(rng.random() ** (1.0 / w), i) for i, w in enumerate(weights)]
    return [i for _, i in heapq.nlargest(k, keys)]


def make_pool(n, sigma, rng):
    """Counterparty 'size' (annual volume share), heavy-tailed lognormal."""
    return [math.exp(rng.gauss(0.0, sigma)) for _ in range(n)]


def simulate(rng, n_pool, sigma, k_lo, k_hi, b_max, reps, grid):
    """Sequentially add borrowers; at each grid point record
    (node coverage, volume coverage, share of seen with >=2 views, Chao1 estimate)."""
    out = {b: [] for b in grid}
    for _ in range(reps):
        w = make_pool(n_pool, sigma, rng)
        tot = sum(w)
        counts = [0] * n_pool
        for b in range(1, b_max + 1):
            k = rng.randint(k_lo, k_hi)
            for i in weighted_sample(w, k, rng):
                counts[i] += 1
            if b in out:
                seen = [i for i, c in enumerate(counts) if c > 0]
                d = len(seen)
                f1 = sum(1 for i in seen if counts[i] == 1)
                f2 = sum(1 for i in seen if counts[i] == 2)
                chao = d + f1 * (f1 - 1) / (2.0 * (f2 + 1))
                vol = sum(w[i] for i in seen) / tot
                multi = (d - f1) / d if d else 0.0
                out[b].append((d / n_pool, vol, multi, chao))
    return out


def pct(sorted_vals, q):
    i = min(len(sorted_vals) - 1, max(0, int(round(q * (len(sorted_vals) - 1)))))
    return sorted_vals[i]


print("simulating offtaker tier...")
RNG = random.Random(20260809)
GRID_O = list(range(1, 151))
SIM_O = simulate(RNG, n_pool=300, sigma=1.6, k_lo=10, k_hi=50,
                 b_max=150, reps=300, grid=GRID_O)

print("simulating supplier tier...")
GRID_S = list(range(1, 151))
SIM_S = simulate(RNG, n_pool=5000, sigma=1.2, k_lo=50, k_hi=200,
                 b_max=150, reps=120, grid=GRID_S)


def mean(vals):
    return sum(vals) / len(vals)


# ------------------------------------------------- fig: offtaker coverage

def fig_coverage():
    c = Chart(920, 470,
              "Offtaker-tier coverage approaches a census",
              "Share of a 300-offtaker pool named by 1+ borrower (solid: uniform mixing; dashed: borrowers favor the same large buyers)",
              "Borrowers in the portfolio (B)", "Offtakers named (% of pool)",
              (0, 150), (0, 100),
              xticks=[0, 25, 50, 75, 100, 125, 150],
              yticks=[0, 20, 40, 60, 80, 100],
              yfmt=lambda v: f"{v:g}%")
    xs = list(range(0, 151))
    for k, color in ((10, AQUA), (30, ORANGE), (50, BLUE)):
        ys = [100 * (1 - (1 - k / 300.0) ** b) for b in xs]
        c.line(xs, ys, color, label=f"{k}/borrower")
    ys_sim = [0.0] + [100 * mean([r[0] for r in SIM_O[b]]) for b in GRID_O]
    c.line([0] + GRID_O, ys_sim, INK2, dash="6 5",
           label="10-50/borrower, size-biased")
    c.vline(100, label="B = 100")
    c.note(103, 55, ["Even when every borrower gravitates to the",
                     "same large buyers (dashed), 100 borrowers still",
                     "name the bulk of the pool; what is missed",
                     "is the small tail - see the volume view."])
    save("bb-offtaker-coverage.svg", c.render())


# ------------------------------------- fig: volume vs identity coverage

def fig_volume():
    c = Chart(920, 470,
              "Your blind spot is the small tail, not the core",
              "Size-biased sampling: large counterparties are captured first, so volume coverage outruns name coverage",
              "Borrowers in the portfolio (B)", "Coverage (% of pool)",
              (0, 150), (0, 100),
              xticks=[0, 25, 50, 75, 100, 125, 150],
              yticks=[0, 20, 40, 60, 80, 100],
              yfmt=lambda v: f"{v:g}%")
    xs = [0] + GRID_O
    vol = [0.0] + [100 * mean([r[1] for r in SIM_O[b]]) for b in GRID_O]
    nod = [0.0] + [100 * mean([r[0] for r in SIM_O[b]]) for b in GRID_O]
    c.line(xs, vol, BLUE, label="Share of tier volume flowing through named offtakers")
    c.line(xs, nod, ORANGE, label="Share of offtaker names on your map")
    b_ref = 40
    y_hi = 100 * mean([r[1] for r in SIM_O[b_ref]])
    y_lo = 100 * mean([r[0] for r in SIM_O[b_ref]])
    x_ref = c.X(b_ref)
    c.body.append(f'<line x1="{x_ref:.1f}" y1="{c.Y(y_hi):.1f}" x2="{x_ref:.1f}" y2="{c.Y(y_lo):.1f}"'
                  f' stroke="{INK2}" stroke-width="1.4" stroke-dasharray="3 3"/>')
    c.note(b_ref + 3, (y_hi + y_lo) / 2 + 2,
           ["the gap: names you lack are",
            "the smallest slice of flow"])
    save("bb-volume-coverage.svg", c.render())


# --------------------------------------------- fig: capture-recapture

def fig_capture():
    grid = [b for b in GRID_O if b >= 3 and b <= 100]
    med, lo, hi, seen = [], [], [], []
    for b in grid:
        vals = sorted(min(r[3], 460) for r in SIM_O[b])
        med.append(pct(vals, 0.5))
        lo.append(pct(vals, 0.05))
        hi.append(pct(vals, 0.95))
        seen.append(300 * mean([r[0] for r in SIM_O[b]]))
    c = Chart(920, 470,
              "Sizing the market you do not finance",
              "Chao capture-recapture lower bound on the total offtaker pool, from borrower-list overlap (true pool: 300; band: 5th-95th pct of 300 runs)",
              "Borrowers in the portfolio (B)", "Estimated offtakers in the whole market",
              (0, 100), (0, 460),
              xticks=[0, 20, 40, 60, 80, 100],
              yticks=[0, 100, 200, 300, 400])
    c.band(grid, lo, hi)
    c.line(grid, med, BLUE, label="Provable pool size (Chao lower bound, median)")
    c.line(grid, seen, ORANGE, label="Distinct offtakers actually seen")
    c.hline(300, label="true pool size (300)", label_x=None)
    c.note(32, 105, ["Overlap between borrowers' counterparty lists proves how much",
                     "market exists beyond your book, long before you have seen it:",
                     "at B=25 you have named ~180 offtakers but can already assert",
                     "the pool holds at least ~230-270."])
    save("bb-capture-recapture.svg", c.render())


# --------------------------------------- fig: cross-validation / fraud

def fig_crossval():
    c = Chart(920, 470,
              "Cross-validation density: when one view becomes several",
              "Share of visible counterparties independently reported by 2+ borrowers - the basis for benchmarking and double-pledge detection",
              "Borrowers in the portfolio (B)", "Visible counterparties with 2+ views (%)",
              (0, 150), (0, 100),
              xticks=[0, 25, 50, 75, 100, 125, 150],
              yticks=[0, 20, 40, 60, 80, 100],
              yfmt=lambda v: f"{v:g}%")
    xs = [1] + GRID_O[1:]
    off = [0.0] + [100 * mean([r[2] for r in SIM_O[b]]) for b in GRID_O[1:]]
    sup = [0.0] + [100 * mean([r[2] for r in SIM_S[b]]) for b in GRID_S[1:]]
    c.line(xs, off, BLUE, label="Offtakers (pool ~300)")
    c.line(xs, sup, ORANGE, label="Suppliers (pool ~5,000)")
    c.note(78, 40, ["A counterparty seen by one borrower is a data point;",
                    "seen by several it is a benchmark - and a pledged asset",
                    "appearing twice becomes detectable fraud."])
    save("bb-crossval.svg", c.render())


# --------------------------------------------------- fig: network panels

def fig_network():
    rng = random.Random(7)
    W, H = 960, 560
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}"'
         f' viewBox="0 0 {W} {H}" font-family="{FONT}">',
         f'<rect width="{W}" height="{H}" fill="{SURFACE}"/>',
         f'<text x="24" y="30" font-size="17" font-weight="700" fill="{INK}">'
         f'What financing illuminates: one neighborhood vs a portfolio</text>',
         f'<text x="24" y="49" font-size="12.5" fill="{INK2}">'
         f'Suppliers &#8594; traders &#8594; offtakers; financing a trader lights up its 1-hop'
         f' neighborhood and monthly edge weights (volumes, prices, aging)</text>']

    n_sup, n_tr, n_off = 16, 7, 9
    sup_y = [95 + i * 26 for i in range(n_sup)]
    tr_y = [130 + i * 57 for i in range(n_tr)]
    off_y = [110 + i * 44 for i in range(n_off)]
    # edges: trader -> suppliers, trader -> offtakers (indices)
    tr_sup = {t: sorted(rng.sample(range(n_sup), rng.randint(3, 5))) for t in range(n_tr)}
    tr_off = {t: sorted(weighted_sample([3.0 if o < 3 else 1.0 for o in range(n_off)],
                                        rng.randint(2, 3), rng)) for t in range(n_tr)}
    tr_tr = [(1, 3), (2, 5)]
    # force a shared supplier for the double-pledge callout in panel B
    shared_sup = 8
    for t in (0, 2, 4):
        if shared_sup not in tr_sup[t]:
            tr_sup[t] = sorted(tr_sup[t][:-1] + [shared_sup])

    def panel(x0, financed, subtitle, show_flags):
        p = [f'<text x="{x0 + 18}" y="86" font-size="14" font-weight="600" fill="{INK}">{esc(subtitle)}</text>']
        sx, tx, ox = x0 + 60, x0 + 235, x0 + 405
        lit_sup, lit_off = set(), set()
        off_views = {o: 0 for o in range(n_off)}
        sup_views = {i: 0 for i in range(n_sup)}
        for t in financed:
            lit_sup.update(tr_sup[t])
            lit_off.update(tr_off[t])
            for o in tr_off[t]:
                off_views[o] += 1
            for i in tr_sup[t]:
                sup_views[i] += 1
        # edges first (dark ones muted)
        for t in range(n_tr):
            lit = t in financed
            col = BLUE if lit else MUTED_EDGE
            wdt = 1.8 if lit else 1
            for i in tr_sup[t]:
                p.append(f'<line x1="{sx}" y1="{sup_y[i]}" x2="{tx}" y2="{tr_y[t]}"'
                         f' stroke="{col}" stroke-width="{wdt}" stroke-opacity="{0.75 if lit else 1}"/>')
            for o in tr_off[t]:
                p.append(f'<line x1="{tx}" y1="{tr_y[t]}" x2="{ox}" y2="{off_y[o]}"'
                         f' stroke="{col}" stroke-width="{wdt}" stroke-opacity="{0.75 if lit else 1}"/>')
        for a, b in tr_tr:
            lit = a in financed or b in financed
            p.append(f'<path d="M {tx - 14} {tr_y[a]} C {tx - 60} {(tr_y[a] + tr_y[b]) / 2},'
                     f' {tx - 60} {(tr_y[a] + tr_y[b]) / 2}, {tx - 14} {tr_y[b]}"'
                     f' fill="none" stroke="{BLUE if lit else MUTED_EDGE}"'
                     f' stroke-width="{1.8 if lit else 1}" stroke-dasharray="4 3"/>')
        # nodes
        for i, y in enumerate(sup_y):
            if show_flags and i == shared_sup and sup_views[i] >= 2:
                p.append(f'<circle cx="{sx}" cy="{y}" r="6" fill="{RED}"/>')
                p.append(f'<text x="{sx + 12}" y="{y + 4}" font-size="11.5" font-weight="600"'
                         f' fill="{RED}" stroke="{SURFACE}" stroke-width="4"'
                         f' paint-order="stroke">&#9888; pledged to 3 borrowers</text>')
            else:
                fill = AQUA if i in lit_sup else MUTED_NODE
                p.append(f'<circle cx="{sx}" cy="{y}" r="4.5" fill="{fill}"/>')
        for t, y in enumerate(tr_y):
            fill = BLUE if t in financed else MUTED_NODE
            p.append(f'<rect x="{tx - 7}" y="{y - 7}" width="14" height="14" rx="3" fill="{fill}"/>')
            if t in financed:
                p.append(f'<circle cx="{tx}" cy="{y}" r="12" fill="none" stroke="{BLUE}"'
                         f' stroke-width="1.4" stroke-opacity="0.5"/>')
        for o, y in enumerate(off_y):
            fill = AQUA if o in lit_off else MUTED_NODE
            p.append(f'<circle cx="{ox}" cy="{y}" r="6" fill="{fill}"/>')
            if show_flags and off_views[o] >= 2:
                p.append(f'<circle cx="{ox}" cy="{y}" r="10" fill="none" stroke="{BLUE_DK}" stroke-width="2"/>')
        for label, x in (("suppliers", sx), ("traders", tx), ("offtakers", ox)):
            p.append(f'<text x="{x}" y="{70}" text-anchor="middle" font-size="12" fill="{INK2}">{label}</text>')
        return p

    s += panel(0, financed={3}, subtitle="A. One borrower: an island of visibility", show_flags=False)
    s += panel(480, financed={0, 2, 3, 4, 6}, subtitle="B. Portfolio: overlapping neighborhoods", show_flags=True)
    s.append(f'<line x1="480" y1="70" x2="480" y2="{H - 60}" stroke="{GRID}" stroke-width="1.4"/>')
    # legend
    ly = H - 26
    items = [("financed trader", BLUE, "rect"), ("visible counterparty", AQUA, "circ"),
             ("dark (unobserved)", MUTED_NODE, "circ"), ("2+ independent views", BLUE_DK, "ring"),
             ("double-pledge alert", RED, "circ")]
    lx = 24
    for label, col, shape in items:
        if shape == "rect":
            s.append(f'<rect x="{lx}" y="{ly - 9}" width="12" height="12" rx="3" fill="{col}"/>')
        elif shape == "ring":
            s.append(f'<circle cx="{lx + 6}" cy="{ly - 3}" r="6" fill="none" stroke="{col}" stroke-width="2"/>')
        else:
            s.append(f'<circle cx="{lx + 6}" cy="{ly - 3}" r="5.5" fill="{col}"/>')
        lx += 18
        s.append(f'<text x="{lx}" y="{ly + 1}" font-size="12" fill="{INK}">{label}</text>')
        lx += 7.0 * len(label) + 26
    s.append("</svg>")
    save("bb-network.svg", "\n".join(s))


fig_network()
fig_coverage()
fig_volume()
fig_capture()
fig_crossval()

# numbers quoted in the doc
b100 = SIM_O[100]
print(f"B=100 size-biased: name coverage {100 * mean([r[0] for r in b100]):.1f}%, "
      f"volume coverage {100 * mean([r[1] for r in b100]):.2f}%, "
      f"multi-view share {100 * mean([r[2] for r in b100]):.1f}%")
b100s = SIM_S[100]
print(f"B=100 suppliers: name coverage {100 * mean([r[0] for r in b100s]):.1f}%, "
      f"volume coverage {100 * mean([r[1] for r in b100s]):.2f}%, "
      f"multi-view share {100 * mean([r[2] for r in b100s]):.1f}%")
for b in (10, 25, 50):
    vals = sorted(min(r[3], 460) for r in SIM_O[b])
    print(f"B={b}: Chao median {pct(vals, .5):.0f}, 5-95pct [{pct(vals, .05):.0f}, {pct(vals, .95):.0f}]")
print(f"uniform k=30: coverage at B=100 = {100 * (1 - (1 - 0.1) ** 100):.4f}%")
