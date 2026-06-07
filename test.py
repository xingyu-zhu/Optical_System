#!/usr/bin/env python3
"""
1x4 multi-panel range dumbbell plot:
- Remove y-axis
- Put panel title on the left side
- Keep x-axis in physical units
- Export PDF at 300 dpi
"""

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

plt.rcParams.update({
    "font.size": 24,
    "font.weight": "bold",
    "axes.labelweight": "bold",
})

PANELS = [
    {
        "title": "Compressive strength (MPa)",
        "xlim": (0, 55),
        "csh_range": (5.0, 10.0),
        "carbonate_range": (20.0, 50.0),
        "fmt": "{:.1f}",
    },
    {
        "title": "CO$_2$ sequestration (%)",
        "xlim": (0, 10),
        "csh_range": (0.0, 0.5),
        "carbonate_range": (6.0, 9.0),
        "fmt": "{:.1f}",
    },
    {
        "title": "Leachate pH",
        "xlim": (8, 13.5),
        "csh_range": (11.0, 13.0),
        "carbonate_range": (9.0, 10.5),
        "fmt": "{:.1f}",
    },
    {
        "title": "MIP porosity (%)",
        "xlim": (0, 35),
        "csh_range": (5.0, 15.0),
        "carbonate_range": (18.0, 25.0),
        "fmt": "{:.1f}",
    },
]

C_CSH_EDGE = "#6b7280"   # C-S-H marker edge (gray)
C_CARB = "#15803d"       # carbonate marker (green)
C_CONNECT = "#d1d5db"    # dumbbell line


def range_label(values, fmt):
    left, right = values
    return f"{fmt.format(left)}-{fmt.format(right)}"


def draw_range(ax, values, y, marker_face, marker_edge, marker_width, fmt, label_offset=0.034):
    left, right = values
    ax.hlines(y, left, right, color=C_CONNECT, linewidth=5.2, zorder=1)
    ax.scatter(
        [left, right],
        [y, y],
        s=160,
        facecolors=marker_face,
        edgecolors=marker_edge,
        linewidths=marker_width * 2,
        clip_on=False,
        zorder=3,
    )
    ax.text(
        (left + right) / 2,
        y + label_offset,
        range_label(values, fmt),
        ha="center",
        va="bottom" if label_offset >= 0 else "top",
        fontsize=23,
        fontweight="bold",
        color="black",
    )


def draw_panel(ax, panel):
    y = 0.0
    x0, x1 = panel["xlim"]
    xr = x1 - x0

    fmt = panel.get("fmt", "{:.2f}")
    draw_range(ax, panel["csh_range"], y, "white", C_CSH_EDGE, 1.6, fmt, label_offset=0.034)
    draw_range(ax, panel["carbonate_range"], y, C_CARB, C_CARB, 1.0, fmt, label_offset=0.034)

    # Left-side title (inside axes, near left edge)
    ax.text(
        x0 + 0.01 * xr,
        0.165,
        panel["title"],
        ha="left",
        va="bottom",
        fontsize=28,
        fontweight="bold",
        color="black",
    )

    # Axes style
    ax.set_xlim(x0, x1)
    ax.set_ylim(-0.15, 0.20)  # room for numeric labels and titles
    ax.set_yticks([])

    # Remove y-axis completely
    ax.spines["left"].set_visible(False)
    ax.yaxis.set_visible(False)

    # Keep clean black x-axis
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["bottom"].set_color("black")
    ax.spines["bottom"].set_linewidth(3.2)
    ax.tick_params(axis="x", colors="black", labelsize=23, width=2.8, length=7.0)
    for label in ax.get_xticklabels():
        label.set_fontweight("bold")


def main():
    # Compact overall figure height for 4 rows
    fig, axes = plt.subplots(
        4, 1,
        figsize=(13.2, 12.0),
        gridspec_kw={"hspace": 0.78}
    )

    for ax, panel in zip(axes, PANELS):
        draw_panel(ax, panel)

    legend_handles = [
        Line2D(
            [0], [0],
            marker="o",
            linestyle="None",
            markerfacecolor="white",
            markeredgecolor=C_CSH_EDGE,
            markeredgewidth=3.2,
            markersize=13.6,
            label="C-S-H based, without alkali activator",
        ),
        Line2D(
            [0], [0],
            marker="o",
            linestyle="None",
            markerfacecolor=C_CARB,
            markeredgecolor=C_CARB,
            markersize=13.6,
            label="Carbonate based, with 50 wt% inert skeleton wastes",
        ),
    ]

    fig.legend(
        handles=legend_handles,
        loc="lower center",
        ncol=1,
        frameon=False,
        bbox_to_anchor=(0.5, 0.005),
        fontsize=24,
        prop={"weight": "bold", "size": 24},
    )

    fig.subplots_adjust(left=0.055, right=0.995, top=0.965, bottom=0.22, hspace=0.78)
    fig.savefig("hydration_carbonation_dumbbell.pdf", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print("Saved: hydration_carbonation_dumbbell.pdf")


if __name__ == "__main__":
    main()
