import os.path

from PyQt6.QtCore import Qt, QRect, QSize, QMimeData, QPoint
from PyQt6.QtGui import (QColor, QPixmap, QPainter, QBrush, QPen, QIcon, QDrag,
                        QFontMetrics)
from PyQt6.QtWidgets import QWidget, QHBoxLayout, QPushButton, QLabel, QVBoxLayout, QScrollArea

class ComponentButton(QWidget):
    def __init__(self, component_type, name, color, description="", icon_path=None, parent=None):
        super().__init__(parent)

        self.component_type = component_type
        self.name = name
        self.color = color
        self.description = description
        self.icon_path = icon_path

        self.setup_ui()

    def setup_ui(self):
        component_layout = QVBoxLayout(self)
        component_layout.setContentsMargins(2, 2, 2, 2)
        component_layout.setSpacing(0)

        self.icon_button = QPushButton()
        self.icon_button.setFixedSize(80, 80)
        self.icon_button.setToolTip(f"{self.description}")
        self.icon_button.setCursor(Qt.CursorShape.OpenHandCursor)

        self.create_icon()
        self.icon_button.setStyleSheet("""
            QPushButton {
                background-color: #f8f8f8;
                border: 1px solid #dddddd;
                border-radius: 6px;
                padding: 2px;
            }
            QPushButton:hover {
                background-color: #e8e8e8;
                border: 2px solid #aaaaaa;
            }
            QPushButton:pressed {
                background-color: #d8d8d8;
                border: 2px solid #888888;
            }
        """)

        self.type_label = QLabel(self.component_type)
        self.type_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.type_label.setFixedWidth(80)
        self.type_label.setStyleSheet("""
            QLabel {
                font-size: 12px;
                color: #555555;
                font-weight: bold;
            }
        """)

        if len(self.component_type) > 10:
            self.type_label.setText(self.component_type[:8] + "...")
            self.type_label.setToolTip(self.component_type)

        component_layout.addWidget(self.icon_button, alignment=Qt.AlignmentFlag.AlignCenter)
        component_layout.addWidget(self.type_label, alignment=Qt.AlignmentFlag.AlignCenter)

        self.icon_button.mousePressEvent = self.on_mouse_press

    def create_icon(self):
        icon_size = 80
        try:
            if self.icon_path:
                if os.path.exists(os.path.abspath(self.icon_path)):
                    # 直接使用图片存储路径，在图片存储文件夹位于项目根文件夹下时使用
                    self.icon_path = self.icon_path
                else:
                    # 获取当前文件所在路径，并拼接图片路径，仅当图片存储文件夹与脚本处于相同子文件夹下时使用
                    self.icon_path = os.path.join(os.path.dirname(__file__), self.icon_path)

            if self.icon_path:
                pixmap = QPixmap(self.icon_path)
                if not pixmap.isNull():
                    pixmap = pixmap.scaled(
                        icon_size, icon_size,
                        Qt.AspectRatioMode.KeepAspectRatio,
                        Qt.TransformationMode.SmoothTransformation
                    )
                    self.icon_button.setIcon(QIcon(pixmap))
                    self.icon_button.setIconSize(QSize(icon_size, icon_size))
                    return

        except Exception as ComponentWidgetIconException:
            print("Create Component Widget Icon ErrorL: ", ComponentWidgetIconException)

        self._draw_default_icon(icon_size)

    def _draw_default_icon(self, size):
        pixmap = QPixmap(size, size)
        pixmap.fill(Qt.GlobalColor.transparent)

        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        painter.setBrush(QBrush(self.color))
        painter.setPen(QPen(self.color.darker(120), 1))
        painter.drawRoundedRect(2, 2, size - 4, size - 4, 8, 8)

        painter.setPen(QPen(Qt.GlobalColor.black, 1))
        font = painter.font()
        font.setPointSize(8)
        font.setBold(True)
        painter.setFont(font)

        short_name = self.component_type[:3]
        painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, short_name)

        painter.end()

        self.icon_button.setIcon(QIcon(pixmap))
        self.icon_button.setIconSize(QSize(size, size))


    def on_mouse_press(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self.start_drag()

    def start_drag(self):
        mime_data = QMimeData()
        mime_data.setText(self.component_type)
        mime_data.setData("application/x-component", self.component_type.encode())
        mime_data.setData("application/x-component-name", self.name.encode())

        drag_size = 50

        if self.icon_path:
            pixmap = QPixmap(self.icon_path)
            if not pixmap.isNull():
                pixmap = pixmap.scaled(
                    drag_size, drag_size,
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation
                )
            else:
                pixmap = self._create_drag_pixmap(drag_size)
        else:
            pixmap = self._create_drag_pixmap(drag_size)

        drag = QDrag(self)
        drag.setMimeData(mime_data)
        drag.setPixmap(pixmap)
        drag.setHotSpot(QPoint(pixmap.width() // 2, pixmap.height() // 2))
        drag.exec(Qt.DropAction.CopyAction)

    def _create_drag_pixmap(self, size):
        pixmap = QPixmap(size, size)
        pixmap.fill(Qt.GlobalColor.transparent)

        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        painter.setBrush(QBrush(self.color.lighter(110)))
        painter.setPen(QPen(self.color.darker(130), 2))
        painter.drawRoundedRect(3, 3, size - 6, size - 6, 8, 8)

        painter.setPen(QPen(Qt.GlobalColor.black, 1))
        font = painter.font()
        font.setPointSize(10)
        font.setBold(True)
        painter.setFont(font)
        painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, self.component_type[:3])

        painter.end()
        return pixmap

class ComponentListWidget(QWidget):

    def __init__(self, parent=None):
        super().__init__(parent)

        self.setMaximumHeight(150)
        self.setMinimumHeight(100)

        component_layout = QVBoxLayout(self)
        component_layout.setSpacing(2)
        component_layout.setContentsMargins(2, 2, 2, 2)

        title_label = QLabel("组件库")
        title_label.setStyleSheet("font-weight: bold; color: #333333; font-size: 18pt;")
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        component_layout.addWidget(title_label)

        scroll_widget = QWidget()
        scroll_layout = QHBoxLayout(scroll_widget)
        scroll_layout.setSpacing(8)
        scroll_layout.setContentsMargins(5, 0, 5, 0)

        components = [
            ("OLTTxDSP", "OLTTxDSP", QColor(100, 200, 200), "下行发端数字信号处理", './icon/Tx_DSP.png'),
            ("ONUTxDSP", "ONUTxDSP", QColor(100, 200, 200), "上行发端数字信号处理", './icon/Tx_DSP.png'),
            # ("TxImbalance", "Transmitter Imbalance", QColor(255, 200, 150), "发射端不平衡", None),
            ("DAC", "DAC", QColor(100, 200, 150), "数模转换器", './icon/DAC.jpg'),

            ("Driver", "Driver", QColor(100, 200, 100), "", './icon/Driver.jpg'),
            ("LaserCW", "LaserCW", QColor(255, 200, 150), "激光器", './icon/laser.png'),

            ("Modulator", "Modulator", QColor(200, 200, 100), "调制器", './icon/modulator.jpg'),

            ("OA", "OA", QColor(200, 150, 200), "光放大器", './icon/OA.jpg'),
            ("LO", "LO", QColor(255, 200, 100), "本地振荡器", './icon/laser.png'),

            ("Pol_Rot", "Pol_Rot", QColor(255, 150, 150), "偏振仿真", './icon/RotatePol.jpg'),
            ("Fiber", "Fiber", QColor(150, 150, 255), "光纤", "./icon/fiber.jpg"),

            ("Splitter", "Splitter", QColor(255, 200, 100), "分光器", './icon/splitter.jpg'),
            ("ICR", "ICR", QColor(150, 200, 255), "相干接收机", './icon/ICR.png'),
            ("TIA", "TIA", QColor(200, 255, 150), "跨阻放大器", './icon/TIA.jpg'),
            ("ADC", "ADC", QColor(150, 255, 200), "模数转换器", "./icon/ADC.jpg"),
            ("ONURxDSP", "ONURxDSP", QColor(100, 200, 255), "下行收端数字信号处理", './icon/Rx_DSP.png'),
            ("OLTRxDSP", "OLTRxDSP", QColor(100, 200, 255), "上行收端数字信号处理", './icon/Rx_DSP.png'),
            ("VOA", "VOA", QColor(100, 200, 255), "光衰减器", './icon/VOA.jpg'),
            # ("Scope", "Scope", QColor(100, 200, 255), "示波器", './icon/Scope.jpg'),
            # ("AWG", "Arbitrary waveform generator", QColor(100, 200, 255), "任意波形发生器", './icon/AWG.png'),
            ("O-Analyzer", "O-Analyzer", QColor(100, 200, 255), "光分析仪", './icon/Analyzer.png'),
            ("E-Analyzer", "E-Analyzer", QColor(100, 200, 255), "电分析仪", './icon/Analyzer.png'),
            ("PowerMeter", "Power Meter", QColor(150, 220, 150), "光功率计", './icon/OPM.jpg'),
        ]

        self.component_buttons = []
        for comp_type, comp_name, color, description, icon_path in components:
            button = ComponentButton(comp_type, comp_name, color, description, icon_path)
            scroll_layout.addWidget(button)
            self.component_buttons.append(button)

        # scroll_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)

        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setWidget(scroll_widget)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        scroll_area.setStyleSheet("""
            QScrollArea {
                border: 1px solid #cccccc;
                border-radius: 4px;
                background-color: #f8f8f8;
            }
            QScrollBar:horizontal {
                height: 12px;
                background-color: #f0f0f0;
                border-radius: 6px;
            }
            QScrollBar::handle:horizontal {
                background-color: #c0c0c0;
                border-radius: 6px;
                min-width: 20px;
            }
            QScrollBar::handle:horizontal:hover {
                background-color: #a0a0a0;
            }
        """)

        component_layout.addWidget(scroll_area)
