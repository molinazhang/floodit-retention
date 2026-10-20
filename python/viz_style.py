"""Shared chart styling: a validated, colorblind-safe palette and recessive chrome.

Palette = the reference categorical order from the dataviz method (adjacent pairs clear the
CVD and normal-vision separation gates in light mode). Series colors are assigned in fixed
order by entity, never by rank. Text always uses the text tokens, never a series color.
"""
import matplotlib as mpl
import matplotlib.pyplot as plt

SURFACE = "#fcfcfb"
TEXT = "#0b0b0b"
TEXT2 = "#52514e"
GRID = "#e6e5e1"
SERIES = {"blue": "#2a78d6", "orange": "#eb6834", "aqua": "#1baf7a", "yellow": "#eda100"}
# Ordinal blue ramp for funnel stages (lightest step still >= 2:1 on the light surface).
ORDINAL_BLUE = ["#86b6ef", "#6da7ec", "#5598e7", "#3987e5", "#2a78d6", "#1c5cab"]


def apply():
    mpl.rcParams.update({
        "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
        "axes.edgecolor": GRID, "axes.linewidth": 1.0, "axes.spines.top": False, "axes.spines.right": False,
        "axes.grid": True, "grid.color": GRID, "grid.linewidth": 1.0, "grid.linestyle": "-",
        "axes.axisbelow": True, "xtick.color": TEXT2, "ytick.color": TEXT2, "text.color": TEXT,
        "axes.labelcolor": TEXT2, "axes.titlecolor": TEXT, "font.size": 10, "axes.titlesize": 12,
        "axes.titleweight": "bold", "axes.titlelocation": "left", "legend.frameon": False,
        "figure.dpi": 150, "savefig.dpi": 200, "savefig.bbox": "tight",
    })


def finish(fig, ax, title, subtitle=None, source=None, synthetic=False, source_y=-0.02):
    ax.set_title(title, pad=18 if subtitle else 8)
    if subtitle:
        ax.text(0, 1.02, subtitle, transform=ax.transAxes, fontsize=9, color=TEXT2, va="bottom")
    if source:
        fig.text(0.01, source_y, source, fontsize=8, color=TEXT2, ha="left", va="top")
    if synthetic:
        fig.text(0.5, 0.5, "SYNTHETIC SMOKE-TEST DATA\nNOT A RESULT", transform=fig.transFigure,
                 fontsize=26, color="#d03b3b", alpha=0.28, ha="center", va="center", rotation=20,
                 weight="bold", zorder=100)


def wilson(k, n, alpha=0.05):
    """Wilson score interval for a proportion; returns (p, lo, hi)."""
    from statsmodels.stats.proportion import proportion_confint
    if n == 0:
        return float("nan"), float("nan"), float("nan")
    lo, hi = proportion_confint(k, n, alpha=alpha, method="wilson")
    return k / n, lo, hi
