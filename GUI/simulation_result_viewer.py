"""Dialogs for analyzer plots and simulation result summaries."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

_MPL_CACHE = Path(__file__).resolve().parent / ".matplotlib_cache"
_MPL_CACHE.mkdir(exist_ok=True)
os.environ.setdefault("MPLCONFIGDIR", str(_MPL_CACHE))
os.environ.setdefault("XDG_CACHE_HOME", str(_MPL_CACHE))

from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from PyQt5.QtWidgets import QDialog, QTabWidget, QTableWidget, QTableWidgetItem, QVBoxLayout

from signal_plotter import draw_constellation, draw_optical_spectrum, draw_spectrum, float_or_default, scalar_text


class AnalyzerPlotDialog(QDialog):
    """Matplotlib-backed plot dialog for optical and electrical analyzers."""

    def __init__(self, title: str, parent=None):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.resize(920, 620)
        self.tabs = QTabWidget(self)
        layout = QVBoxLayout(self)
        layout.addWidget(self.tabs)

    @classmethod
    def optical(cls, node_name: str, workspace: dict[str, Any], parent=None) -> "AnalyzerPlotDialog":
        dialog = cls(f"光分析仪 - {node_name}", parent)
        signal = workspace.get("AnalyzerSignal")
        fs = float_or_default(workspace.get("AnalyzerFs"), 92e9)
        center = float_or_default(workspace.get("AnalyzerCenterFrequency"), 193.1e12)
        dialog._add_optical_spectrum(signal, fs, center)
        return dialog

    @classmethod
    def electrical(cls, node_name: str, workspace: dict[str, Any], parent=None) -> "AnalyzerPlotDialog":
        label = workspace.get("AnalyzerSignalLabel", "Electrical Signal")
        dialog = cls(f"电分析仪 - {node_name}", parent)
        signal = workspace.get("AnalyzerSignal")
        fs = float_or_default(workspace.get("AnalyzerFs"), 92e9)
        dialog._add_constellation(signal, str(label))
        dialog._add_electrical_spectrum(signal, fs, str(label))
        return dialog

    def _add_canvas(self, title: str) -> tuple[Figure, Any]:
        fig = Figure(figsize=(8.5, 4.8), tight_layout=True)
        canvas = FigureCanvas(fig)
        self.tabs.addTab(canvas, title)
        return fig, canvas

    def _add_optical_spectrum(self, signal: Any, fs: float, center_frequency: float) -> None:
        fig, canvas = self._add_canvas("光谱")
        ax = fig.add_subplot(111)
        draw_optical_spectrum(ax, signal, fs, center_frequency_hz=center_frequency)
        canvas.draw()

    def _add_electrical_spectrum(self, signal: Any, fs: float, label: str) -> None:
        fig, canvas = self._add_canvas("频谱")
        ax = fig.add_subplot(111)
        draw_spectrum(ax, signal, fs, title=f"{label} Spectrum")
        canvas.draw()

    def _add_constellation(self, signal: Any, label: str) -> None:
        fig, canvas = self._add_canvas("星座图")
        ax = fig.add_subplot(111)
        draw_constellation(ax, signal, title=f"{label} Constellation")
        canvas.draw()


class SimulationResultDialog(QDialog):
    """Table dialog for BER and SNR extracted from receiver DSP outputs."""

    def __init__(self, rows: list[dict[str, Any]], parent=None):
        super().__init__(parent)
        self.setWindowTitle("仿真结果")
        self.resize(620, 360)

        layout = QVBoxLayout(self)
        table = QTableWidget(self)
        table.setColumnCount(4)
        table.setHorizontalHeaderLabels(["节点ID", "组件", "SNR", "BER"])
        table.horizontalHeader().setStretchLastSection(True)
        table.setRowCount(max(1, len(rows)))

        if rows:
            for row, item in enumerate(rows):
                table.setItem(row, 0, QTableWidgetItem(str(item.get("node_id", ""))))
                table.setItem(row, 1, QTableWidgetItem(str(item.get("name", ""))))
                table.setItem(row, 2, QTableWidgetItem(scalar_text(item.get("SNR"))))
                table.setItem(row, 3, QTableWidgetItem(scalar_text(item.get("BER"))))
        else:
            table.setItem(0, 0, QTableWidgetItem("-"))
            table.setItem(0, 1, QTableWidgetItem("暂无 BER/SNR 结果，请先运行包含 RxDSP 的拓扑。"))
            table.setItem(0, 2, QTableWidgetItem("-"))
            table.setItem(0, 3, QTableWidgetItem("-"))

        layout.addWidget(table)
