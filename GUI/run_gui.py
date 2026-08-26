"""GUI entrypoint with startup splash and MATLAB engine initialization."""

from __future__ import annotations

import sys

from PyQt5.QtCore import Qt, QThread, pyqtSignal
from PyQt5.QtWidgets import (
    QApplication,
    QFileDialog,
    QLabel,
    QMessageBox,
    QProgressBar,
    QVBoxLayout,
    QWidget,
)

from app_style import apply_app_style
from main_window import MainWindow
from matlab_engine_manager import MatlabEngineManager


class MatlabStartupWorker(QThread):
    """Background worker that starts MATLAB engine before main window shows."""

    progress_changed = pyqtSignal(int, str)
    startup_succeeded = pyqtSignal(object)
    startup_failed = pyqtSignal(str)

    def __init__(self, manager: MatlabEngineManager | None = None, parent=None):
        super().__init__(parent)
        self.manager = manager or MatlabEngineManager()

    def run(self) -> None:
        try:
            self.progress_changed.emit(12, "正在初始化启动流程")
            root = self.manager.preferred_matlab_root
            detected = f"检测到 {root.name}" if root else "未检测到默认 MATLAB 安装"
            self.progress_changed.emit(38, detected)
            self.progress_changed.emit(72, "正在启动 MATLAB 引擎")
            self.manager.start()
            self.progress_changed.emit(100, "MATLAB 引擎已就绪")
            self.startup_succeeded.emit(self.manager)
        except Exception as exc:
            self.startup_failed.emit(str(exc))


class StartupWindow(QWidget):
    """Initialization window shown before launching the main window."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("startupWindow")
        self.setWindowTitle("系统初始化")
        self.setFixedSize(720, 280)
        self.setWindowFlags(Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint)

        self.title_label = QLabel("多维复用超高速光接入端到端系统仿真平台", self)
        self.title_label.setObjectName("startupTitle")
        self.title_label.setAlignment(Qt.AlignCenter)

        self.dev_label = QLabel("香港理工大学深圳研究院光子研究中心", self)
        self.dev_label.setObjectName("startupDeveloper")
        self.dev_label.setAlignment(Qt.AlignCenter)

        self.version_label = QLabel("版本号：3.10", self)
        self.version_label.setObjectName("startupVersion")
        self.version_label.setAlignment(Qt.AlignCenter)

        self.status_label = QLabel("正在初始化...", self)
        self.status_label.setObjectName("startupStatus")
        self.status_label.setAlignment(Qt.AlignCenter)

        self.progress_bar = QProgressBar(self)
        self.progress_bar.setObjectName("startupProgress")
        self.progress_bar.setRange(0, 0)
        self.progress_bar.setTextVisible(False)
        self.progress_bar.setFixedHeight(12)

        self.setStyleSheet(
            """
            QWidget#startupWindow {
                background: qlineargradient(
                    x1: 0, y1: 0, x2: 1, y2: 1,
                    stop: 0 #f4f9ff, stop: 1 #dbeaf7
                );
            }
            QLabel#startupTitle {
                color: #123b63;
                font-size: 26px;
                font-weight: 700;
            }
            QLabel#startupDeveloper {
                color: #365d7d;
                font-size: 15px;
            }
            QLabel#startupVersion {
                color: #5f7890;
                font-size: 13px;
            }
            QLabel#startupStatus {
                color: #1f5f8f;
                background: rgba(248, 252, 255, 210);
                border: 1px solid #b9d3ea;
                border-radius: 6px;
                padding: 7px;
            }
            QProgressBar#startupProgress {
                background: #e8f1f8;
                border: 1px solid #8eb9dc;
                border-radius: 5px;
            }
            QProgressBar#startupProgress::chunk {
                background: qlineargradient(
                    x1: 0, y1: 0, x2: 1, y2: 0,
                    stop: 0 #2f80c2, stop: 1 #65b6e8
                );
                border-radius: 4px;
            }
            """
        )

        layout = QVBoxLayout(self)
        layout.setContentsMargins(44, 30, 44, 30)
        layout.setSpacing(8)
        layout.addStretch(1)
        layout.addWidget(self.title_label)
        layout.addWidget(self.dev_label)
        layout.addWidget(self.version_label)
        layout.addSpacing(14)
        layout.addWidget(self.status_label)
        layout.addWidget(self.progress_bar)
        layout.addStretch(1)

    def update_progress(self, value: int, text: str) -> None:
        self.status_label.setText(text)


def _move_window_to_startup_screen(startup: QWidget, window: QWidget) -> None:
    screen = startup.screen()
    if screen is None:
        return
    geo = screen.availableGeometry()
    target = window.frameGeometry()
    target.moveCenter(geo.center())
    window.move(target.topLeft())


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("多维复用超高速光接入端到端系统仿真平台")
    app.setOrganizationName("香港理工大学光子研究院")
    apply_app_style(app)

    startup = StartupWindow()
    startup.adjustSize()
    startup.move(
        (app.primaryScreen().availableGeometry().center() - startup.rect().center())
    )
    startup.show()

    startup_attempts = {"manual_prompted": False}
    worker = None

    def on_progress(value: int, text: str) -> None:
        startup.update_progress(value, text)

    def start_worker(manager: MatlabEngineManager | None = None) -> None:
        nonlocal worker
        worker = MatlabStartupWorker(manager)
        worker.progress_changed.connect(on_progress)
        worker.startup_failed.connect(on_failed)
        worker.startup_succeeded.connect(on_succeeded)
        worker.start()
        app._startup_worker = worker

    def on_failed(error_text: str) -> None:
        startup.update_progress(100, "MATLAB 引擎启动失败")
        if not startup_attempts["manual_prompted"]:
            startup_attempts["manual_prompted"] = True
            reply = QMessageBox.question(
                startup,
                "选择 MATLAB 路径",
                "自动启动 MATLAB 引擎失败。\n\n选择“是”可手动指定 MATLAB；选择“否”进入离线模式。",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.Yes,
            )
            if reply == QMessageBox.Yes:
                selected = QFileDialog.getExistingDirectory(
                    startup,
                    "选择 MATLAB 安装目录或 extern/engines/python 目录",
                    "",
                )
                if selected:
                    manager = MatlabEngineManager()
                    try:
                        root = manager.set_matlab_root(selected, persist=True)
                        startup.update_progress(50, f"已选择 MATLAB: {root}")
                        start_worker(manager)
                        return
                    except Exception as exc:
                        QMessageBox.warning(startup, "MATLAB 路径无效", str(exc))

        startup.close()
        manager = worker.manager if worker is not None else MatlabEngineManager()
        window = MainWindow(
            engine_manager=manager,
            initial_engine_status="Offline",
            offline_mode=True,
        )
        window.output_widget.append_message(
            f"Startup error: {error_text}", source="ERROR"
        )
        _move_window_to_startup_screen(startup, window)
        window.show()
        app._main_window = window

    def on_succeeded(engine_manager: MatlabEngineManager) -> None:
        startup.close()
        window = MainWindow(
            engine_manager=engine_manager, initial_engine_status="Ready"
        )
        window.output_widget.append_matlab("MATLAB engine initialized during startup.")
        _move_window_to_startup_screen(startup, window)
        window.show()
        app._main_window = window

    start_worker()
    app._startup_window = startup

    return app.exec_()


if __name__ == "__main__":
    raise SystemExit(main())
