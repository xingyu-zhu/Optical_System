#!/usr/bin/env python3
"""
1x4 multi-panel dumbbell plot (compressed height):
- Remove y-axis
- Put panel title on the left side
- Keep x-axis in physical units
- Export PDF at 300 dpi
"""

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

PANELS = [
    {
        "title": "Compressive strength (MPa)",
        "xlim": (0, 65),
        "hydration": 32.0,
        "carbonation": 56.0,
        "literature_range": (25.0, 60.0),
        "fmt": "{:.1f}",
    },
    {
        "title": "CO$_2$ uptake (wt%)",
        "xlim": (0, 20),
        "hydration": 4.2,
        "carbonation": 16.8,
        "literature_range": (2.0, 18.0),
        "fmt": "{:.1f}",
    },
    {
        "title": "Leachate pH",
        "xlim": (8, 13),
        "hydration": 11.9,
        "carbonation": 9.6,
        "literature_range": (9.2, 12.5),
        "fmt": "{:.1f}",
    },
    {
        "title": "Porosity (%)",
        "xlim": (0, 45),
        "hydration": 31.0,
        "carbonation": 24.0,
        "literature_range": (18.0, 36.0),
        "fmt": "{:.1f}",
    },
]

C_HYD_EDGE = "#6b7280"   # hydration marker edge (gray)
C_CARB = "#15803d"       # carbonation marker (green)
C_CONNECT = "#d1d5db"    # dumbbell line
C_RANGE = "#9ca3af"      # literature range


def draw_panel(ax, panel):
    y = 0.0
    x0, x1 = panel["xlim"]
    xr = x1 - x0

    # Literature range behind points
    if panel.get("literature_range") is not None:
        xmin, xmax = panel["literature_range"]
        ax.hlines(y, xmin, xmax, color=C_RANGE, linewidth=1.8, alpha=0.35, zorder=1)

    # Connector
    ax.plot(
        [panel["hydration"], panel["carbonation"]],
        [y, y],
        color=C_CONNECT,
        linewidth=1.8,
        zorder=2,
    )

    # Points
    ax.scatter(
        [panel["hydration"]],
        [y],
        s=52,
        facecolors="white",
        edgecolors=C_HYD_EDGE,
        linewidths=1.5,
        zorder=3,
    )
    ax.scatter(
        [panel["carbonation"]],
        [y],
        s=52,
        facecolors=C_CARB,
        edgecolors=C_CARB,
        linewidths=1.0,
        zorder=3,
    )

    # Numeric labels (auto above/below to avoid overlap when points are close)
    hv = panel["hydration"]
    cv = panel["carbonation"]
    close = abs(hv - cv) < 0.15 * xr
    h_off = 0.09
    c_off = -0.10 if not close else 0.09

    fmt = panel.get("fmt", "{:.2f}")
    ax.text(hv, y + h_off, fmt.format(hv), ha="center", va="bottom", fontsize=9, color="black")
    ax.text(cv, y + c_off, fmt.format(cv), ha="center", va="bottom" if c_off > 0 else "top", fontsize=9, color="black")

    # Left-side title (inside axes, near left edge)
    ax.text(
        x0 + 0.01 * xr,
        0.145,
        panel["title"],
        ha="left",
        va="bottom",
        fontsize=10.5,
        fontweight="bold",
        color="black",
    )

    # Axes style
    ax.set_xlim(x0, x1)
    ax.set_ylim(-0.16, 0.16)  # compressed panel height
    ax.set_yticks([])

    # Remove y-axis completely
    ax.spines["left"].set_visible(False)
    ax.yaxis.set_visible(False)

    # Keep clean black x-axis
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["bottom"].set_color("black")
    ax.spines["bottom"].set_linewidth(1.0)
    ax.tick_params(axis="x", colors="black", labelsize=9, width=1, length=3)


def main():
    # Compact overall figure height for 4 rows
    fig, axes = plt.subplots(
        4, 1,
        figsize=(8.4, 6.4),
        gridspec_kw={"hspace": 0.35}
    )

    for ax, panel in zip(axes, PANELS):
        draw_panel(ax, panel)

    legend_handles = [
        Line2D(
            [0], [0],
            marker="o",
            linestyle="None",
            markerfacecolor="white",
            markeredgecolor=C_HYD_EDGE,
            markeredgewidth=1.5,
            markersize=6.8,
            label="Hydration",
        ),
        Line2D(
            [0], [0],
            marker="o",
            linestyle="None",
            markerfacecolor=C_CARB,
            markeredgecolor=C_CARB,
            markersize=6.8,
            label="Carbonation",
        ),
        Line2D(
            [0, 1], [0, 0],
            color=C_RANGE,
            linewidth=1.8,
            alpha=0.35,
            label="Literature range",
        ),
    ]

    fig.legend(
        handles=legend_handles,
        loc="lower center",
        ncol=3,
        frameon=False,
        bbox_to_anchor=(0.5, 0.005),
        fontsize=9,
    )

    fig.tight_layout(rect=(0.035, 0.055, 0.995, 1.0))
    fig.savefig("hydration_carbonation_dumbbell.pdf", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print("Saved: hydration_carbonation_dumbbell.pdf")


if __name__ == "__main__":
    main()