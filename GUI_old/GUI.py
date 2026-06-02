import sys
import os
import traceback
import time
from pathlib import Path

from PyQt6.QtCore import Qt, QTimer, QThread, pyqtSignal
from PyQt6.QtGui import QPalette, QColor, QFont, QIcon, QPixmap, QPainter, QLinearGradient
from PyQt6.QtWidgets import QApplication, QSplashScreen, QMessageBox
from PyQt6.QtWidgets import QStyleFactory

from MainWindow import MainWindow

class OpticalSimulationApp(QApplication):
    """光通信仿真应用程序"""

    def __init__(self, argv):
        super().__init__(argv)

        self.setApplicationName("光通信仿真实验平台")
        self.setApplicationVersion("1.0.0")
        self.setOrganizationName("香港理工大学光子研究中心")

        # 设置样式
        self.setup_style()

        # 设置字体
        self.setup_fonts()

        # 创建主窗口
        self.main_window = None

        # 启动画面
        self.splash = None

        # 启动状态
        self.startup_error = ""

        # 异常处理
        sys.excepthook = self.exception_hook

    def setup_style(self):
        """设置应用程序样式"""
        # 使用Fusion样式
        self.setStyle(QStyleFactory.create("Fusion"))

        # 自定义调色板
        palette = QPalette()
        palette.setColor(QPalette.ColorRole.Window, QColor(240, 240, 245))
        palette.setColor(QPalette.ColorRole.WindowText, QColor(0, 0, 0))
        palette.setColor(QPalette.ColorRole.Base, QColor(255, 255, 255))
        palette.setColor(QPalette.ColorRole.AlternateBase, QColor(245, 245, 245))
        palette.setColor(QPalette.ColorRole.ToolTipBase, QColor(255, 255, 220))
        palette.setColor(QPalette.ColorRole.ToolTipText, QColor(0, 0, 0))
        palette.setColor(QPalette.ColorRole.Text, QColor(0, 0, 0))
        palette.setColor(QPalette.ColorRole.Button, QColor(240, 240, 240))
        palette.setColor(QPalette.ColorRole.ButtonText, QColor(0, 0, 0))
        palette.setColor(QPalette.ColorRole.BrightText, QColor(255, 255, 255))
        palette.setColor(QPalette.ColorRole.Link, QColor(0, 120, 215))
        palette.setColor(QPalette.ColorRole.Highlight, QColor(0, 120, 215))
        palette.setColor(QPalette.ColorRole.HighlightedText, QColor(255, 255, 255))

        self.setPalette(palette)

        # 设置样式表
        self.setStyleSheet("""
            QMainWindow {
                background-color: #f0f0f0;
            }

            QDockWidget {
                titlebar-normal-icon: url(dock-restore.png);
                titlebar-close-icon: url(dock-close.png);
            }

            QDockWidget::title {
                background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
                    stop:0 #f6f7fa, stop:1 #d9dce5);
                padding-left: 10px;
                padding-top: 5px;
                padding-bottom: 5px;
                border: 1px solid #c0c0c0;
                border-top-left-radius: 5px;
                border-top-right-radius: 5px;
            }

            QDockWidget::close-button, QDockWidget::float-button {
                border: 1px solid transparent;
                background: transparent;
                padding: 2px;
            }

            QDockWidget::close-button:hover, QDockWidget::float-button:hover {
                background: rgba(0, 0, 0, 0.1);
            }

            QDockWidget::close-button:pressed, QDockWidget::float-button:pressed {
                background: rgba(0, 0, 0, 0.2);
            }

            QToolBar {
                background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
                    stop:0 #f6f7fa, stop:1 #e3e5e9);
                border-bottom: 1px solid #c0c0c0;
                spacing: 3px;
                padding: 2px;
            }

            QToolBar QToolButton {
                background: transparent;
                border: 1px solid transparent;
                border-radius: 3px;
                padding: 5px;
                margin: 1px;
            }

            QToolBar QToolButton:hover {
                background: rgba(0, 0, 0, 0.1);
                border: 1px solid #a0a0a0;
            }

            QToolBar QToolButton:pressed {
                background: rgba(0, 0, 0, 0.2);
            }

            QToolBar QToolButton:checked {
                background: rgba(0, 120, 215, 0.2);
                border: 1px solid #0078d7;
            }

            QStatusBar {
                background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
                    stop:0 #f6f7fa, stop:1 #d9dce5);
                border-top: 1px solid #c0c0c0;
            }

            QStatusBar QLabel {
                padding: 2px 8px;
                border-right: 1px solid #c0c0c0;
            }

            QMessageBox {
                background-color: #ffffff;
            }

            QProgressBar {
                border: 1px solid #c0c0c0;
                border-radius: 3px;
                text-align: center;
                background-color: #f0f0f0;
            }

            QProgressBar::chunk {
                background-color: #0078d7;
                border-radius: 2px;
            }
        """)

    def setup_fonts(self):
        """设置字体"""
        font = QFont()
        # font.setFamily("Microsoft YaHei" if sys.platform == "win32" else "Noto Sans CJK SC")
        font.setPointSize(10)
        self.setFont(font)

    def show_splash_screen(self):
        """显示启动画面"""
        # 创建启动画面
        splash_pixmap = QPixmap(500, 350)
        splash_pixmap.fill(Qt.GlobalColor.white)

        # 绘制启动画面内容
        painter = QPainter(splash_pixmap)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # 绘制背景渐变
        gradient = QLinearGradient(0, 0, 0, 350)
        gradient.setColorAt(0, QColor(52, 152, 219))
        gradient.setColorAt(1, QColor(41, 128, 185))
        painter.fillRect(0, 0, 500, 350, gradient)

        # 绘制标题
        painter.setPen(Qt.GlobalColor.white)
        font = painter.font()
        font.setPointSize(28)
        font.setBold(True)
        painter.setFont(font)
        painter.drawText(0, 100, 500, 60, Qt.AlignmentFlag.AlignCenter, "光通信仿真实验平台")

        # 绘制版本
        font.setPointSize(12)
        font.setBold(False)
        painter.setFont(font)
        painter.drawText(0, 160, 500, 40, Qt.AlignmentFlag.AlignCenter, f"版本 {self.applicationVersion()}")

        # 绘制单位信息
        font.setPointSize(10)
        painter.drawText(0, 200, 500, 30, Qt.AlignmentFlag.AlignCenter, "香港理工大学光子研究中心")

        # 绘制加载信息
        painter.drawText(0, 250, 500, 40, Qt.AlignmentFlag.AlignCenter, "正在初始化应用程序...")

        painter.end()

        self.splash = QSplashScreen(splash_pixmap, Qt.WindowType.WindowStaysOnTopHint)
        self.splash.show()

        # 处理事件，确保画面显示
        self.processEvents()

        return self.splash

    def update_splash_message(self, message):
        """更新启动画面消息"""
        if self.splash:
            self.splash.showMessage(message,
                                    Qt.AlignmentFlag.AlignBottom | Qt.AlignmentFlag.AlignCenter,
                                    Qt.GlobalColor.white)
            self.processEvents()

    def create_main_window(self):
        """创建主窗口"""
        try:
            self.update_splash_message("正在初始化主界面...")

            # 创建主窗口
            self.main_window = MainWindow()

            # 更新启动画面
            self.update_splash_message("启动完成，正在显示主窗口...")

            # 显示主窗口
            self.main_window.show()

            # 关闭启动画面
            if self.splash:
                self.splash.finish(self.main_window)
                self.splash = None

            return True

        except Exception as e:
            error_msg = f"创建主窗口时发生错误: {str(e)}\n\n{traceback.format_exc()}"
            print(error_msg)

            if self.splash:
                self.splash.close()

            QMessageBox.critical(
                None, "启动错误",
                f"应用程序启动失败:\n{str(e)}\n\n{traceback.format_exc()}"
            )
            return False

    def handle_matlab_engine_started(self, success, error_msg):
        return success

    def run(self):
        """运行应用程序"""
        # 显示启动画面
        self.show_splash_screen()

        try:
            if MainWindow.engine_started.started.connect(self.handle_matlab_engine_started):
                self.create_main_window()

                # 运行应用程序事件循环
                return self.exec()

        except Exception as e:
            # 关闭启动画面
            if self.splash:
                self.splash.close()

            # 显示错误
            QMessageBox.critical(
                None, "启动错误",
                f"应用程序启动失败:\n{str(e)}\n\n{traceback.format_exc()}"
            )
            return 1

    def exception_hook(self, exc_type, exc_value, exc_traceback):
        """异常处理钩子"""
        # 显示错误对话框
        error_msg = "".join(traceback.format_exception(exc_type, exc_value, exc_traceback))

        error_dialog = QMessageBox()
        error_dialog.setIcon(QMessageBox.Icon.Critical)
        error_dialog.setWindowTitle("应用程序错误")
        error_dialog.setText("发生未处理的异常")
        error_dialog.setDetailedText(error_msg)
        error_dialog.setStandardButtons(QMessageBox.StandardButton.Ok)
        error_dialog.exec()

        # 调用默认的异常处理
        sys.__excepthook__(exc_type, exc_value, exc_traceback)

def main():
    """主函数"""
    # 创建应用程序
    app = OpticalSimulationApp(sys.argv)

    # 设置窗口图标
    app_icon = QIcon()

    # 尝试加载图标文件
    icon_paths = [
        "icon.ico",
        "icon.png",
        "resources/icon.ico",
        "resources/icon.png",
        os.path.join(os.path.dirname(__file__), "icon.ico"),
        os.path.join(os.path.dirname(__file__), "icon.png"),
    ]

    for path in icon_paths:
        if os.path.exists(path):
            app_icon.addFile(path)
            break

    if not app_icon.isNull():
        app.setWindowIcon(app_icon)

    # 运行应用程序
    return app.run()


if __name__ == "__main__":
    sys.exit(main())
