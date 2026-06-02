"""Application-wide style setup for GUI."""

from __future__ import annotations

from PyQt5.QtGui import QColor, QFont, QPalette
from PyQt5.QtWidgets import QApplication, QStyleFactory


def apply_app_style(app: QApplication) -> None:
    """Apply palette, style, and stylesheet consistent with legacy GUI."""
    app.setStyle(QStyleFactory.create("Fusion"))

    palette = QPalette()
    palette.setColor(QPalette.Window, QColor(240, 240, 245))
    palette.setColor(QPalette.WindowText, QColor(0, 0, 0))
    palette.setColor(QPalette.Base, QColor(255, 255, 255))
    palette.setColor(QPalette.AlternateBase, QColor(245, 245, 245))
    palette.setColor(QPalette.ToolTipBase, QColor(255, 255, 220))
    palette.setColor(QPalette.ToolTipText, QColor(0, 0, 0))
    palette.setColor(QPalette.Text, QColor(0, 0, 0))
    palette.setColor(QPalette.Button, QColor(240, 240, 240))
    palette.setColor(QPalette.ButtonText, QColor(0, 0, 0))
    palette.setColor(QPalette.Link, QColor(0, 120, 215))
    palette.setColor(QPalette.Highlight, QColor(0, 120, 215))
    palette.setColor(QPalette.HighlightedText, QColor(255, 255, 255))
    app.setPalette(palette)

    font = QFont()
    font.setPointSize(10)
    app.setFont(font)

    app.setStyleSheet(
        """
        QMainWindow { background-color: #f0f0f0; }

        QMenuBar, QToolBar {
            background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #f6f7fa, stop:1 #e3e5e9);
            border-bottom: 1px solid #c0c0c0;
        }

        QStatusBar {
            background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #f6f7fa, stop:1 #d9dce5);
            border-top: 1px solid #c0c0c0;
        }

        QStatusBar QLabel { padding: 2px 8px; border-right: 1px solid #c0c0c0; }

        QLabel#windowTitleLabel {
            font-size: 22pt; font-weight: bold; color: white; padding: 10px;
            background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #3498db, stop:1 #2c3e50);
        }

        QLabel#panelTitle { font-size: 11pt; font-weight: bold; color: #2c3e50; }
        QLabel#panelBody { color: #5f6c7b; font-size: 9.5pt; }

        QSplitter::handle { background-color: #d6dce6; height: 2px; }

        QListWidget {
            background: #ffffff;
            border: 1px solid #c8ced8;
            border-radius: 4px;
            outline: none;
        }

        QListWidget::item { padding: 4px 6px; }
        QListWidget::item:selected { background-color: #dbeafe; color: #143b5f; }

        QTextEdit {
            background-color: #f8f8f8;
            border: 1px solid #c8c8c8;
            border-radius: 4px;
            selection-background-color: #0078d7;
            font-family: 'Menlo', 'Monaco', 'Courier New', monospace;
        }

        QPushButton {
            background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #f6f7fa, stop:1 #e3e5e9);
            border: 1px solid #b8bcc4;
            border-radius: 4px;
            padding: 6px 12px;
        }
        QPushButton:hover { background: #edf3fb; border-color: #8faed3; }
        QPushButton:pressed { background: #dbe7f4; }

        QLineEdit {
            border: 1px solid #c8c8c8;
            border-radius: 4px;
            padding: 5px;
            background-color: #ffffff;
        }

        QProgressBar {
            border: 1px solid #c0c0c0;
            border-radius: 3px;
            text-align: center;
            background-color: #f0f0f0;
        }
        QProgressBar::chunk { background-color: #0078d7; border-radius: 2px; }
        """
    )
