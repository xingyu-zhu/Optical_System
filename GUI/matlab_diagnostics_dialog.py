"""MATLAB diagnostic dialog."""

from __future__ import annotations

import json

from PyQt5.QtWidgets import (
    QApplication,
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
)


class MatlabDiagnosticsDialog(QDialog):
    def __init__(self, engine_manager, parent=None):
        super().__init__(parent)
        self.engine_manager = engine_manager
        self.setWindowTitle("MATLAB 诊断")
        self.resize(760, 520)
        layout = QVBoxLayout(self)
        self.text = QPlainTextEdit(self)
        self.text.setReadOnly(True)
        layout.addWidget(self.text, 1)
        actions = QHBoxLayout()
        refresh = QPushButton("刷新", self)
        copy = QPushButton("复制", self)
        refresh.clicked.connect(self.refresh)
        copy.clicked.connect(
            lambda: QApplication.clipboard().setText(self.text.toPlainText())
        )
        actions.addWidget(refresh)
        actions.addWidget(copy)
        actions.addStretch(1)
        layout.addLayout(actions)
        buttons = QDialogButtonBox(QDialogButtonBox.Close, self)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)
        self.refresh()

    def refresh(self) -> None:
        info = self.engine_manager.diagnostics()
        labels = {
            "platform": "操作系统",
            "python": "Python",
            "python_version": "Python 版本",
            "frozen": "打包程序",
            "preferred_root": "首选 MATLAB",
            "detected_roots": "检测到的 MATLAB",
            "engine_paths": "Engine 路径",
            "engine_importable": "Engine 可导入",
            "engine_running": "Engine 已连接",
            "engine_owned": "当前会话由本程序启动",
            "engine_busy": "Engine 正在执行",
            "runtime_root": "运行时 MATLAB",
            "runtime_version": "运行时版本",
            "runtime_error": "运行时诊断错误",
            "last_error": "最近错误",
        }
        lines = []
        for key, value in info.items():
            display = json.dumps(value, ensure_ascii=False) if isinstance(value, (list, dict)) else str(value)
            lines.append(f"{labels.get(key, key)}: {display}")
        self.text.setPlainText("\n".join(lines))
