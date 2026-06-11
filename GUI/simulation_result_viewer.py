"""Dialogs for analyzer plots and simulation result summaries."""

# ruff: noqa: E402

from __future__ import annotations

from typing import Any

from matplotlib_config import configure_matplotlib_cache

configure_matplotlib_cache()

from matplotlib import rcParams
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from PyQt5.QtWidgets import (
    QDialog,
    QTableWidget,
    QTableWidgetItem,
    QTabWidget,
    QVBoxLayout,
)

from signal_plotter import (
    _as_array,
    draw_constellation,
    draw_optical_spectrum,
    draw_spectrum,
    draw_time_waveform,
    float_or_default,
    scalar_text,
)

rcParams["font.sans-serif"] = [
    "PingFang SC",
    "Hiragino Sans GB",
    "Heiti SC",
    "Arial Unicode MS",
    "Noto Sans CJK SC",
    "Microsoft YaHei",
    "SimHei",
    "DejaVu Sans",
]
rcParams["axes.unicode_minus"] = False


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
    def optical(
        cls, node_name: str, workspace: dict[str, Any], parent=None
    ) -> "AnalyzerPlotDialog":
        dialog = cls(f"光分析仪 - {node_name}", parent)
        signal = workspace.get("AnalyzerSignal")
        fs = float_or_default(workspace.get("AnalyzerFs"), 92e9)
        center = float_or_default(workspace.get("AnalyzerCenterFrequency"), 193.1e12)
        dialog._add_optical_spectrum(
            signal,
            fs,
            center,
            workspace.get("AnalyzerOpticalFrequencyTHz"),
            workspace.get("AnalyzerOpticalPowerdBm"),
        )
        return dialog

    @classmethod
    def electrical(
        cls, node_name: str, workspace: dict[str, Any], parent=None
    ) -> "AnalyzerPlotDialog":
        label = workspace.get("AnalyzerSignalLabel", "Electrical Signal")
        dialog = cls(f"电分析仪 - {node_name}", parent)
        signal = workspace.get("AnalyzerSignal")
        constellation = workspace.get("AnalyzerConstellation", signal)
        fs = float_or_default(workspace.get("AnalyzerFs"), 92e9)
        sample_step = float_or_default(workspace.get("AnalyzerSignalSampleStep"), 1.0)
        spectrum_freq = workspace.get("AnalyzerSpectrumFrequencyGHz")
        spectrum_psd = workspace.get("AnalyzerSpectrumPSDdBHz")
        dialog._add_time_waveform(signal, fs, str(label), sample_step)
        dialog._add_constellation(constellation, str(label))
        dialog._add_electrical_spectrum(
            signal, fs, str(label), spectrum_freq, spectrum_psd
        )
        return dialog

    def _add_canvas(self, title: str) -> tuple[Figure, Any]:
        fig = Figure(figsize=(8.5, 4.8), tight_layout=True)
        canvas = FigureCanvas(fig)
        self.tabs.addTab(canvas, title)
        return fig, canvas

    def _add_optical_spectrum(
        self,
        signal: Any,
        fs: float,
        center_frequency: float,
        optical_freq_thz: Any = None,
        optical_power_dbm: Any = None,
    ) -> None:
        fig, canvas = self._add_canvas("光谱")
        ax = fig.add_subplot(111)
        freq = _as_array(optical_freq_thz)
        power = _as_array(optical_power_dbm)
        if freq.size and power.size and freq.size == power.size:
            x = freq.reshape(-1)
            y = power.reshape(-1)
            ax.plot(x, y, color="#003366", linewidth=2.0)
            ax.set_title("Optical Spectrum")
            ax.set_xlabel("Frequency (THz)")
            ax.set_ylabel("Power (dBm)")
            center_thz = center_frequency / 1e12 if center_frequency else None
            if center_thz:
                ax.set_xlim(center_thz - 0.05, center_thz + 0.05)
            ax.set_ylim(-90, 10)
            ax.grid(True, alpha=0.25)
        else:
            draw_optical_spectrum(ax, signal, fs, center_frequency_hz=center_frequency)
        canvas.draw()

    def _add_electrical_spectrum(
        self,
        signal: Any,
        fs: float,
        label: str,
        spectrum_freq_ghz: Any = None,
        spectrum_psd_db_hz: Any = None,
    ) -> None:
        fig, canvas = self._add_canvas("频谱")
        ax = fig.add_subplot(111)
        freq = _as_array(spectrum_freq_ghz)
        psd = _as_array(spectrum_psd_db_hz)
        if freq.size and psd.size and freq.size == psd.size:
            ax.plot(freq.reshape(-1), psd.reshape(-1), color="#c74440", linewidth=1.5)
            ax.set_title(f"{label} Spectrum")
            ax.set_xlabel("Frequency (GHz)")
            ax.set_ylabel("Power Spectral Density (dB/Hz)")
            ax.set_xlim(-40, 40)
            ax.grid(True, alpha=0.25)
        else:
            draw_spectrum(ax, signal, fs, title=f"{label} Spectrum")
        canvas.draw()

    def _add_time_waveform(
        self, signal: Any, fs: float, label: str, sample_step: float = 1.0
    ) -> None:
        fig, canvas = self._add_canvas("时域波形")
        ax = fig.add_subplot(111)
        draw_time_waveform(
            ax, signal, fs=fs, sample_step=sample_step, title=f"{label} Time Waveform"
        )
        canvas.draw()

    def _add_constellation(self, signal: Any, label: str) -> None:
        fig, canvas = self._add_canvas("星座图")
        ax = fig.add_subplot(111)
        draw_constellation(ax, signal, title=f"{label} Constellation")
        canvas.draw()


