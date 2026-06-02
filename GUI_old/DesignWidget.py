import json
import time
import numpy as np
import matlab
from typing import Dict, List, Tuple, Optional, Any
from PyQt6.QtCore import Qt, pyqtSignal, QLineF
from PyQt6.QtGui import QPainter, QLinearGradient, QColor, QBrush, QTransform, QPen, QPixmap
from PyQt6.QtWidgets import QDialog, QVBoxLayout, QGroupBox, QFormLayout, QLineEdit, QLabel, QTableWidget, \
    QDialogButtonBox, QTableWidgetItem, QComboBox, QCheckBox, QSpinBox, QDoubleSpinBox, QTextEdit, QMessageBox, \
    QGraphicsView, QGraphicsScene, QGraphicsLineItem, QMenu, QPushButton, QScrollArea, QWidget, QTabWidget

# 使用统一的参数管理器
from ParameterManager import ParameterManager, ParameterType
from basement import Component, Connection
from graphBasement import ComponentGraphicsItem, PortGraphicsItem, ConnectionGraphicsItem


class ComponentParameterDialog(QDialog):
    def __init__(self, component, parameter_manager, parent=None):
        super().__init__(parent)

        self.component = component
        self.parameter_manager = parameter_manager   # 接收 ParameterManager 实例
        self.param_widgets = {}

        self.setWindowTitle(f"编辑{component.name}参数")
        self.setMinimumSize(600, 500)

        self.init_ui()
        self.load_parameters()

    def init_ui(self):
        layout = QVBoxLayout(self)
        info_group = QGroupBox("基本信息")
        info_layout = QFormLayout()

        self.name_edit = QLineEdit(self.component.name)
        info_layout.addRow("名称：", self.name_edit)

        type_label = QLabel(self.component.type)
        info_layout.addRow("类型：", type_label)

        id_label = QLabel(str(self.component.id))
        info_layout.addRow("ID:", id_label)

        info_group.setLayout(info_layout)
        layout.addWidget(info_group)

        params_group = QGroupBox("参数设置")
        params_layout = QVBoxLayout()

        self.params_table = QTableWidget()
        self.params_table.setColumnCount(4)
        self.params_table.setHorizontalHeaderLabels(["参数名", "值", "单位", "描述"])
        self.params_table.horizontalHeader().setStretchLastSection(True)

        params_layout.addWidget(self.params_table)
        params_group.setLayout(params_layout)
        layout.addWidget(params_group)

        button_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok |
            QDialogButtonBox.StandardButton.Cancel |
            QDialogButtonBox.StandardButton.Apply |
            QDialogButtonBox.StandardButton.Reset
        )

        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        button_box.button(QDialogButtonBox.StandardButton.Apply).clicked.connect(self.apply_changes)
        button_box.button(QDialogButtonBox.StandardButton.Reset).clicked.connect(self.reset_parameters)

        layout.addWidget(button_box)

    def load_parameters(self):
        param_data = self.parameter_manager.create_parameter_dialog_data(
            self.component.type, self.component.properties
        )

        self.params_table.setRowCount(len(param_data))

        for row, param in enumerate(param_data):
            name_item = QTableWidgetItem(param['name'])
            name_item.setFlags(name_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
            self.params_table.setItem(row, 0, name_item)

            value_widget = self.create_value_widget(param)
            self.params_table.setCellWidget(row, 1, value_widget)
            self.param_widgets[param['name']] = value_widget

            unit_item = QTableWidgetItem(param['unit'])
            unit_item.setFlags(unit_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
            self.params_table.setItem(row, 2, unit_item)

            desc_text = param['description']
            if param.get('min_value') is not None:
                desc_text += f"\n范围: [{param['min_value']}, "
                if param.get('max_value') is not None:
                    desc_text += f"{param['max_value']}]"
                else:
                    desc_text += "∞)"

            desc_item = QTableWidgetItem(desc_text)
            desc_item.setFlags(desc_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
            self.params_table.setItem(row, 3, desc_item)

        self.params_table.resizeColumnsToContents()

    def create_value_widget(self, param):
        param_type = param['type']
        value = param['value']
        options = param.get('options')

        if options:
            combo = QComboBox()
            for option in options:
                combo.addItem(str(option))

            if value is not None:
                index = combo.findText(str(value))
                if index >= 0:
                    combo.setCurrentIndex(index)

            return combo

        elif param_type == ParameterType.BOOL:
            checkbox = QCheckBox()
            checkbox.setChecked(bool(value))
            return checkbox

        elif param_type == ParameterType.INTEGER:
            spinbox = QSpinBox()
            spinbox.setRange(-999999, 999999)

            if param.get('min_value') is not None:
                spinbox.setMinimum(int(param['min_value']))
            if param.get('max_value') is not None:
                spinbox.setMaximum(int(param['max_value']))

            if value is not None:
                spinbox.setValue(int(value))

            return spinbox

        elif param_type in [ParameterType.FLOAT, ParameterType.FREQUENCY,
                            ParameterType.POWER, ParameterType.LENGTH, ParameterType.TIME]:
            spinbox = QDoubleSpinBox()
            spinbox.setDecimals(12)
            spinbox.setRange(-1e20, 1e20)

            if param.get('min_value') is not None:
                spinbox.setMinimum(float(param['min_value']))
            if param.get('max_value') is not None:
                spinbox.setMaximum(float(param['max_value']))

            if value is not None:
                spinbox.setValue(float(value))

            return spinbox

        elif param_type == ParameterType.ARRAY:
            text_edit = QTextEdit()
            text_edit.setMaximumHeight(60)

            if value is not None:
                if isinstance(value, (list, tuple, np.ndarray)):
                    text_edit.setText(str(list(value)))
                else:
                    text_edit.setText(str(value))

            return text_edit

        else:
            line_edit = QLineEdit()
            if value is not None:
                line_edit.setText(str(value))
            return line_edit

    def get_parameter_value(self, widget):
        if isinstance(widget, QComboBox):
            text = widget.currentText()
            try:
                if '.' in text:
                    return float(text)
                else:
                    return int(text)
            except:
                return text

        elif isinstance(widget, QCheckBox):
            return widget.isChecked()

        elif isinstance(widget, (QSpinBox, QDoubleSpinBox)):
            return widget.value()

        elif isinstance(widget, QTextEdit):
            text = widget.toPlainText().strip()
            if text.startswith('[') and text.endswith(']'):
                try:
                    import ast
                    return ast.literal_eval(text)
                except:
                    pass
            return text

        elif isinstance(widget, QLineEdit):
            return widget.text()

        else:
            return None

    def get_parameters(self):
        params = {}

        for row in range(self.params_table.rowCount()):
            param_name = self.params_table.item(row, 0).text()
            widget = self.param_widgets.get(param_name)

            if widget:
                value = self.get_parameter_value(widget)
                unit = self.params_table.item(row, 2).text()
                params[param_name] = [value, unit]

        return params

    def apply_changes(self):
        self.component.name = self.name_edit.text()
        self.component.properties = self.get_parameters()

    def reset_parameters(self):
        reply = QMessageBox.question(
            self, "重置参数",
            "确定要重置所有参数为默认值吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )

        if reply == QMessageBox.StandardButton.Yes:
            self.load_parameters()


class SimulationResultsDialog(QDialog):
    def __init__(self, results, workspace, parent=None):
        super().__init__(parent)
        self.results = results
        self.workspace = workspace
        self.setWindowTitle("仿真结果详情")
        self.setMinimumSize(900, 600)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # 1. Power Budget 图像（保持不变）
        img_label = QLabel()
        img_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        img_label.setStyleSheet("border: 1px solid #ccc; background: white;")
        link = self.workspace._get_link_direction_and_onu_count()[0]
        if link == 'Down':
            img_path = "img/down/Power_Budget_vs_PTx_Downlink.png"
        else:
            img_path = "img/up/Power_Budget_vs_PTx_Uplink.png"
        pixmap = QPixmap(img_path)
        if not pixmap.isNull():
            pixmap = pixmap.scaledToWidth(700, Qt.TransformationMode.SmoothTransformation)
            img_label.setPixmap(pixmap)
        else:
            img_label.setText("功率预算图未生成，请检查 MATLAB 是否成功保存图像。")
        layout.addWidget(img_label)

        # 获取仿真结果中的发射功率（入纤功率）
        tx_power = self.results.get('tx_power_dbm', None)
        if isinstance(tx_power, (list, tuple, np.ndarray)):
            # 如果上行链路返回列表，取第一个（或实际使用的值）
            tx_power = tx_power[-1] if len(tx_power) > 0 else 0.0
        elif tx_power is None:
            tx_power = 0.0

        snr_mat = self.results['snr']
        ber_mat = self.results['ber']
        rop_list = self.results['rop_dbm']
        num_rop, num_onu = snr_mat.shape

        if len(rop_list) != num_rop:
            import warnings
            warnings.warn(f"ROP 列表长度 ({len(rop_list)}) 与矩阵行数 ({num_rop}) 不匹配，将使用索引作为 ROP 值")
            rop_list = np.arange(num_rop)

        # 2. 表格：增加一列显示发射功率
        group = QGroupBox("详细数据 (SNR / BER vs ROP)")
        group_layout = QVBoxLayout()
        table = QTableWidget()

        # 设置列：新增加第一列“发射功率”，然后是 ROP，之后每个 ONU 的 SNR 和 BER
        table.setColumnCount(1 + 1 + 2 * num_onu)  # 发射功率 + ROP + (SNR+BER)*ONU数量
        headers = ["发射功率 (dBm)", "ROP (dBm)"]
        for i in range(num_onu):
            headers.append(f"ONU{i + 1} SNR (dB)")
            headers.append(f"ONU{i + 1} BER")
        table.setHorizontalHeaderLabels(headers)
        table.setRowCount(num_rop)

        for r in range(num_rop):
            # 第一列：发射功率（所有行相同）
            tx_item = QTableWidgetItem(f"{tx_power:.2f}")
            tx_item.setFlags(tx_item.flags() & ~Qt.ItemFlag.ItemIsEditable)  # 只读
            table.setItem(r, 0, tx_item)

            # 第二列：ROP
            table.setItem(r, 1, QTableWidgetItem(f"{rop_list[r]:.2f}"))

            col = 2
            for i in range(num_onu):
                snr_val = snr_mat[r, i]
                ber_val = ber_mat[r, i]
                table.setItem(r, col, QTableWidgetItem(f"{snr_val:.2f}"))
                table.setItem(r, col + 1, QTableWidgetItem(f"{ber_val:.2e}"))
                col += 2

        table.resizeColumnsToContents()
        group_layout.addWidget(table)
        group.setLayout(group_layout)
        layout.addWidget(group)

        # 关闭按钮（保持不变）
        btn_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        btn_box.rejected.connect(self.reject)
        layout.addWidget(btn_box)

class Workspace(QGraphicsView):
    simulation_requested = pyqtSignal()
    simulation_completed = pyqtSignal(dict)
    simulation_error = pyqtSignal(str)

    def __init__(self, parent=None):
        super().__init__(parent)

        self.scene = QGraphicsScene()
        self.setScene(self.scene)
        self.setRenderHint(QPainter.RenderHint.Antialiasing)
        self.setAcceptDrops(True)
        self.setDragMode(QGraphicsView.DragMode.RubberBandDrag)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

        gradient = QLinearGradient(0, 0, 0, 400)
        gradient.setColorAt(0, QColor(250, 250, 255))
        gradient.setColorAt(1, QColor(240, 245, 255))
        self.setBackgroundBrush(QBrush(gradient))

        self.components = {}  # id -> Component
        self.connections = {}  # id -> Connection
        self.component_items = {}  # id -> ComponentGraphicsItem
        self.connection_items = {}  # id -> ConnectionGraphicsItem

        self.connecting = False
        self.source_component = None
        self.source_port_loc = None
        self.temp_connection = None

        self.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.customContextMenuRequested.connect(self.show_context_menu)

        # 使用统一的参数管理器，替代原来的 global_params 和 parameter_manager
        self.param_manager = ParameterManager()
        print("可用模板:", list(self.param_manager.component_templates.keys()))
        # 默认全局参数已由 ParameterManager.load_defaults() 在构造函数中自动加载

        self.auto_avoid_overlap = True
        self.grid_snap = True
        self.grid_size = 20

    def dragEnterEvent(self, event):
        if event.mimeData().hasFormat("application/x-component"):
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def dragMoveEvent(self, event):
        if event.mimeData().hasFormat("application/x-component"):
            event.acceptProposedAction()
        else:
            super().dragMoveEvent(event)

    def dropEvent(self, event):
        if event.mimeData().hasFormat("application/x-component"):
            component_type = event.mimeData().data("application/x-component").data().decode()
            component_name = event.mimeData().data("application/x-component-name").data().decode()

            scene_pos = self.mapToScene(event.position().toPoint())

            component_width = ComponentGraphicsItem.WIDTH
            component_height = ComponentGraphicsItem.HEIGHT
            adjusted_x = scene_pos.x() - component_width / 2
            adjusted_y = scene_pos.y() - component_height / 2

            if self.grid_snap:
                adjusted_x = round(adjusted_x / self.grid_size) * self.grid_size
                adjusted_y = round(adjusted_y / self.grid_size) * self.grid_size

            base_name = component_name.split(' ')[0] if ' ' in component_name else component_name
            existing_names = [comp.name for comp in self.components.values()]
            name = self.generate_unique_name(base_name, existing_names)

            properties = self.get_default_properties(component_type)

            component = Component(component_type, name, adjusted_x, adjusted_y, icon_path=None, properties=properties)
            self.add_component(component)

            event.acceptProposedAction()
        else:
            super().dropEvent(event)

    def generate_unique_name(self, base_name, existing_names):
        if base_name not in existing_names:
            return base_name

        counter = 1
        while True:
            new_name = f"{base_name}_{counter}"
            if new_name not in existing_names:
                return new_name
            counter += 1

    def get_default_properties(self, component_type):
        """获取默认参数（使用统一管理器的模板）"""
        template = self.param_manager.get_template(component_type)
        properties = {}

        for param_name, param in template.parameters.items():
            properties[param_name] = [param.value, param.unit]

        return properties

    def add_component(self, component):
        self.components[component.id] = component
        item = ComponentGraphicsItem(component)
        self.component_items[component.id] = item

        if self.auto_avoid_overlap:
            self.avoid_overlap(item)

        self.scene.addItem(item)
        item.setPos(component.x, component.y)

        self.update_all_connections()

    def avoid_overlap(self, new_item):
        new_rect = new_item.boundingRect().translated(new_item.pos())

        for existing_item in self.component_items.values():
            if existing_item == new_item:
                continue

            existing_rect = existing_item.boundingRect().translated(existing_item.pos())

            if new_rect.intersects(existing_rect):
                new_item.setPos(new_item.x() + 20, new_item.y() + 20)
                new_item.component.x = new_item.x()
                new_item.component.y = new_item.y()
                self.avoid_overlap(new_item)
                break

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            scene_pos = self.mapToScene(event.pos())
            item = self.scene.itemAt(scene_pos, QTransform())

            if isinstance(item, PortGraphicsItem) and item.port_type == 'out':
                self.start_connection(item.component_id, item.port_loc)
                event.accept()
                return

        super().mousePressEvent(event)

    def mouseDoubleClickEvent(self, event):
        scene_pos = self.mapToScene(event.pos())
        item = self.scene.itemAt(scene_pos, QTransform())

        if not item:
            self.edit_global_parameters()
        elif isinstance(item, ComponentGraphicsItem):
            comp_type = item.component.type
            if comp_type in ("O-Analyzer", "E-Analyzer"):
                self.save_design('.\\TS.json')
                with open('.\\TS.json', 'r', encoding='utf-8') as f:
                    data = json.load(f)

                link = None
                num = 0

                for comp in data['components']:
                    if comp['name'] == 'OLTTxDSP' and comp['type'] == 'OLTTxDSP':
                        link = 'Down'
                        num = sum(1 for c in data.get('components', []) if c.get('type') == 'ONURxDSP')
                        break
                    elif comp['name'] == 'ONUTxDSP' and comp['type'] == 'ONUTxDSP':
                        link = 'Up'
                        num = sum(1 for c in data.get('components', []) if c.get('type') == 'ONUTxDSP')
                        break
                self.show_analyzer_image(link, num, comp_type)
            elif comp_type == "PowerMeter":
                self.show_power_meter_dialog(item.component)
            else:
                super().mouseDoubleClickEvent(event)
        else:
            super().mouseDoubleClickEvent(event)

    def show_power_meter_dialog(self, component):
        """显示功率计读数对话框"""
        power = getattr(component, 'power_value', None)
        if power is None:
            power = 0.0  # 未测量时显示 0
        # 读取用户设置的显示单位，默认为 dBm
        unit = component.properties.get('DisplayUnit', ['dBm', ''])[0]
        # 根据单位转换数值（仅示例，实际功率 value 应存储为 dBm）
        if unit == 'dBm':
            display_value = power
        elif unit == 'W':
            display_value = 10 ** (power / 10) * 1e-3  # dBm -> W
        elif unit == 'mW':
            display_value = 10 ** (power / 10)  # dBm -> mW
        else:
            display_value = power
            unit = 'dBm'

        QMessageBox.information(self, "功率计",
                                f"组件：{component.name}\n当前光功率：{display_value:.4f} {unit}")

    def show_analyzer_image(self, link, num, comp_type):
        import os

        # --- 1. 调试：打印关键信息 ---
        print(f"--- 尝试打开分析窗口 ---")
        print(f"Link: {link}, Num: {num} (类型: {type(num)}), Type: {comp_type}")

        if not link or not comp_type:
            print("错误: link 或 comp_type 为空。")
            return

        dialog = QDialog(self)
        dialog.setWindowTitle(f"{comp_type} 分析 (Link: {link})")
        dialog.setMinimumSize(600, 500)

        layout = QVBoxLayout(dialog)
        tab_widget = QTabWidget()

        tabs_to_create = []  # 统一暂存列表

        # --- 2. 填充 tabs_to_create 列表 ---
        if link == 'Up':
            if comp_type == "O-Analyzer":
                tabs_to_create = [("光谱", "./img/up/Tx_Optical_Spectrum.png")]
            elif comp_type == "E-Analyzer":
                tabs_to_create = [
                    ("收端ADC信号", "./img/up/Rx_ADC_Signal.png"),
                    ("星座图", "./img/up/Recovered_Constellation.png")
                ]

        elif link == 'Down':
            if comp_type == "O-Analyzer":
                tabs_to_create = [("光谱", "./img/down/OLT_Tx_Optical_Spectrum.png"),
                                  ("OLT发端电谱", "./img/down/OLT_Tx_Electrical_Spectrum.png")]

            elif comp_type == "E-Analyzer":

                # --- 处理动态端口 ---
                port_list = []
                if num is not None:
                    if isinstance(num, list):
                        port_list = num
                    else:
                        # 如果 num=3，这里生成 [1, 2, 3]
                        port_list = list(range(1, num + 1))

                # 为每个端口添加星座图标签页
                for port_num in port_list:
                    tabs_to_create.append((f"ONU {port_num} 星座图", f"./img/down/Constellation_Downlink_ONU{port_num}.png"))

                # 为每个端口添加频谱标签页
                for port_num in port_list:
                    tabs_to_create.append((f"port {port_num} 频谱", f"./img/down/Rx_ADC_Spectrum_Port{port_num}.png"))

        # --- 3. 统一创建标签页 ---
        if not tabs_to_create:
            print("警告: 没有定义任何标签页内容。")
            return

        for tab_name, image_path in tabs_to_create:
            self._add_image_tab(tab_widget, tab_name, image_path)

        layout.addWidget(tab_widget)

        btn_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        btn_box.rejected.connect(dialog.reject)
        layout.addWidget(btn_box)

        print(">>> 窗口已创建，正在显示...")
        dialog.exec()

    def _add_image_tab(self, tab_widget, tab_name, image_path):
        tab = QWidget()
        tab_layout = QVBoxLayout(tab)
        label = QLabel()
        label.setAlignment(Qt.AlignmentFlag.AlignCenter)

        pixmap = QPixmap(image_path)
        if pixmap.isNull():
            label.setText(f"{tab_name} 图片未找到\n({image_path})")
            label.setStyleSheet("color: red;")
        else:
            max_w, max_h = 800, 600
            if pixmap.width() > max_w or pixmap.height() > max_h:
                pixmap = pixmap.scaled(max_w, max_h,
                                       Qt.AspectRatioMode.KeepAspectRatio,
                                       Qt.TransformationMode.SmoothTransformation)
            label.setPixmap(pixmap)

        scroll = QScrollArea()
        scroll.setWidget(label)
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet("background-color: white;")
        tab_layout.addWidget(scroll)
        tab_widget.addTab(tab, tab_name)

    def mouseMoveEvent(self, event):
        if self.connecting and self.temp_connection:
            mouse_pos = self.mapToScene(event.pos())
            source_item = self.component_items.get(self.source_component)
            if source_item:
                if self.source_port_loc == 'bottom':
                    source_pos = self.component_items[self.source_component].get_port_position('bottom')
                    self.temp_connection.setLine(QLineF(source_pos, mouse_pos))
                elif self.source_port_loc == 'right':
                    source_pos = self.component_items[self.source_component].get_port_position('right')
                    self.temp_connection.setLine(QLineF(source_pos, mouse_pos))
            else:
                self.connecting = False
                if self.temp_connection:
                    self.scene.removeItem(self.temp_connection)
                    self.temp_connection = None

        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        if self.connecting and event.button() == Qt.MouseButton.LeftButton:
            scene_pos = self.mapToScene(event.pos())
            item = self.scene.itemAt(scene_pos, QTransform())

            if isinstance(item, PortGraphicsItem) and item.port_type == 'in':
                target_component_id = item.component_id

                if target_component_id != self.source_component:
                    connection_exists = False
                    for connection in self.connections.values():
                        if (connection.source_id == self.source_component and
                                connection.target_id == target_component_id):
                            connection_exists = True
                            break

                    if not connection_exists:
                        connection = Connection(self.source_component, target_component_id, self.source_port_loc, item.port_loc)
                        self.add_connection(connection)

            if self.temp_connection:
                self.scene.removeItem(self.temp_connection)
                self.temp_connection = None

            self.connecting = False
            self.source_component = None

        super().mouseReleaseEvent(event)

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Delete or event.key() == Qt.Key.Key_Backspace:
            self.delete_selected_items()
            event.accept()
        elif event.key() == Qt.Key.Key_C and event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            self.copy_selected_items()
        elif event.key() == Qt.Key.Key_V and event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            self.paste_items()
        elif event.key() == Qt.Key.Key_A and event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            self.select_all_items()
        else:
            super().keyPressEvent(event)

    def delete_selected_items(self):
        selected_items = self.scene.selectedItems()

        if not selected_items:
            return

        reply = QMessageBox.question(
            self, "删除确认",
            f"确定要删除 {len(selected_items)} 个选中项吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )

        if reply == QMessageBox.StandardButton.Yes:
            connections_to_delete = []
            components_to_delete = []

            for item in selected_items:
                if isinstance(item, ConnectionGraphicsItem):
                    if hasattr(item, 'connection_id'):
                        connections_to_delete.append(item.connection_id)
                elif isinstance(item, ComponentGraphicsItem):
                    components_to_delete.append(item.component.id)

            for connection_id in connections_to_delete:
                self.remove_connection(connection_id)

            for component_id in components_to_delete:
                self.remove_component(component_id)

            self.scene.update()

    def copy_selected_items(self):
        # TODO: 实现复制功能
        pass

    def paste_items(self):
        # TODO: 实现粘贴功能
        pass

    def select_all_items(self):
        for item in self.scene.items():
            if isinstance(item, (ComponentGraphicsItem, ConnectionGraphicsItem)):
                item.setSelected(True)

    def start_connection(self, component_id, port_loc):
        self.connecting = True
        self.source_component = component_id
        self.source_port_loc = port_loc

        source_pos = self.component_items[component_id].get_port_position(self.source_port_loc)
        self.temp_connection = QGraphicsLineItem(QLineF(source_pos, source_pos))
        self.temp_connection.setPen(QPen(QColor(100, 150, 200), 2, Qt.PenStyle.DashLine))
        self.scene.addItem(self.temp_connection)
        self.temp_connection.setZValue(-1)

    def add_connection(self, connection):
        if (connection.source_id not in self.component_items or
                connection.target_id not in self.component_items):
            return

        for existing_connection in self.connections.values():
            if (existing_connection.source_id == connection.source_id and
                    existing_connection.target_id == connection.target_id):
                return

        self.connections[connection.id] = connection

        source_component = self.component_items[connection.source_id]
        target_component = self.component_items[connection.target_id]
        source_port = connection.source_port
        target_port = connection.target_port

        connection_item = ConnectionGraphicsItem(source_component, target_component, source_port, target_port, connection.id)
        self.connection_items[connection.id] = connection_item
        self.scene.addItem(connection_item)

        connection_item.update_line()

        source_component.component.add_output_connection(connection.id, connection.source_port)
        target_component.component.add_input_connection(connection.id, connection.target_port)

    def remove_component(self, component_id):
        if component_id in self.component_items:
            connections_to_remove = []
            for conn_id, connection in self.connections.items():
                if connection.source_id == component_id or connection.target_id == component_id:
                    connections_to_remove.append(conn_id)

            for conn_id in connections_to_remove:
                self.remove_connection(conn_id)

            self.scene.removeItem(self.component_items[component_id])
            del self.component_items[component_id]
            del self.components[component_id]

            self.scene.update()

    def remove_connection(self, connection_id):
        if connection_id in self.connection_items:
            connection_item = self.connection_items[connection_id]
            connection_item.remove_from_components()

            if connection_id in self.connections:
                connection = self.connections[connection_id]
                if connection.source_id in self.components:
                    self.components[connection.source_id].remove_connection(connection_id)
                if connection.target_id in self.components:
                    self.components[connection.target_id].remove_connection(connection_id)

            self.scene.removeItem(connection_item)
            del self.connection_items[connection_id]

            if connection_id in self.connections:
                del self.connections[connection_id]

            self.scene.update()

    def show_context_menu(self, pos):
        scene_pos = self.mapToScene(pos)
        item = self.scene.itemAt(scene_pos, QTransform())

        menu = QMenu()

        if isinstance(item, ComponentGraphicsItem):
            menu.addAction("编辑参数").triggered.connect(
                lambda: self.edit_component_parameters(item.component.id)
            )
            menu.addAction("复制组件").triggered.connect(
                lambda: self.copy_component(item.component.id)
            )
            menu.addAction("删除组件").triggered.connect(
                lambda: self.remove_component(item.component.id)
            )
            menu.addSeparator()
            menu.addAction("运行此组件").triggered.connect(
                lambda: self.simulate_single_component(item.component.id)
            )

        elif isinstance(item, ConnectionGraphicsItem):
            menu.addAction("编辑属性").triggered.connect(
                lambda: self.edit_connection_properties(item.connection_id)
            )
            menu.addAction("删除连接线").triggered.connect(
                lambda: self.remove_connection(item.connection_id)
            )

        else:
            menu.addAction("添加组件...").triggered.connect(
                lambda: self.show_add_component_dialog(scene_pos)
            )
            menu.addAction("编辑全局参数").triggered.connect(
                self.edit_global_parameters
            )
            menu.addSeparator()
            menu.addAction("运行仿真").triggered.connect(
                self.run_simulation
            )
            menu.addAction("验证设计").triggered.connect(
                self.validate_design
            )
            menu.addSeparator()
            menu.addAction("整理布局").triggered.connect(
                self.arrange_layout
            )
            menu.addAction("清空工作区").triggered.connect(
                self.clear_design
            )

        menu.exec(self.mapToGlobal(pos))

    def copy_component(self, component_id):
        if component_id in self.components:
            original = self.components[component_id]

            new_component = Component(
                component_type=original.type,
                name=f"{original.name}_copy",
                x=original.x + 50,
                y=original.y + 50,
                icon_path=original.icon_path,
                properties=original.properties.copy()
            )

            self.add_component(new_component)

    def edit_component_parameters(self, component_id):
        if component_id not in self.components:
            return

        component = self.components[component_id]

        dialog = ComponentParameterDialog(component, self.param_manager, self)

        if dialog.exec() == QDialog.DialogCode.Accepted:
            dialog.apply_changes()

            if component_id in self.component_items:
                self.component_items[component_id].update()

    def edit_global_parameters(self):
        """编辑全局参数 - 使用统一管理器"""
        dialog = QDialog(self)
        dialog.setWindowTitle("编辑全局参数")
        dialog.setMinimumSize(600, 500)

        layout = QVBoxLayout(dialog)

        info_label = QLabel(
            "全局参数可以在所有组件中引用。\n"
            "使用格式：${参数名} 或使用单位后缀，如 1.55e-9 m"
        )
        info_label.setWordWrap(True)
        layout.addWidget(info_label)

        table = QTableWidget()
        table.setColumnCount(3)
        table.setHorizontalHeaderLabels(["参数名", "值", "单位"])

        # 从统一管理器获取全局参数
        params = self.param_manager.to_dict()
        table.setRowCount(len(params))

        row = 0
        for key, value in params.items():
            name_item = QTableWidgetItem(key)
            name_item.setFlags(name_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
            table.setItem(row, 0, name_item)

            if isinstance(value, (list, tuple)) and len(value) >= 2:
                value_item = QTableWidgetItem(str(value[0]))
                unit_item = QTableWidgetItem(str(value[1]))
            else:
                value_item = QTableWidgetItem(str(value))
                unit_item = QTableWidgetItem("")

            table.setItem(row, 1, value_item)
            table.setItem(row, 2, unit_item)

            row += 1

        table.resizeColumnsToContents()
        layout.addWidget(table)

        add_group = QGroupBox("添加新参数")
        add_layout = QFormLayout()

        new_key_edit = QLineEdit()
        new_value_edit = QLineEdit()
        new_unit_edit = QLineEdit()
        add_button = QPushButton("添加")

        add_layout.addRow("参数名:", new_key_edit)
        add_layout.addRow("值:", new_value_edit)
        add_layout.addRow("单位:", new_unit_edit)
        add_layout.addRow(add_button)

        add_group.setLayout(add_layout)
        layout.addWidget(add_group)

        button_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok |
            QDialogButtonBox.StandardButton.Cancel |
            QDialogButtonBox.StandardButton.Apply
        )

        def add_parameter():
            key = new_key_edit.text().strip()
            value = new_value_edit.text().strip()
            unit = new_unit_edit.text().strip()

            if key and value:
                row = table.rowCount()
                table.insertRow(row)

                name_item = QTableWidgetItem(key)
                name_item.setFlags(name_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                table.setItem(row, 0, name_item)
                table.setItem(row, 1, QTableWidgetItem(value))
                table.setItem(row, 2, QTableWidgetItem(unit))

                new_key_edit.clear()
                new_value_edit.clear()
                new_unit_edit.clear()

        def apply_changes():
            new_params = {}
            for i in range(table.rowCount()):
                key = table.item(i, 0).text()
                value = table.item(i, 1).text()
                unit = table.item(i, 2).text() if table.item(i, 2) else ""
                new_params[key] = [value, unit]

            self.param_manager.from_dict(new_params)

        add_button.clicked.connect(add_parameter)
        button_box.button(QDialogButtonBox.StandardButton.Apply).clicked.connect(apply_changes)
        button_box.accepted.connect(lambda: (apply_changes(), dialog.accept()))
        button_box.rejected.connect(dialog.reject)
        layout.addWidget(button_box)

        dialog.exec()

    def arrange_layout(self):
        if not self.components:
            return

        grid_size = 150
        cols = int(np.ceil(np.sqrt(len(self.components))))

        positions = []
        for i, component_id in enumerate(self.components):
            row = i // cols
            col = i % cols

            x = col * grid_size + 50
            y = row * grid_size + 50

            positions.append((component_id, x, y))

        for component_id, x, y in positions:
            if component_id in self.component_items:
                item = self.component_items[component_id]
                item.setPos(x, y)
                self.components[component_id].x = x
                self.components[component_id].y = y

        self.update_all_connections()

    def update_all_connections(self):
        for connection_item in self.connection_items.values():
            connection_item.update_line()

    def clear_design(self):
        if len(self.components) > 0:
            reply = QMessageBox.question(
                self, "清空工作区",
                "确定要清空整个工作区吗？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )

            if reply == QMessageBox.StandardButton.Yes:
                self.components.clear()
                self.connections.clear()
                self.component_items.clear()
                self.connection_items.clear()
                self.scene.clear()

                self.simulation_results = None

    def save_design(self, filename: str):
        data = {
            'components': [comp.to_dict() for comp in self.components.values()],
            'connections': [conn.to_dict() for conn in self.connections.values()],
            'global_parameters': self.param_manager.to_dict(),
            'metadata': {
                'version': '1.0',
                'timestamp': time.time(),
                'component_count': len(self.components),
                'connection_count': len(self.connections)
            }
        }

        with open(filename, 'w') as f:
            json.dump(data, f, indent=2, default=str)

    def load_design(self, filename: str):
        try:
            with open(filename, 'r') as f:
                data = json.load(f)

            self.clear_design()

            for comp_data in data['components']:
                component = Component.from_dict(comp_data)
                self.add_component(component)

            for conn_data in data.get('connections', []):
                connection = Connection.from_dict(conn_data)
                self.add_connection(connection)

            if 'global_parameters' in data:
                self.param_manager.from_dict(data['global_parameters'])
            else:
                self.param_manager.load_defaults()

            self.update_all_connections()

            return True

        except Exception as e:
            QMessageBox.critical(self, "加载错误", f"无法加载设计文件: {str(e)}")
            return False

    def get_design_info(self) -> Dict:
        return {
            'component_count': len(self.components),
            'connection_count': len(self.connections),
        }

    def save_data(self, filename: str = 'TS_data.json', x_t=None, y_t=None, SigX=None, SigY=None, PAPR=None, Params=None):
        data = {
            'x_t': x_t,
            'y_t': y_t,
            'SigX': SigX,
            'SigY': SigY,
            'PAPR': PAPR,
            'Params': Params
        }

        with open(filename, 'w') as f:
            json.dump(data, f, indent=2, default=str)

    def _get_link_direction_and_onu_count(self) -> Tuple[str, int]:
        """从当前组件中判断链路方向并统计 ONU 数量"""
        has_olt_tx = any(comp.type == 'OLTTxDSP' for comp in self.components.values())
        has_onu_tx = any(comp.type == 'ONUTxDSP' for comp in self.components.values())

        if has_olt_tx:
            # 下行：统计 ONURxDSP 数量作为 ONU 个数
            onu_count = sum(1 for comp in self.components.values() if comp.type == 'ONURxDSP')
            return 'Down', onu_count
        elif has_onu_tx:
            # 上行：统计 ONUTxDSP 数量作为 ONU 个数
            onu_count = sum(1 for comp in self.components.values() if comp.type == 'ONUTxDSP')
            return 'Up', onu_count
        else:
            return 'Unknown', 0

    def _build_matlab_params(self, num_onu, index) -> dict:
        """构建完整的 Params 结构体，用于传递给 MATLAB 仿真函数"""
        # 1. 获取全局参数（从 param_manager）
        global_params = self.param_manager.to_dict()  # 格式 {name: [value, unit]}

        # 2. 从组件中提取参数
        comps = self.components

        # 辅助函数：获取特定类型组件的第一个实例的参数
        def get_first_component_param(comp_type, param_name):
            for comp in comps.values():
                if comp.type == comp_type:
                    props = comp.properties
                    if param_name in props:
                        val, unit = props[param_name]
                        # 尝试转换为数值
                        try:
                            return float(val)
                        except:
                            return val
            return None

        # 提取关键参数
        # TxDSP 参数（优先使用 OLTTxDSP 或 ONUTxDSP，取第一个）
        tx_dsp_type = 'OLTTxDSP' if any(c.type == 'OLTTxDSP' for c in comps.values()) else 'ONUTxDSP'
        baudrate = get_first_component_param(tx_dsp_type, 'BaudRate')
        M = get_first_component_param(tx_dsp_type, 'M') or 16
        num_bands = get_first_component_param(tx_dsp_type, 'num_bands') or 4
        symbolnum = get_first_component_param(tx_dsp_type, 'symbolnum') or 32768

        # DAC 参数
        dac_sr = get_first_component_param('DAC', 'sampling_rate') or 92e9
        dac_bw = get_first_component_param('DAC', 'DAC_BW_Analog') or 32e9
        dac_res = get_first_component_param('DAC', 'Resolution') or 8

        # Driver
        driver_bw = get_first_component_param('Driver', 'Bandwidth') or 35e9
        driver_gain = get_first_component_param('Driver', 'Gain_dB') or 3

        # Modulator
        vpi = get_first_component_param('Modulator', 'Vpi') or 3
        vpi_dc = get_first_component_param('Modulator', 'VpiDC') or 3
        mzm_bw = get_first_component_param('Modulator', 'Bandwidth') or 35e9

        # Amplifier (EDFA)
        edfa_output_power = get_first_component_param('OA', 'OutputPower') or 1e-3
        edfa_gain_max = get_first_component_param('OA', 'GainMax') or 100
        edfa_nf = get_first_component_param('OA', 'NoiseFigure') or 5.0
        edfa_min_power = get_first_component_param('OA', 'Scan_Tx_Power_MinVal') or 0
        edfa_max_power = get_first_component_param('OA', 'Scan_Tx_Power_MaxVal') or 0

        # ADC 参数
        adc_sr = get_first_component_param('ADC', 'SamplingRate') or 256e9
        adc_bw = get_first_component_param('ADC', 'ADC_BW_Analog') or 59e9
        adc_res = get_first_component_param('ADC', 'Resolution') or 10

        # 获取激光器参数（若没有则使用默认值）
        laser_emission_freq = get_first_component_param('LaserCW', 'EmissionFrequency') or 193.1e12
        laser_avg_power = get_first_component_param('LaserCW', 'AveragePower') or 20e-3
        laser_linewidth = get_first_component_param('LaserCW', 'Linewidth') or 100e3
        laser_rin = get_first_component_param('LaserCW', 'RIN') or -150

        # LO
        lo_emission_freq = get_first_component_param('LO', 'EmissionFrequency') or 193.1e12
        lo_power = get_first_component_param('LO', 'Power') or 20e-3
        lo_linewidth = get_first_component_param('LO', 'LineWidth') or 5e6
        lo_rin = get_first_component_param('LO', 'RIN') or -150

        # Fiber
        fiber_length = get_first_component_param('Fiber', 'Length') or 20
        fiber_loss = get_first_component_param('Fiber', 'Loss_dB_km') or 0.17
        fiber_gamma = get_first_component_param('Fiber', 'Gamma') or 1.3e-3
        fiber_disp = get_first_component_param('Fiber', 'Dispersion') or 17e-6

        voa_min = get_first_component_param('VOA', 'Scan_ROP_MinVal')
        voa_max = get_first_component_param('VOA', 'Scan_ROP_MaxVal')

        # CoherentReceiver
        icr_responsivity = get_first_component_param('ICR', 'Responsivity') or 0.6
        icr_pd_bw = get_first_component_param('ICR', 'PD_BandWidth') or 25e9

        # TIA
        tia_gain = get_first_component_param('TIA', 'Gain') or 2000
        tia_bw = get_first_component_param('TIA', 'BandWidth') or 50e9

        # Splitter
        splitter_n = get_first_component_param('Splitter', 'N') or 4

        params = {
            'TxDSP':{
                'BaudRate': matlab.double(baudrate),
                'M': matlab.double(M),
                'num_bands': matlab.double(num_bands),
                'symbolnum': matlab.double(symbolnum),
            },
            'DAC': {'SamplingRate': matlab.double(dac_sr),
                    'BandWidth': matlab.double(dac_bw),
                    'Resolution': matlab.double(dac_res)},
            'Driver': {
                'Bandwidth': matlab.double(driver_bw),
                'Gain_dB': matlab.double(driver_gain)
            },
            'MZM': {
                'Vpi': matlab.double(vpi),
                'VpiDC': matlab.double(vpi_dc),
                'BW': matlab.double(mzm_bw)
            },
            'LaserParam': {
                'EmissionFrequency': matlab.double(laser_emission_freq),
                'AveragePower': matlab.double(laser_avg_power),
                'Linewidth': matlab.double(laser_linewidth),
                'RIN': matlab.double(laser_rin),
            },
            'Amp': {
                'OutputPower': matlab.double(edfa_output_power),
                'GainMax': matlab.double(edfa_gain_max),
                'NoiseFigure': matlab.double(edfa_nf),
                'Type': 'PowerControlled',
                'MinPower': matlab.double(edfa_min_power),
                'MaxPower': matlab.double(edfa_max_power),
            },
            'LO': {'EmissionFrequency': matlab.double(lo_emission_freq),
                   'Power': matlab.double(lo_power),
                   'Linewidth': matlab.double(lo_linewidth),
                   'RIN': matlab.double(lo_rin)
                   },
            'Fiber': {
                'Length': matlab.double(fiber_length * 1000),  # km -> m
                'Loss_dB_km': matlab.double(fiber_loss),
                'Gamma': matlab.double(fiber_gamma),
                'Dispersion': matlab.double(fiber_disp),
            },
            'TIA': {
                'Gain': matlab.double(tia_gain),
                'BandWidth': matlab.double(tia_bw)
            },
            'ADC': {
                'SamplingRate': matlab.double(adc_sr),
                'BandWidth': matlab.double(adc_bw),
                'Resolution': matlab.double(adc_res)
            },
            'ICR': {
                'BandWidth': matlab.double(icr_pd_bw),
                'Responsivity': matlab.double(icr_responsivity)
            },
            'VOA':{
                'Scan_ROP_MinVal': matlab.double(voa_min),
                'Scan_ROP_MaxVal': matlab.double(voa_max),
            },
        }

        return params

    def run_simulation(self, eng):
        self.save_design('.\\TS.json')
        link, num_onu = self._get_link_direction_and_onu_count()
        if link == 'Unknown' or num_onu == 0:
            QMessageBox.warning(self, "仿真错误", "无法确定链路方向或未找到 ONU 组件")
            return

        try:
            params = self._build_matlab_params(num_onu, 1)
            path = eng.genpath('.\\PON')
            eng.addpath(path)
            eng.workspace['Params'] = params
            eng.workspace['num_ONU'] = matlab.double(num_onu)

            # 安全转换辅助函数
            def to_float(val):
                if isinstance(val, (int, float)):
                    return float(val)
                # 将 matlab.double 转为 numpy 数组并取第一个元素
                return float(np.array(val).flat[0])

            if link == 'Down':
                snr_mat, ber_mat, tx_power, rop_list = eng.DEMO_model_Down(
                    matlab.double(num_onu), params, nargout=4
                )
                snr_np = np.array(snr_mat).T
                ber_np = np.array(ber_mat).T
                rop_np = np.array(rop_list).flatten()
                tx_power_dbm = to_float(tx_power)
                results = {
                    'snr': snr_np,
                    'ber': ber_np,
                    'rop_dbm': rop_np,
                    'tx_power_dbm': tx_power_dbm
                }
            elif link == 'Up':
                snr_arr, ber_arr, tx_power, rop_list = eng.DEMO_model_Up(
                    matlab.double(num_onu), params, nargout=4
                )
                snr_np = np.array(snr_arr).reshape(-1, 1)  # (ROP点数, 1)
                ber_np = np.array(ber_arr).reshape(-1, 1)
                rop_np = np.array(rop_list).flatten()
                tx_power_dbm = to_float(tx_power)
                results = {
                    'snr': snr_np,
                    'ber': ber_np,
                    'rop_dbm': rop_np,
                    'tx_power_dbm': tx_power_dbm
                }
            else:
                QMessageBox.warning(self, "仿真错误", "无法确定链路方向")
                return

            self.last_sim_results = results
            self.simulation_completed.emit(results)
            # QMessageBox.information(self, "仿真完成", f"发射功率: {results['tx_power_dbm']:.2f} dBm")
            QMessageBox.information(self, "仿真完成", "仿真结束")

        except Exception as e:
            error_msg = f"仿真失败: {str(e)}"
            QMessageBox.critical(self, "仿真错误", error_msg)
            self.simulation_error.emit(error_msg)


    def cancel_simulation(self):
        pass


"""    def run_simulation(self, eng):
        # 可选：保存当前设计到 JSON（用于调试）
        self.save_design('.\\TS.json')

        # 获取链路方向和 ONU 数量
        link, num_onu = self._get_link_direction_and_onu_count()
        if link == 'Unknown' or num_onu == 0:
            QMessageBox.warning(self, "仿真错误", "无法确定链路方向或未找到 ONU 组件，请检查设计。")
            return

        # 构建完整的参数结构体
        try:
            for index in range(num_onu):
                if index == 0:
                    params = self._build_matlab_params(num_onu, index + 1)
                else:
                    params.update(self._build_matlab_params(num_onu, index + 1))
        except Exception as e:
            QMessageBox.critical(self, "参数构建失败", f"构建 MATLAB 参数时出错：{str(e)}")
            return
        # 将参数注入 MATLAB 工作空间（可选，便于调试）
        path = eng.genpath('.\\PON')
        eng.addpath(path)
        eng.workspace['Params'] = params
        eng.workspace['num_ONU'] = matlab.double(num_onu)

        # 根据方向调用不同的仿真函数
        try:
            if link == 'Down':
                # 假设 MATLAB 函数接受 (num_ONU, Params)
                [snr, ber, tx_power, rop] = eng.DEMO_model_Down(matlab.double(num_onu), params, nargout=4)
            elif link == 'Up':  # Up
                [snr, ber, tx_power] = eng.DEMO_model_Up(matlab.double(num_onu), params, nargout=3)

            # 统一转换为 numpy 数组
            snr_np = np.array(snr).squeeze()
            ber_np = np.array(ber).squeeze()
            rop_np = np.array(rop).squeeze()

            snr_np = snr_np[-1]
            ber_np = ber_np[-1]
            rop_np = rop_np[-1]

            # 提取每个 ONU 的性能（假设 snr_np 形状为 (num_onus, ) 或 (num_onus, 1)）
            if snr_np.ndim == 0:  # 标量（单 ONU 单点）
                snr_list = [float(snr_np)]
                ber_list = [float(ber_np)]
                rop_list = [float(rop_np)]
            elif snr_np.ndim == 1:  # 一维向量（每个 ONU 一个值）
                snr_list = snr_np.tolist()
                ber_list = ber_np.tolist()
                rop_list = rop_np.tolist()
            else:  # 二维矩阵，取最后一列
                snr_list = snr_np[:, -1].tolist()
                ber_list = ber_np[:, -1].tolist()
                rop_list = rop_np[:, -1].tolist()

            # 构建详细结果文本
            result_text = f"链路: {link}\nONU 数量: {num_onu}\n\n"
            for i in range(min(len(snr_list), len(ber_list))):
                result_text += f"ONU {i + 1}:  SNR = {snr_list[i]:.2f} dB,  BER = {ber_list[i]:.2e}, ROP = {rop_list[i]:.3f}dBm\n"

            # 可选：添加平均值
            if len(snr_list) > 1:
                avg_snr = sum(snr_list) / len(snr_list)
                avg_ber = sum(ber_list) / len(ber_list)
                result_text += f"\n平均 SNR: {avg_snr:.2f} dB, 平均 BER: {avg_ber:.2e}"

            # 显示结果
            QMessageBox.information(self, "仿真完成", result_text)

            # 发射仿真完成信号（携带详细信息）
            self.simulation_completed.emit({'SNR': snr_list, 'BER': ber_list})

            for comp in self.components.values():
                if comp.type == "PowerMeter":
                    # 查找输入连接，尝试从上游组件估算功率（此处使用随机模拟值）
                    # 实际项目中可根据仿真结果中的节点功率赋值
                    import random
                    # 模拟一个合理的光功率范围 (-20 dBm ~ +5 dBm)
                    power_dbm = tx_power
                    comp.power_value = power_dbm

                    # 可选：在图形上刷新显示（如果添加了实时文本）
                    if comp.id in self.component_items:
                        self.component_items[comp.id].update()

        except Exception as e:
            error_msg = f"仿真失败: {str(e)}"
            QMessageBox.critical(self, "仿真错误", error_msg)
            self.simulation_error.emit(error_msg)"""

"""
for n in onu:
params(n) of onu -> onu(n) -> output_n store in python? -> onu_(n)_Tx.mat
output -> combine -> fiber -> Rx

for n in onu:
onu_output_1, 2, 3, 4
"""

"""
    def run_simulation(self, eng):
        self.save_design('.\\TS.json')
        with open('.\\TS.json', 'r', encoding='utf-8') as f:
            data = json.load(f)

        path = eng.genpath('.\\PON')
        eng.addpath(path)

        link = None
        num = 0

        for comp in data['components']:
            if comp['name'] == 'TxDSP' and comp['type'] == 'OLTTxDSP':
                link = 'Down'
                num = sum(1 for c in data.get('components', []) if c.get('type') == 'ONURxDSP')
                break
            elif comp['name'] == 'TxDSP' and comp['type'] == 'ONUTxDSP':
                link = 'Up'
                num = sum(1 for c in data.get('components', []) if c.get('type') == 'ONUTxDSP')
                break

        print(link)
        if link == 'Down':
            [SNR, BER] = eng.DEMO_model_Down(matlab.double(num), nargout=2)
        elif link == 'Up':
            [SNR, BER] = eng.DEMO_model_Up(matlab.double(num), nargout=2)
        elif link is None:
            print('链路状态无法判断')
"""