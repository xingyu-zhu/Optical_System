"""Parameter sweep configuration dialog."""

from __future__ import annotations

from typing import Any

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
)

from topology_display import build_component_display_names


class ParameterSweepDialog(QDialog):
    """Configure global parameter sweeps for the current topology."""

    HEADERS = ["启用", "深度", "组件", "参数", "起始", "终止", "步长", "单位"]

    def __init__(
        self,
        nodes: list[dict[str, Any]],
        sweeps: list[dict[str, Any]] | None = None,
        parent=None,
    ):
        super().__init__(parent)
        self.setWindowTitle("参数扫描设置")
        self.resize(920, 460)
        self._nodes = sorted(nodes, key=lambda item: int(item.get("id", 0)))
        self._node_by_id = {int(node.get("id", 0)): node for node in self._nodes}
        self._display_names = build_component_display_names(self._nodes)

        layout = QVBoxLayout(self)
        self.table = QTableWidget(self)
        self.table.setColumnCount(len(self.HEADERS))
        self.table.setHorizontalHeaderLabels(self.HEADERS)
        self.table.horizontalHeader().setStretchLastSection(True)
        layout.addWidget(self.table, 1)

        row_buttons = QHBoxLayout()
        add_button = QPushButton("添加扫描", self)
        remove_button = QPushButton("删除选中", self)
        add_button.clicked.connect(self._add_empty_row)
        remove_button.clicked.connect(self._remove_selected_rows)
        row_buttons.addWidget(add_button)
        row_buttons.addWidget(remove_button)
        row_buttons.addStretch(1)
        layout.addLayout(row_buttons)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel, self)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        for sweep in sweeps or []:
            self._add_row(sweep)
        if self.table.rowCount() == 0 and self._nodes:
            self._add_empty_row()

    def get_sweeps(self) -> list[dict[str, Any]]:
        sweeps: list[dict[str, Any]] = []
        for row in range(self.table.rowCount()):
            enabled_widget = self.table.cellWidget(row, 0)
            node_combo = self.table.cellWidget(row, 2)
            param_combo = self.table.cellWidget(row, 3)
            if not isinstance(node_combo, QComboBox) or not isinstance(
                param_combo, QComboBox
            ):
                continue
            node_id = int(node_combo.currentData())
            node = self._node_by_id.get(node_id)
            if not node:
                continue
            parameter = str(param_combo.currentText()).strip()
            if not parameter:
                continue
            sweeps.append(
                {
                    "enabled": bool(enabled_widget.isChecked())
                    if isinstance(enabled_widget, QCheckBox)
                    else True,
                    "depth": self._int_item(row, 1, default=1),
                    "node_id": node_id,
                    "component": str(node.get("name", "")),
                    "parameter": parameter,
                    "start": self._text_item(row, 4),
                    "stop": self._text_item(row, 5),
                    "step": self._text_item(row, 6),
                    "unit": self._current_param_unit(row),
                }
            )
        return sweeps

    def _add_empty_row(self) -> None:
        self._add_row({"enabled": True, "depth": 1})

    def _add_row(self, sweep: dict[str, Any]) -> None:
        row = self.table.rowCount()
        self.table.insertRow(row)

        enabled = QCheckBox(self.table)
        enabled.setChecked(bool(sweep.get("enabled", True)))
        enabled.setStyleSheet("margin-left: 12px;")
        self.table.setCellWidget(row, 0, enabled)

        self.table.setItem(row, 1, QTableWidgetItem(str(sweep.get("depth", 1))))

        node_combo = QComboBox(self.table)
        for node in self._nodes:
            node_id = int(node.get("id", 0))
            name = self._display_names.get(node_id, str(node.get("name", "")))
            node_combo.addItem(f"{node_id}: {name}", node_id)
        selected_node_id = self._safe_int(sweep.get("node_id"), self._first_node_id())
        self._set_combo_by_data(node_combo, selected_node_id)
        self.table.setCellWidget(row, 2, node_combo)

        param_combo = QComboBox(self.table)
        self.table.setCellWidget(row, 3, param_combo)
        node_combo.currentIndexChanged.connect(
            lambda _index, r=row: self._refresh_param_combo(r)
        )
        param_combo.currentIndexChanged.connect(
            lambda _index, r=row: self._sync_unit(r)
        )
        self._refresh_param_combo(row, preferred=str(sweep.get("parameter", "")))

        self.table.setItem(row, 4, QTableWidgetItem(str(sweep.get("start", ""))))
        self.table.setItem(row, 5, QTableWidgetItem(str(sweep.get("stop", ""))))
        self.table.setItem(row, 6, QTableWidgetItem(str(sweep.get("step", "1"))))
        self._set_readonly_item(row, 7, self._current_param_unit(row))

    def _refresh_param_combo(self, row: int, preferred: str = "") -> None:
        node_combo = self.table.cellWidget(row, 2)
        param_combo = self.table.cellWidget(row, 3)
        if not isinstance(node_combo, QComboBox) or not isinstance(
            param_combo, QComboBox
        ):
            return
        current = preferred or param_combo.currentText()
        param_combo.blockSignals(True)
        param_combo.clear()
        node = self._node_by_id.get(int(node_combo.currentData()))
        for key in (node.get("params") or {}) if node else {}:
            param_combo.addItem(str(key))
        if current:
            index = param_combo.findText(current)
            if index >= 0:
                param_combo.setCurrentIndex(index)
        param_combo.blockSignals(False)
        self._sync_unit(row)

    def _sync_unit(self, row: int) -> None:
        self._set_readonly_item(row, 7, self._current_param_unit(row))

    def _current_param_unit(self, row: int) -> str:
        node_combo = self.table.cellWidget(row, 2)
        param_combo = self.table.cellWidget(row, 3)
        if not isinstance(node_combo, QComboBox) or not isinstance(
            param_combo, QComboBox
        ):
            return ""
        node = self._node_by_id.get(int(node_combo.currentData()))
        value = (
            (node.get("params") or {}).get(param_combo.currentText()) if node else None
        )
        return str(value[1]) if isinstance(value, list) and len(value) > 1 else ""

    def _remove_selected_rows(self) -> None:
        rows = sorted({item.row() for item in self.table.selectedItems()}, reverse=True)
        for row in rows:
            self.table.removeRow(row)

    def _first_node_id(self) -> int:
        return int(self._nodes[0].get("id", 0)) if self._nodes else 0

    def _text_item(self, row: int, col: int) -> str:
        item = self.table.item(row, col)
        return item.text().strip() if item else ""

    def _set_readonly_item(self, row: int, col: int, text: str) -> None:
        item = QTableWidgetItem(str(text))
        item.setFlags(item.flags() & ~Qt.ItemIsEditable)
        self.table.setItem(row, col, item)

    def _int_item(self, row: int, col: int, default: int) -> int:
        try:
            return max(1, int(float(self._text_item(row, col))))
        except Exception:
            return default

    @staticmethod
    def _safe_int(value: Any, default: int) -> int:
        try:
            return int(value)
        except Exception:
            return default

    @staticmethod
    def _set_combo_by_data(combo: QComboBox, value: int) -> None:
        for index in range(combo.count()):
            if int(combo.itemData(index)) == int(value):
                combo.setCurrentIndex(index)
                return