class SimulationResultDialog(QDialog):
    """Table dialog for BER and SNR extracted from receiver DSP outputs."""

    def __init__(
        self,
        rows: list[dict[str, Any]],
        sweep: dict[str, Any] | None = None,
        parent=None,
    ):
        super().__init__(parent)
        self.setWindowTitle("仿真结果")
        self.resize(860, 560)

        layout = QVBoxLayout(self)
        self.tabs = QTabWidget(self)
        layout.addWidget(self.tabs)

        self._add_summary_tab(rows)
        if any(item.get("constellation") is not None for item in rows):
            self._add_result_constellation_tab(rows)
        if sweep and sweep.get("rows"):
            self._add_sweep_tab(sweep.get("rows", []))
            self._add_budget_tab(sweep.get("power_budget", []), sweep.get("rows", []))

    def _add_summary_tab(self, rows: list[dict[str, Any]]) -> None:
        table = QTableWidget(self)
        table.setColumnCount(4)
        table.setHorizontalHeaderLabels(["节点编号", "组件", "SNR", "BER"])
        table.horizontalHeader().setStretchLastSection(True)
        table.setRowCount(max(1, len(rows)))

        if rows:
            for row, item in enumerate(rows):
                table.setItem(
                    row,
                    0,
                    QTableWidgetItem(
                        str(item.get("display_node_id", item.get("node_id", "")))
                    ),
                )
                table.setItem(row, 1, QTableWidgetItem(str(item.get("name", ""))))
                table.setItem(row, 2, QTableWidgetItem(scalar_text(item.get("SNR"))))
                table.setItem(row, 3, QTableWidgetItem(scalar_text(item.get("BER"))))
        else:
            table.setItem(0, 0, QTableWidgetItem("-"))
            table.setItem(
                0, 1, QTableWidgetItem("暂无 BER/SNR 结果，请先运行包含 RxDSP 的拓扑。")
            )
            table.setItem(0, 2, QTableWidgetItem("-"))
            table.setItem(0, 3, QTableWidgetItem("-"))

        self.tabs.addTab(table, "BER/SNR")

    def _add_result_constellation_tab(self, rows: list[dict[str, Any]]) -> None:
        tab = QTabWidget(self)
        added = False
        for item in rows:
            constellation = item.get("constellation")
            if constellation is None:
                continue
            fig = Figure(figsize=(5.0, 4.6), tight_layout=True)
            canvas = FigureCanvas(fig)
            ax = fig.add_subplot(111)
            label = str(item.get("name", "Constellation"))
            draw_constellation(ax, constellation, title=f"{label} Constellation")
            canvas.draw()
            tab.addTab(canvas, label)
            added = True
        if added:
            self.tabs.addTab(tab, "星座图")

    def _add_sweep_tab(self, rows: list[dict[str, Any]]) -> None:
        table = QTableWidget(self)
        headers = [
            "扫描点",
            "节点编号",
            "组件",
            "扫描参数",
            "发射功率(dBm)",
            "接收光功率(dBm)",
            "SNR",
            "BER",
        ]
        table.setColumnCount(len(headers))
        table.setHorizontalHeaderLabels(headers)
        table.horizontalHeader().setStretchLastSection(True)
        table.setRowCount(len(rows))

        for row_idx, item in enumerate(rows):
            values = [
                item.get("point_index", ""),
                item.get("display_node_id", item.get("node_id", "")),
                item.get("component", ""),
                item.get(
                    "sweep_label", self._sweep_values_text(item.get("sweep_values"))
                ),
                scalar_text(item.get("tx_power_dbm")),
                scalar_text(item.get("rop_dbm")),
                scalar_text(item.get("SNR")),
                scalar_text(item.get("BER")),
            ]
            for col, value in enumerate(values):
                table.setItem(row_idx, col, QTableWidgetItem(str(value)))

        self.tabs.addTab(table, "参数扫描")

    def _add_budget_tab(
        self, budget_rows: list[dict[str, Any]], sweep_rows: list[dict[str, Any]]
    ) -> None:
        tab = QTabWidget(self)

        budget_table = QTableWidget(self)
        headers = [
            "发射功率(dBm)",
            "节点编号",
            "组件",
            "灵敏度(dBm)",
            "功率预算(dB)",
            "FEC门限",
        ]
        budget_table.setColumnCount(len(headers))
        budget_table.setHorizontalHeaderLabels(headers)
        budget_table.horizontalHeader().setStretchLastSection(True)
        budget_table.setRowCount(max(1, len(budget_rows)))
        if budget_rows:
            for row_idx, item in enumerate(budget_rows):
                values = [
                    scalar_text(item.get("tx_power_dbm")),
                    item.get("display_node_id", item.get("node_id", "")),
                    item.get("component", ""),
                    scalar_text(item.get("sensitivity_dbm")),
                    scalar_text(item.get("power_budget_db")),
                    scalar_text(item.get("fec_limit")),
                ]
                for col, value in enumerate(values):
                    budget_table.setItem(row_idx, col, QTableWidgetItem(str(value)))
        else:
            budget_table.setItem(
                0, 0, QTableWidgetItem("需要同时配置发射功率扫描和接收光功率扫描。")
            )
        tab.addTab(budget_table, "数据")

        fig = Figure(figsize=(7.8, 4.6), tight_layout=True)
        canvas = FigureCanvas(fig)
        ax = fig.add_subplot(111)
        plotted = self._scatter_budget_metric(
            ax,
            budget_rows,
            y_key="power_budget_db",
            title="功率预算 vs 发射功率",
            y_label="功率预算 (dB)",
        )
        if not plotted:
            message = (
                "BER 扫描点不足，无法插值功率预算"
                if budget_rows
                else "暂无功率预算数据"
            )
            ax.text(0.5, 0.5, message, ha="center", va="center", transform=ax.transAxes)
        ax.grid(True, alpha=0.25)
        canvas.draw()
        tab.addTab(canvas, "功率预算图")

        fig_sens = Figure(figsize=(7.8, 4.6), tight_layout=True)
        canvas_sens = FigureCanvas(fig_sens)
        ax_sens = fig_sens.add_subplot(111)
        plotted_sens = self._scatter_budget_metric(
            ax_sens,
            budget_rows,
            y_key="sensitivity_dbm",
            title="接收机灵敏度 vs 发射功率",
            y_label="接收机灵敏度 (dBm @ BER=1e-2)",
        )
        if not plotted_sens:
            message = (
                "BER 扫描点不足，无法插值接收机灵敏度"
                if budget_rows
                else "暂无接收机灵敏度数据"
            )
            ax_sens.text(
                0.5, 0.5, message, ha="center", va="center", transform=ax_sens.transAxes
            )
        ax_sens.grid(True, alpha=0.25)
        canvas_sens.draw()
        tab.addTab(canvas_sens, "接收机灵敏度")

        fig2 = Figure(figsize=(7.8, 4.6), tight_layout=True)
        canvas2 = FigureCanvas(fig2)
        ax2 = fig2.add_subplot(111)
        plotted = False
        grouped: dict[tuple[str, Any], list[dict[str, Any]]] = {}
        for row in sweep_rows:
            if row.get("rop_dbm") is None or row.get("BER") is None:
                continue
            key = (str(row.get("component", "Receiver")), row.get("tx_power_dbm"))
            grouped.setdefault(key, []).append(row)
        for (component, tx_power), group in sorted(
            grouped.items(),
            key=lambda item: (item[0][0], item[0][1] is None, item[0][1]),
        ):
            group = sorted(group, key=lambda item: float(item["rop_dbm"]))
            x = [float(item["rop_dbm"]) for item in group]
            y = [max(float(item["BER"]), 1e-12) for item in group]
            if x and y:
                tx_label = (
                    f", Tx={scalar_text(tx_power)} dBm" if tx_power is not None else ""
                )
                line = ax2.plot(
                    x, y, linewidth=1.4, alpha=0.7, label=f"{component}{tx_label}"
                )[0]
                ax2.scatter(x, y, s=38, alpha=0.9, color=line.get_color())
                plotted = True
        if plotted:
            ax2.set_yscale("log")
            ax2.axhline(
                1e-2, color="0.25", linestyle="--", linewidth=1.0, label="FEC=1e-2"
            )
            ax2.set_title("BER vs 接收光功率")
            ax2.set_xlabel("接收光功率 (dBm)")
            ax2.set_ylabel("BER")
            ax2.legend(loc="best", fontsize=8)
        else:
            ax2.text(
                0.5,
                0.5,
                "暂无 BER/ROP 扫描曲线",
                ha="center",
                va="center",
                transform=ax2.transAxes,
            )
        ax2.grid(True, alpha=0.25)
        canvas2.draw()
        tab.addTab(canvas2, "BER曲线")

        self.tabs.addTab(tab, "功率预算")

    @staticmethod
    def _scatter_budget_metric(
        ax, budget_rows: list[dict[str, Any]], y_key: str, title: str, y_label: str
    ) -> bool:
        grouped: dict[str, list[dict[str, Any]]] = {}
        for item in budget_rows:
            if item.get("tx_power_dbm") is None or item.get(y_key) is None:
                continue
            grouped.setdefault(str(item.get("component", "Receiver")), []).append(item)

        plotted = False
        for component, group in sorted(grouped.items()):
            group = sorted(group, key=lambda item: float(item["tx_power_dbm"]))
            x = [float(item["tx_power_dbm"]) for item in group]
            y = [float(item[y_key]) for item in group]
            if not x or not y:
                continue
            line = ax.plot(x, y, linewidth=1.4, alpha=0.7, label=component)[0]
            ax.scatter(x, y, s=48, alpha=0.9, color=line.get_color())
            plotted = True

        if plotted:
            ax.set_title(title)
            ax.set_xlabel("发射光功率 (dBm)")
            ax.set_ylabel(y_label)
            if len(grouped) > 1:
                ax.legend(loc="best", fontsize=8)
        return plotted

    @staticmethod
    def _sweep_values_text(values: Any) -> str:
        if not isinstance(values, dict):
            return ""
        return ", ".join(f"{key}={scalar_text(value)}" for key, value in values.items())
