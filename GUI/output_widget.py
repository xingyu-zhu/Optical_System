"""Independent output widget for displaying Python and MATLAB logs."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from PyQt5.QtCore import QThread, Qt, pyqtSignal
from PyQt5.QtGui import QColor, QFontDatabase, QTextCharFormat, QTextCursor
from PyQt5.QtWidgets import QHBoxLayout, QLabel, QPushButton, QTextEdit, QVBoxLayout, QWidget

from matlab_engine_manager import MatlabEngineManager


class MatlabConnectWorker(QThread):
    connected = pyqtSignal(object)
    failed = pyqtSignal(str)

    def __init__(self, engine_manager: MatlabEngineManager):
        super().__init__()
        self.engine_manager = engine_manager

    def run(self) -> None:
        try:
            engine = self.engine_manager.start()
            self.connected.emit(engine)
        except Exception as exc:
            self.failed.emit(str(exc))


class OutputWidget(QWidget):
    """Standalone output widget connected to MatlabEngineManager."""

    engine_status_changed = pyqtSignal(str)

    def __init__(
        self,
        parent=None,
        show_timestamp: bool = True,
        engine_manager: Optional[MatlabEngineManager] = None,
    ):
        super().__init__(parent)
        self.show_timestamp = show_timestamp
        self.engine_manager = engine_manager or MatlabEngineManager()
        self._connect_worker = None
        self._setup_ui()

    def _setup_ui(self) -> None:
        title = QLabel("输出信息")
        title.setStyleSheet("font-weight: bold; font-size: 11pt;")

        self.stats_label = QLabel("MATLAB函数调用区暂未启用")
        self.stats_label.setStyleSheet("color: gray; font-size: 9pt;")

        self.output_text = QTextEdit(self)
        self.output_text.setReadOnly(True)
        self.output_text.setLineWrapMode(QTextEdit.NoWrap)
        self.output_text.setFont(QFontDatabase.systemFont(QFontDatabase.FixedFont))

        self.connect_btn = QPushButton("连接 MATLAB 引擎")
        self.connect_btn.clicked.connect(self.connect_matlab)

        clear_btn = QPushButton("清除")
        clear_btn.clicked.connect(self.clear)

        header_row = QHBoxLayout()
        header_row.addWidget(title)
        header_row.addStretch(1)
        header_row.addWidget(self.stats_label)

        button_row = QHBoxLayout()
        button_row.addWidget(self.connect_btn)
        button_row.addStretch(1)
        button_row.addWidget(clear_btn)

        layout = QVBoxLayout(self)
        layout.addLayout(header_row)
        layout.addWidget(self.output_text)
        layout.addLayout(button_row)
        self.setLayout(layout)

    def clear(self) -> None:
        self.output_text.clear()

    def append_python(self, message: str) -> None:
        self.append_message(message, source="PYTHON")

    def append_matlab(self, message: str) -> None:
        self.append_message(message, source="MATLAB")

    def append_message(self, message: str, source: str = "INFO") -> None:
        source_upper = source.upper()
        time_text = datetime.now().strftime("%H:%M:%S") if self.show_timestamp else ""
        prefix = f"[{time_text}] [{source_upper}] " if time_text else f"[{source_upper}] "

        fmt = QTextCharFormat()
        fmt.setForeground(self._source_color(source_upper))

        cursor = self.output_text.textCursor()
        cursor.movePosition(QTextCursor.End)
        cursor.insertText(prefix, fmt)
        cursor.insertText(f"{message}\n")

        self.output_text.setTextCursor(cursor)
        self.output_text.ensureCursorVisible()

    def connect_matlab(self) -> None:
        """Start or reuse MATLAB engine asynchronously and log status."""
        if self._connect_worker is not None and self._connect_worker.isRunning():
            return

        self.engine_status_changed.emit("Starting")
        self.connect_btn.setEnabled(False)
        self.append_matlab("正在连接 MATLAB 引擎...")

        worker = MatlabConnectWorker(self.engine_manager)
        self._connect_worker = worker
        worker.connected.connect(self._on_connect_success)
        worker.failed.connect(self._on_connect_failed)
        worker.finished.connect(lambda: self.connect_btn.setEnabled(True))
        worker.start()

    def _on_connect_success(self, engine: object) -> None:
        self.append_matlab(f"Engine ready: {engine}")
        self.engine_status_changed.emit("Ready")

    def _on_connect_failed(self, error_text: str) -> None:
        self.append_message(f"Failed to connect MATLAB: {error_text}", source="ERROR")
        self.engine_status_changed.emit("Error")

    def log_python_output(self, message: str) -> None:
        self.append_python(message)

    @staticmethod
    def _source_color(source: str) -> QColor:
        if source == "PYTHON":
            return QColor("#2E7D32")
        if source == "MATLAB":
            return QColor("#1565C0")
        if source == "ERROR":
            return QColor("#C62828")
        return QColor(Qt.black)
