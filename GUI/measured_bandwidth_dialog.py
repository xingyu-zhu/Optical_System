"""Dialogs for importing and applying measured bandwidth datasets."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg
from matplotlib.figure import Figure
from PyQt5.QtCore import QThread, pyqtSignal
from PyQt5.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from measurement_dataset import DEVICE_LABELS, LANE_NAMES, MeasurementDatasetCatalog


class MeasurementImportWorker(QThread):
    """Read and validate measured files without blocking the GUI thread."""

    prepared = pyqtSignal(object)
    failed = pyqtSignal(str)

    def __init__(self, catalog: MeasurementDatasetCatalog, options: dict, parent=None):
        super().__init__(parent)
        self.catalog = catalog
        self.options = dict(options)

    def run(self) -> None:
        try:
            self.prepared.emit(self.catalog.prepare_import(**self.options))
        except Exception as exc:
            self.failed.emit(str(exc))


class MeasurementImportDialog(QDialog):
    def __init__(
        self,
        catalog: MeasurementDatasetCatalog,
        device_type: str | None = None,
        parent=None,
    ):
        super().__init__(parent)
        self.catalog = catalog
        self.prepared_dataset = None
        self._import_worker: MeasurementImportWorker | None = None
        self._device_locked = device_type in DEVICE_LABELS
        self.setWindowTitle("导入实测带宽数据")
        self.resize(900, 700)

        layout = QVBoxLayout(self)
        form = QFormLayout()
        self.name_edit = QLineEdit(self)
        self.device_combo = QComboBox(self)
        self.device_combo.addItem("调制器 (Tx)", "modulator")
        self.device_combo.addItem("相干接收机 (Rx)", "receiver")
        if self._device_locked:
            self.device_combo.setCurrentIndex(0 if device_type == "modulator" else 1)
            self.device_combo.setEnabled(False)
        self.device_combo.currentIndexChanged.connect(self._device_changed)
        form.addRow("数据集名称", self.name_edit)
        form.addRow("应用设备", self.device_combo)
        layout.addLayout(form)

        files_group = QGroupBox("通道文件（XI、XQ、YI、YQ）", self)
        files_layout = QGridLayout(files_group)
        self.file_edits: list[QLineEdit] = []
        self.file_buttons: list[QPushButton] = []
        for row, lane in enumerate(LANE_NAMES):
            edit = QLineEdit(files_group)
            button = QPushButton("浏览...", files_group)
            button.clicked.connect(lambda _checked=False, target=edit: self._browse(target))
            files_layout.addWidget(QLabel(lane, files_group), row, 0)
            files_layout.addWidget(edit, row, 1)
            files_layout.addWidget(button, row, 2)
            self.file_edits.append(edit)
            self.file_buttons.append(button)
        layout.addWidget(files_group)

        options = QHBoxLayout()
        self.frequency_column = QSpinBox(self)
        self.frequency_column.setRange(1, 256)
        self.frequency_column.setValue(1)
        self.response_column = QSpinBox(self)
        self.response_column.setRange(1, 256)
        self.response_column.setValue(3)
        self.frequency_unit = QComboBox(self)
        self.frequency_unit.addItems(["GHz", "MHz", "Hz"])
        self.normalize_check = QCheckBox("按 0.5–2 GHz 中位数归一化", self)
        self.normalize_check.setChecked(True)
        options.addWidget(QLabel("频率列", self))
        options.addWidget(self.frequency_column)
        options.addWidget(QLabel("响应列", self))
        options.addWidget(self.response_column)
        options.addWidget(QLabel("频率单位", self))
        options.addWidget(self.frequency_unit)
        options.addWidget(self.normalize_check)
        options.addStretch(1)
        layout.addLayout(options)

        preview_row = QHBoxLayout()
        self.preview_button = QPushButton("读取并预览", self)
        self.preview_button.clicked.connect(self._prepare_preview)
        self.import_progress = QProgressBar(self)
        self.import_progress.setObjectName("measurementImportProgress")
        self.import_progress.setRange(0, 0)
        self.import_progress.setTextVisible(False)
        self.import_progress.setFixedSize(180, 9)
        self.import_progress.setVisible(False)
        self.import_status_label = QLabel("正在读取文件...", self)
        self.import_status_label.setVisible(False)
        preview_row.addWidget(self.preview_button)
        preview_row.addWidget(self.import_progress)
        preview_row.addWidget(self.import_status_label)
        preview_row.addStretch(1)
        layout.addLayout(preview_row)

        self.figure = Figure(figsize=(8, 4), tight_layout=True)
        self.canvas = FigureCanvasQTAgg(self.figure)
        layout.addWidget(self.canvas, 1)

        self.summary_label = QLabel("尚未读取数据。", self)
        self.summary_label.setWordWrap(True)
        layout.addWidget(self.summary_label)

        self.buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel, self)
        self.buttons.button(QDialogButtonBox.Ok).setText("确认导入")
        self.buttons.button(QDialogButtonBox.Ok).setEnabled(False)
        self.buttons.accepted.connect(self._commit)
        self.buttons.rejected.connect(self.reject)
        layout.addWidget(self.buttons)
        self.name_edit.textEdited.connect(self._invalidate_preview)
        for edit in self.file_edits:
            edit.textEdited.connect(self._invalidate_preview)
        self.frequency_column.valueChanged.connect(self._invalidate_preview)
        self.response_column.valueChanged.connect(self._invalidate_preview)
        self.frequency_unit.currentIndexChanged.connect(self._invalidate_preview)
        self.normalize_check.toggled.connect(self._invalidate_preview)
        self._device_changed()

    def _device_changed(self) -> None:
        self.response_column.setValue(3 if self.device_combo.currentData() == "modulator" else 2)
        self.prepared_dataset = None
        self.buttons.button(QDialogButtonBox.Ok).setEnabled(False)

    def _browse(self, edit: QLineEdit) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择测试文件",
            edit.text().strip(),
            "测试数据 (*.xlsx *.csv *.tsv *.txt);;所有文件 (*)",
        )
        if path:
            edit.setText(path)
            self.prepared_dataset = None
            self.buttons.button(QDialogButtonBox.Ok).setEnabled(False)

    def _invalidate_preview(self, *_args) -> None:
        self.prepared_dataset = None
        self.buttons.button(QDialogButtonBox.Ok).setEnabled(False)

    def _prepare_preview(self) -> None:
        if self._import_worker is not None and self._import_worker.isRunning():
            return

        options = {
            "name": self.name_edit.text(),
            "device_type": self.device_combo.currentData(),
            "files": [edit.text().strip() for edit in self.file_edits],
            "frequency_column": self.frequency_column.value(),
            "response_column": self.response_column.value(),
            "frequency_unit": self.frequency_unit.currentText(),
            "normalize": self.normalize_check.isChecked(),
        }
        self.prepared_dataset = None
        self._set_importing(True)
        self._import_worker = MeasurementImportWorker(self.catalog, options, self)
        self._import_worker.prepared.connect(self._preview_ready)
        self._import_worker.failed.connect(self._preview_failed)
        self._import_worker.finished.connect(self._preview_finished)
        self._import_worker.start()

    def _preview_ready(self, payload: dict) -> None:
        self.prepared_dataset = payload
        self.figure.clear()
        axis = self.figure.add_subplot(111)
        summaries = []
        for lane in LANE_NAMES:
            response = payload["lanes"][lane]
            frequency = response["frequency_hz"]
            magnitude = response["magnitude_db"]
            plot_frequency, plot_magnitude = _preview_samples(frequency, magnitude)
            axis.plot(plot_frequency / 1e9, plot_magnitude, label=lane)
            bandwidth = response.get("bandwidth_3db_hz")
            bandwidth_text = "未越过 -3 dB" if bandwidth is None else f"{bandwidth / 1e9:.3f} GHz"
            summaries.append(
                f"{lane}: {len(frequency)} 点，0–{frequency[-1] / 1e9:.3f} GHz，-3 dB={bandwidth_text}"
            )
        max_frequency = max(
            payload["lanes"][lane]["frequency_hz"][-1] for lane in LANE_NAMES
        )
        reference_frequency = np.linspace(0, max_frequency, 800)
        default_bandwidth = 35e9 if payload["device_type"] == "modulator" else 25e9
        axis.plot(
            reference_frequency / 1e9,
            _bessel5_magnitude_db(reference_frequency, default_bandwidth),
            color="#222222",
            linestyle="--",
            linewidth=1.4,
            label=f"原始 Bessel5 ({default_bandwidth / 1e9:.0f} GHz)",
        )
        axis.axhline(-3, color="#666666", linestyle=":", linewidth=1)
        axis.set_xlabel("Frequency (GHz)")
        axis.set_ylabel("Magnitude (dB)")
        axis.grid(True, alpha=0.25)
        axis.legend(ncol=4)
        self.canvas.draw_idle()
        self.summary_label.setText("\n".join(summaries))
        self.buttons.button(QDialogButtonBox.Ok).setEnabled(True)

    def _preview_failed(self, message: str) -> None:
        self.summary_label.setText("读取失败。请检查文件、列号和频率单位。")
        QMessageBox.warning(self, "导入校验失败", message)

    def _preview_finished(self) -> None:
        self._set_importing(False)
        worker = self._import_worker
        self._import_worker = None
        if worker is not None:
            worker.deleteLater()

    def _set_importing(self, importing: bool) -> None:
        self.preview_button.setEnabled(not importing)
        self.name_edit.setEnabled(not importing)
        self.device_combo.setEnabled(
            not importing and not self._device_locked
        )
        self.frequency_column.setEnabled(not importing)
        self.response_column.setEnabled(not importing)
        self.frequency_unit.setEnabled(not importing)
        self.normalize_check.setEnabled(not importing)
        for widget in [*self.file_edits, *self.file_buttons]:
            widget.setEnabled(not importing)
        self.import_progress.setVisible(importing)
        self.import_status_label.setVisible(importing)
        self.buttons.button(QDialogButtonBox.Cancel).setEnabled(not importing)
        if importing:
            self.buttons.button(QDialogButtonBox.Ok).setEnabled(False)

    def reject(self) -> None:
        if self._import_worker is not None and self._import_worker.isRunning():
            return
        super().reject()

    def closeEvent(self, event) -> None:  # noqa: N802
        if self._import_worker is not None and self._import_worker.isRunning():
            event.ignore()
            return
        super().closeEvent(event)

    def _commit(self) -> None:
        if self.prepared_dataset is None:
            return
        try:
            self.catalog.commit(self.prepared_dataset)
        except Exception as exc:
            QMessageBox.critical(self, "导入失败", str(exc))
            return
        self.accept()


class MeasuredBandwidthManagerDialog(QDialog):
    def __init__(self, workspace_panel, catalog: MeasurementDatasetCatalog, cache_clear=None, parent=None):
        super().__init__(parent)
        self.workspace_panel = workspace_panel
        self.catalog = catalog
        self.cache_clear = cache_clear or (lambda: None)
        self.setWindowTitle("实测带宽数据集")
        self.resize(820, 540)
        layout = QVBoxLayout(self)

        self.table = QTableWidget(self)
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels(["名称", "设备", "四通道 -3 dB (GHz)", "数据集 ID", "创建时间"])
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        layout.addWidget(self.table, 1)

        data_actions = QHBoxLayout()
        import_button = QPushButton("导入数据集", self)
        delete_button = QPushButton("删除选中数据集", self)
        import_button.clicked.connect(self._import_dataset)
        delete_button.clicked.connect(self._delete_dataset)
        data_actions.addWidget(import_button)
        data_actions.addWidget(delete_button)
        data_actions.addStretch(1)
        layout.addLayout(data_actions)

        apply_group = QGroupBox("应用到当前设计", self)
        apply_layout = QGridLayout(apply_group)
        self.node_combo = QComboBox(apply_group)
        self.dataset_combo = QComboBox(apply_group)
        self.node_combo.currentIndexChanged.connect(self._refresh_dataset_combo)
        apply_button = QPushButton("使用选中实测数据", apply_group)
        original_button = QPushButton("使用原始模型", apply_group)
        default_button = QPushButton("恢复该组件默认参数", apply_group)
        apply_button.clicked.connect(self._apply_dataset)
        original_button.clicked.connect(self._use_original)
        default_button.clicked.connect(self._restore_component_defaults)
        apply_layout.addWidget(QLabel("组件", apply_group), 0, 0)
        apply_layout.addWidget(self.node_combo, 0, 1)
        apply_layout.addWidget(QLabel("数据集", apply_group), 1, 0)
        apply_layout.addWidget(self.dataset_combo, 1, 1)
        apply_layout.addWidget(apply_button, 2, 0)
        apply_layout.addWidget(original_button, 2, 1)
        apply_layout.addWidget(default_button, 2, 2)
        layout.addWidget(apply_group)

        buttons = QDialogButtonBox(QDialogButtonBox.Close, self)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)
        self._refresh_all()

    def _refresh_all(self) -> None:
        self._summaries = self.catalog.list()
        self.table.setRowCount(len(self._summaries))
        for row, item in enumerate(self._summaries):
            values = [
                item.name,
                DEVICE_LABELS.get(item.device_type, item.device_type),
                " / ".join(
                    "--" if item.lane_bandwidths_hz[lane] is None else f"{item.lane_bandwidths_hz[lane] / 1e9:.2f}"
                    for lane in LANE_NAMES
                ),
                item.dataset_id,
                item.created_at,
            ]
            for column, value in enumerate(values):
                self.table.setItem(row, column, QTableWidgetItem(str(value)))
        self.node_combo.clear()
        for node in self.workspace_panel.bandwidth_model_nodes():
            device = self.workspace_panel.bandwidth_device_type(node)
            model = (node.meta.model_config or {}).get("BandwidthModel", "IdealBessel")
            self.node_combo.addItem(
                f"{node.node_id}: {node.meta.name} [{model}]", (node.node_id, device)
            )
        self._refresh_dataset_combo()

    def _refresh_dataset_combo(self) -> None:
        self.dataset_combo.clear()
        data = self.node_combo.currentData()
        if not data:
            return
        device = data[1]
        active_dataset = ""
        node = self.workspace_panel._node_by_id(data[0])
        if node is not None:
            active_dataset = str((node.meta.model_config or {}).get("BandwidthDataset", ""))
        for item in self._summaries:
            if item.device_type == device:
                self.dataset_combo.addItem(f"{item.name} ({item.dataset_id})", item.dataset_id)
                if item.dataset_id == active_dataset:
                    self.dataset_combo.setCurrentIndex(self.dataset_combo.count() - 1)

    def _import_dataset(self) -> None:
        dialog = MeasurementImportDialog(self.catalog, parent=self)
        if dialog.exec_():
            self.cache_clear()
            self._refresh_all()

    def _delete_dataset(self) -> None:
        row = self.table.currentRow()
        if row < 0:
            return
        summary = self._summaries[row]
        if self.workspace_panel.dataset_in_use(summary.dataset_id):
            QMessageBox.warning(self, "数据集正在使用", "请先将相关组件切回原始模型或更换数据集。")
            return
        if QMessageBox.question(
            self,
            "删除数据集",
            f"删除数据集“{summary.name}”？此操作不会修改原始参数。",
        ) != QMessageBox.Yes:
            return
        self.catalog.delete(summary.dataset_id)
        self.cache_clear()
        self._refresh_all()

    def _apply_dataset(self) -> None:
        node_data = self.node_combo.currentData()
        dataset_id = self.dataset_combo.currentData()
        if not node_data or not dataset_id:
            QMessageBox.information(self, "应用实测数据", "请选择组件和匹配的数据集。")
            return
        self.workspace_panel.set_node_bandwidth_dataset(node_data[0], dataset_id)
        self.cache_clear()
        self._refresh_all()
        QMessageBox.information(self, "应用实测数据", "已切换为实测幅频响应；原始参数未被改写。")

    def _use_original(self) -> None:
        node_data = self.node_combo.currentData()
        if node_data:
            self.workspace_panel.use_original_bandwidth_model(node_data[0])
            self.cache_clear()
            self._refresh_all()

    def _restore_component_defaults(self) -> None:
        node_data = self.node_combo.currentData()
        if node_data:
            self.workspace_panel.restore_node_defaults(node_data[0])
            self.cache_clear()
            self._refresh_all()
            QMessageBox.information(self, "恢复默认参数", "该组件已恢复为代码声明的默认参数和原始带宽模型。")


def _bessel5_magnitude_db(frequency_hz, bandwidth_hz):
    x = np.asarray(frequency_hz, dtype=float) / float(bandwidth_hz)
    omega = 2 * np.pi * x * 0.3863
    real_part = 945 - 420 * omega**2 + 15 * omega**4
    imag_part = 945 * omega - 105 * omega**3 + omega**5
    response = 945 / (real_part + 1j * imag_part)
    return 20 * np.log10(np.maximum(np.abs(response), np.finfo(float).tiny))


def _preview_samples(frequency, magnitude, maximum_points: int = 4000):
    frequency_values = np.asarray(frequency, dtype=float)
    magnitude_values = np.asarray(magnitude, dtype=float)
    if frequency_values.size <= maximum_points:
        return frequency_values, magnitude_values
    indices = np.linspace(
        0, frequency_values.size - 1, maximum_points, dtype=np.int64
    )
    return frequency_values[indices], magnitude_values[indices]
