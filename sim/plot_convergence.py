#!/usr/bin/env python3
"""Plot the convergence curve written by `mc_model converge`.

usage: python3 sim/plot_convergence.py docs/convergence_10M.csv
Writes docs/convergence_light.png and docs/convergence_dark.png (needs matplotlib).
"""
import csv
import math
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

rows = list(csv.DictReader(open(sys.argv[1])))
n = [int(r["samples"]) for r in rows]
err = [max(float(r["abs_rel_error_pct"]), 1e-5) for r in rows]   # log axis can't show 0
p = math.pi / 4
sigma = [4 * math.sqrt(p * (1 - p) / k) / math.pi * 100 for k in n]  # binomial noise, in %

x_labels = {10: "10", 100: "100", 1e3: "1k", 1e4: "10k", 1e5: "100k", 1e6: "1M", 1e7: "10M"}
themes = {
    "light": dict(bg="#fcfcfb", fg="#0b0b0b", fg2="#52514e", grid="#e4e3df", s1="#2a78d6"),
    "dark":  dict(bg="#1a1a19", fg="#ffffff", fg2="#c3c2b7", grid="#383835", s1="#3987e5"),
}

for name, t in themes.items():
    fig, ax = plt.subplots(figsize=(8, 4.2), dpi=150)
    fig.patch.set_facecolor(t["bg"])
    ax.set_facecolor(t["bg"])

    ax.plot(n, sigma, color=t["fg2"], lw=1.5, ls=(0, (4, 3)), label="Expected sampling noise (1σ)")
    ax.plot(n, err, color=t["s1"], lw=2, label="Measured error (C model, bit-exact with the RTL)")
    ax.plot([n[-1]], [err[-1]], "o", ms=7, color=t["s1"], mec=t["bg"], mew=2)
    ax.annotate(f"{err[-1]:.4f}% at {n[-1]/1e6:g}M", (n[-1], err[-1]), xytext=(-12, -1),
                textcoords="offset points", ha="right", va="center", color=t["fg"], fontsize=9)

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: x_labels.get(v, "")))
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:g}%"))
    ax.xaxis.set_minor_formatter(FuncFormatter(lambda v, _: ""))
    ax.yaxis.set_minor_formatter(FuncFormatter(lambda v, _: ""))
    ax.set_xlabel("Samples", color=t["fg2"])
    ax.set_ylabel("Relative error vs π", color=t["fg2"])
    ax.set_title("π estimate converges at the rate pure sampling noise predicts",
                 color=t["fg"], fontsize=11, loc="left")
    ax.grid(True, which="major", color=t["grid"], lw=0.8)
    ax.set_axisbelow(True)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(colors=t["fg2"], which="both", length=0)
    legend = ax.legend(frameon=False, loc="lower left", fontsize=9)
    for text in legend.get_texts():
        text.set_color(t["fg"])

    fig.tight_layout()
    fig.savefig(f"docs/convergence_{name}.png", facecolor=t["bg"])
    plt.close(fig)
