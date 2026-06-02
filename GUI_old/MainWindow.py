import matlab
from matlab import engine
import json
import os
from PyQt6.QtCore import Qt, QTimer, QThread, pyqtSignal, QObject
from PyQt6.QtGui import QAction, QKeySequence, QIcon, QPainter, QImage
from PyQt6.QtWidgets import QMainWindow, QWidget, QVBoxLayout, QLabel, QSplitter, QMenuBar, QFileDialog, QMessageBox, \
    QStyle, QApplication, QGroupBox, QLineEdit, QFormLayout, QDialog, QCheckBox, QComboBox, QDialogButtonBox

from ComponentWidget import ComponentListWidget
from MessageWidget import MessageArea
from DesignWidget import Workspace, SimulationResultsDialog


class Matlab_status(QObject):
    started = pyqtSignal(bool, str)


class MainWindow(QMainWindow):
    engine_started = Matlab_status()

    def __init__(self):
        super().__init__()

        self.matlab_engine = engine.start_matlab()
        path = self.matlab_engine.genpath('C:/Users/xingy/Desktop/NKR_GUI/Platform_PONsimple_down_Zepeng_v2')
        self.matlab_engine.addpath(path)

        self.engine_started.started.emit(True, "MATLAB引擎已经启动")


        self.setWindowTitle("多维复用超高速相干光接入端到端系统仿真平台")
        self.setGeometry(100, 50, 1400, 900)

        self.current_file = None
        self.recent_files = []
        self.max_recent_files = 10

        self.init_ui()

        # self.load_settings()

        self.statusBar().showMessage("就绪", 5000)

    def init_ui(self):
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(5, 5, 5, 5)
        main_layout.setSpacing(5)

        title_label = QLabel("多维复用超高速相干光接入端到端系统仿真平台")
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)

        title_label.setStyleSheet("""
            QLabel {
                font-size: 24pt;
                font-weight: bold;
                color: #2c3e50;
                padding: 10px;
                background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
                    stop:0 #3498db, stop:1 #2c3e50);
                border-radius: 0px;
                color: white;
            }
        """)
        main_layout.addWidget(title_label)

        vertical_splitter = QSplitter(Qt.Orientation.Vertical)
        main_layout.addWidget(vertical_splitter, 1)

        component_container = QWidget()
        component_layout = QVBoxLayout(component_container)
        component_layout.setContentsMargins(5, 5, 5, 5)

        self.component_list = ComponentListWidget()
        component_layout.addWidget(self.component_list)

        vertical_splitter.addWidget(component_container)

        component_container = QWidget()
        component_layout = QVBoxLayout(component_container)
        component_layout.setContentsMargins(5, 5, 5, 5)

        self.workspace = Workspace()
        vertical_splitter.addWidget(self.workspace)

        message_container = QWidget()
        message_layout = QVBoxLayout(message_container)
        message_layout.setContentsMargins(5, 5, 5, 5)

        self.message_area = MessageArea()
        message_layout.addWidget(self.message_area)

        vertical_splitter.addWidget(message_container)

        vertical_splitter.setSizes([150, 500, 250])

        self.create_menu_bar()

        self.create_tool_bar()

        self.create_status_bar()

    def create_menu_bar(self):
        menubar = self.menuBar()

        # 文件菜单
        file_menu = menubar.addMenu("文件")

        new_action = QAction("新建", self)
        new_action.setShortcut(QKeySequence("Ctrl+N"))
        new_action.triggered.connect(self.new_design)
        file_menu.addAction(new_action)

        open_action = QAction("打开", self)
        open_action.setShortcut(QKeySequence("Ctrl+O"))
        open_action.triggered.connect(self.open_design)
        file_menu.addAction(open_action)

        self.recent_menu = file_menu.addMenu("最近打开")
        self.update_recent_menu()

        file_menu.addSeparator()

        save_action = QAction("保存", self)
        save_action.setShortcut(QKeySequence("Ctrl+S"))
        save_action.triggered.connect(self.save_design)
        file_menu.addAction(save_action)

        save_as_action = QAction("另存为", self)
        save_as_action.setShortcut(QKeySequence("Ctrl+Shift+S"))
        save_as_action.triggered.connect(self.save_design_as)
        file_menu.addAction(save_as_action)

        file_menu.addSeparator()

        import_action = QAction("导入", self)
        import_action.triggered.connect(self.import_design)
        file_menu.addAction(import_action)

        export_action = QAction("导出", self)
        export_action.triggered.connect(self.export_design)
        file_menu.addAction(export_action)

        file_menu.addSeparator()

        exit_action = QAction("退出", self)
        exit_action.setShortcut(QKeySequence("Ctrl+Q"))
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)

        # 编辑菜单
        edit_menu = menubar.addMenu("编辑")

        undo_action = QAction("撤销", self)
        undo_action.setShortcut(QKeySequence("Ctrl+Z"))
        undo_action.triggered.connect(self.undo)
        edit_menu.addAction(undo_action)

        redo_action = QAction("重做", self)
        redo_action.setShortcut(QKeySequence("Ctrl+Y"))
        redo_action.triggered.connect(self.redo)
        edit_menu.addAction(redo_action)

        edit_menu.addSeparator()

        cut_action = QAction("剪切", self)
        cut_action.setShortcut(QKeySequence("Ctrl+X"))
        cut_action.triggered.connect(self.cut)
        edit_menu.addAction(cut_action)

        copy_action = QAction("复制", self)
        copy_action.setShortcut(QKeySequence("Ctrl+C"))
        copy_action.triggered.connect(self.copy)
        edit_menu.addAction(copy_action)

        paste_action = QAction("粘贴", self)
        paste_action.setShortcut(QKeySequence("Ctrl+V"))
        paste_action.triggered.connect(self.paste)
        edit_menu.addAction(paste_action)

        edit_menu.addSeparator()

        delete_action = QAction("删除", self)
        delete_action.setShortcut(QKeySequence("Delete"))
        delete_action.triggered.connect(self.delete_selected)
        edit_menu.addAction(delete_action)

        select_all_action = QAction("全选", self)
        select_all_action.setShortcut(QKeySequence("Ctrl+A"))
        select_all_action.triggered.connect(self.select_all)
        edit_menu.addAction(select_all_action)

        edit_menu.addSeparator()

        global_params_action = QAction("全局参数", self)
        global_params_action.setShortcut(QKeySequence("Ctrl+G"))
        global_params_action.triggered.connect(self.edit_global_parameters)
        edit_menu.addAction(global_params_action)

        preferences_action = QAction("首选项", self)
        preferences_action.triggered.connect(self.show_preferences)
        edit_menu.addAction(preferences_action)

        # 视图菜单
        view_menu = menubar.addMenu("视图")

        zoom_in_action = QAction("放大", self)
        zoom_in_action.setShortcut(QKeySequence("Ctrl++"))
        zoom_in_action.triggered.connect(self.zoom_in)
        view_menu.addAction(zoom_in_action)

        zoom_out_action = QAction("缩小", self)
        zoom_out_action.setShortcut(QKeySequence("Ctrl+-"))
        zoom_out_action.triggered.connect(self.zoom_out)
        view_menu.addAction(zoom_out_action)

        reset_zoom_action = QAction("重置缩放", self)
        reset_zoom_action.setShortcut(QKeySequence("Ctrl+0"))
        reset_zoom_action.triggered.connect(self.reset_zoom)
        view_menu.addAction(reset_zoom_action)

        view_menu.addSeparator()

        show_grid_action = QAction("显示网格", self)
        show_grid_action.setCheckable(True)
        show_grid_action.setChecked(True)
        show_grid_action.triggered.connect(self.toggle_grid)
        view_menu.addAction(show_grid_action)

        snap_to_grid_action = QAction("对齐网格", self)
        snap_to_grid_action.setCheckable(True)
        snap_to_grid_action.setChecked(True)
        snap_to_grid_action.triggered.connect(self.toggle_snap)
        view_menu.addAction(snap_to_grid_action)

        auto_arrange_action = QAction("自动布局", self)
        auto_arrange_action.triggered.connect(self.arrange_layout)
        view_menu.addAction(auto_arrange_action)

        # 仿真菜单
        sim_menu = menubar.addMenu("仿真")

        run_sim_action = QAction("运行仿真", self)
        run_sim_action.setShortcut(QKeySequence("F5"))
        run_sim_action.triggered.connect(self.run_simulation)
        sim_menu.addAction(run_sim_action)

        stop_sim_action = QAction("停止仿真", self)
        stop_sim_action.setShortcut(QKeySequence("Shift+F5"))
        stop_sim_action.triggered.connect(self.stop_simulation)
        sim_menu.addAction(stop_sim_action)

        show_results_action = QAction("显示仿真结果", self)
        show_results_action.triggered.connect(self.show_simulation_results)
        sim_menu.addAction(show_results_action)

        sim_menu.addSeparator()

    def create_tool_bar(self):
        """创建工具栏"""
        # 文件工具栏
        file_toolbar = self.addToolBar("文件")
        file_toolbar.setObjectName("FileToolbar")

        new_action = QAction(QIcon.fromTheme("document-new"), "新建", self)
        new_action.triggered.connect(self.new_design)
        file_toolbar.addAction(new_action)

        open_action = QAction(QIcon.fromTheme("document-open"), "打开", self)
        open_action.triggered.connect(self.open_design)
        file_toolbar.addAction(open_action)

        save_action = QAction(QIcon.fromTheme("document-save"), "保存", self)
        save_action.triggered.connect(self.save_design)
        file_toolbar.addAction(save_action)

        file_toolbar.addSeparator()

        # 编辑工具栏
        edit_toolbar = self.addToolBar("编辑")
        edit_toolbar.setObjectName("EditToolbar")

        undo_action = QAction(QIcon.fromTheme("edit-undo"), "撤销", self)
        undo_action.triggered.connect(self.undo)
        edit_toolbar.addAction(undo_action)

        redo_action = QAction(QIcon.fromTheme("edit-redo"), "重做", self)
        redo_action.triggered.connect(self.redo)
        edit_toolbar.addAction(redo_action)

        edit_toolbar.addSeparator()

        cut_action = QAction(QIcon.fromTheme("edit-cut"), "剪切", self)
        cut_action.triggered.connect(self.cut)
        edit_toolbar.addAction(cut_action)

        copy_action = QAction(QIcon.fromTheme("edit-copy"), "复制", self)
        copy_action.triggered.connect(self.copy)
        edit_toolbar.addAction(copy_action)

        paste_action = QAction(QIcon.fromTheme("edit-paste"), "粘贴", self)
        paste_action.triggered.connect(self.paste)
        edit_toolbar.addAction(paste_action)

        delete_action = QAction(QIcon.fromTheme("edit-delete"), "删除", self)
        delete_action.triggered.connect(self.delete_selected)
        edit_toolbar.addAction(delete_action)

        # 仿真工具栏
        sim_toolbar = self.addToolBar("仿真")
        sim_toolbar.setObjectName("SimulationToolbar")

        run_action = QAction(QIcon.fromTheme("media-playback-start"), "运行", self)
        run_action.triggered.connect(self.run_simulation)
        sim_toolbar.addAction(run_action)

        stop_action = QAction(QIcon.fromTheme("media-playback-stop"), "停止", self)
        stop_action.triggered.connect(self.stop_simulation)
        sim_toolbar.addAction(stop_action)

        validate_action = QAction(QIcon.fromTheme("tools-check-spelling"), "验证", self)
        # validate_action.triggered.connect(self.validate_design)
        sim_toolbar.addAction(validate_action)

        # 视图工具栏
        view_toolbar = self.addToolBar("视图")
        view_toolbar.setObjectName("ViewToolbar")

        zoom_in_action = QAction(QIcon.fromTheme("zoom-in"), "放大", self)
        zoom_in_action.triggered.connect(self.zoom_in)
        view_toolbar.addAction(zoom_in_action)

        zoom_out_action = QAction(QIcon.fromTheme("zoom-out"), "缩小", self)
        zoom_out_action.triggered.connect(self.zoom_out)
        view_toolbar.addAction(zoom_out_action)

        reset_zoom_action = QAction(QIcon.fromTheme("zoom-original"), "重置", self)
        reset_zoom_action.triggered.connect(self.reset_zoom)
        view_toolbar.addAction(reset_zoom_action)

        view_toolbar.addSeparator()

        arrange_action = QAction(QIcon.fromTheme("view-grid"), "布局", self)
        arrange_action.triggered.connect(self.arrange_layout)
        view_toolbar.addAction(arrange_action)

        show_results_btn = QAction(QIcon.fromTheme("view-statistics"), "显示结果", self)
        show_results_btn.triggered.connect(self.show_simulation_results)
        sim_toolbar.addAction(show_results_btn)

    def create_status_bar(self):
        """创建状态栏"""
        # 状态标签
        self.q_label = QLabel("就绪")
        self.status_label = self.q_label
        self.statusBar().addWidget(self.status_label, 1)

        # 设计信息
        self.design_info_label = QLabel("组件: 0 | 连接: 0")
        self.statusBar().addWidget(self.design_info_label)

        # 更新设计信息
        self.update_design_info()

    def connect_signals(self):
        """连接信号"""
        # 工作区信号
        self.workspace.simulation_completed.connect(self.on_simulation_completed)
        self.workspace.simulation_error.connect(self.on_simulation_error)

        # 定时更新设计信息
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self.update_design_info)
        self.update_timer.start(1000)  # 每秒更新一次

    def update_design_info(self):
        """更新设计信息"""
        info = self.workspace.get_design_info()
        self.design_info_label.setText(f"组件: {info['component_count']} | 连接: {info['connection_count']}")

        # 更新状态标签
        # if info['simulation_ready']:
        #     self.status_label.setText("仿真就绪")
        #     self.status_label.setStyleSheet("color: green;")
        if info['component_count'] > 0:
            self.status_label.setText("设计就绪")
            self.status_label.setStyleSheet("color: blue;")
        else:
            self.status_label.setText("就绪")
            self.status_label.setStyleSheet("")

    def new_design(self):
        """新建设计"""
        if self.workspace.components:
            reply = QMessageBox.question(
                self, "新建设计",
                "当前设计尚未保存，是否保存？",
                QMessageBox.StandardButton.Yes |
                QMessageBox.StandardButton.No |
                QMessageBox.StandardButton.Cancel
            )

            if reply == QMessageBox.StandardButton.Yes:
                if not self.save_design():
                    return
            elif reply == QMessageBox.StandardButton.Cancel:
                return

        # self.workspace.clear_design()
        self.current_file = None
        self.setWindowTitle("光通信仿真平台 - 未命名")

        # self.message_area.append_message("已创建新设计", "INFO")
        self.statusBar().showMessage("已创建新设计", 3000)

    def open_design(self):
        """打开设计"""
        if self.workspace.components:
            reply = QMessageBox.question(
                self, "打开设计",
                "当前设计尚未保存，是否保存？",
                QMessageBox.StandardButton.Yes |
                QMessageBox.StandardButton.No |
                QMessageBox.StandardButton.Cancel
            )

            if reply == QMessageBox.StandardButton.Yes:
                if not self.save_design():
                    return
            elif reply == QMessageBox.StandardButton.Cancel:
                return

        filename, _ = QFileDialog.getOpenFileName(
            self, "打开设计文件", "",
            "设计文件 (*.json);;所有文件 (*)"
        )

        if filename:
            if self.workspace.load_design(filename):
                self.current_file = filename
                self.setWindowTitle(f"光通信仿真平台 - {os.path.basename(filename)}")
                self.add_recent_file(filename)

                # self.message_area.append_message(f"已加载设计文件: {filename}", "SUCCESS")
                self.statusBar().showMessage(f"已加载设计文件: {filename}", 3000)

    def save_design(self):
        """保存设计"""
        if self.current_file:
            self.workspace.save_design(self.current_file)
            # self.message_area.append_message(f"设计已保存到: {self.current_file}", "SUCCESS")
            self.statusBar().showMessage(f"设计已保存到: {self.current_file}", 3000)
            return True
        else:
            return self.save_design_as()

    def save_design_as(self):
        """另存为设计"""
        filename, _ = QFileDialog.getSaveFileName(
            self, "保存设计文件", "design.json"
            "设计文件 (*.json);;所有文件 (*)"
        )

        if filename:
            self.workspace.save_design(filename)
            self.current_file = filename
            self.setWindowTitle(f"光通信仿真平台 - {os.path.basename(filename)}")
            self.add_recent_file(filename)

            # self.message_area.append_message(f"设计已保存到: {filename}", "SUCCESS")
            self.statusBar().showMessage(f"设计已保存到: {filename}", 3000)
            return True

        return False

    def import_design(self):
        """导入设计"""
        filename, _ = QFileDialog.getOpenFileName(
            self, "导入设计文件", "",
            "支持的文件 (*.json *.xml *.yaml);;所有文件 (*)"
        )

        if filename:
            # TODO: 实现导入功能
            self.message_area.append_message(f"导入文件: {filename}", "INFO")

    def export_design(self):
        """导出设计"""
        filename, _ = QFileDialog.getSaveFileName(
            self, "导出设计文件", "design_export",
            "图像文件 (*.png *.jpg);;PDF文件 (*.pdf);;所有文件 (*)"
        )

        if filename:
            # 导出为图像
            if filename.endswith(('.png', '.jpg', '.jpeg')):
                self.export_as_image(filename)
            # 导出为PDF
            elif filename.endswith('.pdf'):
                self.export_as_pdf(filename)

    def export_as_image(self, filename):
        """导出为图像"""
        # 获取场景边界
        rect = self.workspace.scene.itemsBoundingRect()

        # 创建图像
        image = QImage(rect.size().toSize(), QImage.Format.Format_ARGB32)
        image.fill(Qt.GlobalColor.white)

        # 绘制场景
        painter = QPainter(image)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        self.workspace.scene.render(painter)
        painter.end()

        # 保存图像
        image.save(filename)

        self.message_area.append_message(f"设计已导出为图像: {filename}", "SUCCESS")

    def export_as_pdf(self, filename):
        """导出为PDF"""
        # TODO: 实现PDF导出
        self.message_area.append_message(f"PDF导出功能尚未实现", "WARNING")

    def add_recent_file(self, filename):
        """添加最近打开文件"""
        if filename in self.recent_files:
            self.recent_files.remove(filename)

        self.recent_files.insert(0, filename)

        if len(self.recent_files) > self.max_recent_files:
            self.recent_files = self.recent_files[:self.max_recent_files]

        self.update_recent_menu()
        self.save_settings()

    def update_recent_menu(self):
        """更新最近打开菜单"""
        self.recent_menu.clear()

        if not self.recent_files:
            self.recent_menu.setEnabled(False)
            return

        self.recent_menu.setEnabled(True)

        for i, filename in enumerate(self.recent_files):
            if i < 9:
                shortcut = f"&{i + 1} "
            else:
                shortcut = ""

            action = QAction(f"{shortcut}{os.path.basename(filename)}", self)
            action.setData(filename)
            action.triggered.connect(lambda checked, f=filename: self.open_recent_file(f))
            self.recent_menu.addAction(action)

        self.recent_menu.addSeparator()
        clear_action = QAction("清空列表", self)
        clear_action.triggered.connect(self.clear_recent_files)
        self.recent_menu.addAction(clear_action)

    def open_recent_file(self, filename):
        """打开最近文件"""
        if os.path.exists(filename):
            if self.workspace.load_design(filename):
                self.current_file = filename
                self.setWindowTitle(f"光通信仿真平台 - {os.path.basename(filename)}")
                self.message_area.append_message(f"已加载设计文件: {filename}", "SUCCESS")
        else:
            QMessageBox.warning(self, "文件不存在", f"文件不存在: {filename}")
            self.recent_files.remove(filename)
            self.update_recent_menu()

    def clear_recent_files(self):
        """清空最近文件列表"""
        self.recent_files.clear()
        self.update_recent_menu()
        self.save_settings()

    def undo(self):
        """撤销"""
        # TODO: 实现撤销功能
        self.message_area.append_message("撤销功能尚未实现", "WARNING")

    def redo(self):
        """重做"""
        # TODO: 实现重做功能
        self.message_area.append_message("重做功能尚未实现", "WARNING")

    def cut(self):
        """剪切"""
        # TODO: 实现剪切功能
        self.message_area.append_message("剪切功能尚未实现", "WARNING")

    def copy(self):
        """复制"""
        # TODO: 实现复制功能
        self.message_area.append_message("复制功能尚未实现", "WARNING")

    def paste(self):
        """粘贴"""
        # TODO: 实现粘贴功能
        self.message_area.append_message("粘贴功能尚未实现", "WARNING")

    def delete_selected(self):
        """删除选中项"""
        self.workspace.delete_selected_items()

    def select_all(self):
        """全选"""
        self.workspace.select_all_items()

    def edit_global_parameters(self):
        """编辑全局参数"""
        self.workspace.edit_global_parameters()

    def show_preferences(self):
        """显示首选项"""
        dialog = QDialog(self)
        dialog.setWindowTitle("首选项")
        dialog.setMinimumSize(400, 300)

        layout = QVBoxLayout(dialog)

        # Matlab设置
        matlab_group = QGroupBox("MATLAB设置")
        matlab_layout = QFormLayout()

        matlab_path_edit = QLineEdit()
        matlab_path_edit.setPlaceholderText("MATLAB安装路径")
        matlab_layout.addRow("MATLAB路径:", matlab_path_edit)

        auto_start_check = QCheckBox("启动时自动连接MATLAB")
        auto_start_check.setChecked(True)
        matlab_layout.addRow(auto_start_check)

        matlab_group.setLayout(matlab_layout)
        layout.addWidget(matlab_group)

        # 界面设置
        ui_group = QGroupBox("界面设置")
        ui_layout = QFormLayout()

        theme_combo = QComboBox()
        theme_combo.addItems(["浅色主题", "深色主题", "自动"])
        ui_layout.addRow("主题:", theme_combo)

        language_combo = QComboBox()
        language_combo.addItems(["简体中文", "English"])
        ui_layout.addRow("语言:", language_combo)

        ui_group.setLayout(ui_layout)
        layout.addWidget(ui_group)

        # 按钮
        button_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok |
            QDialogButtonBox.StandardButton.Cancel |
            QDialogButtonBox.StandardButton.Apply
        )

        def apply_preferences():
            # TODO: 应用首选项
            pass

        button_box.accepted.connect(dialog.accept)
        button_box.rejected.connect(dialog.reject)
        button_box.button(QDialogButtonBox.StandardButton.Apply).clicked.connect(apply_preferences)
        layout.addWidget(button_box)

        dialog.exec()

    def zoom_in(self):
        """放大"""
        self.workspace.scale(1.2, 1.2)

    def zoom_out(self):
        """缩小"""
        self.workspace.scale(0.8, 0.8)

    def reset_zoom(self):
        """重置缩放"""
        self.workspace.resetTransform()

    def toggle_grid(self):
        """切换网格显示"""
        # TODO: 实现网格显示
        pass

    def toggle_snap(self):
        """切换网格对齐"""
        self.workspace.grid_snap = not self.workspace.grid_snap

    def arrange_layout(self):
        """自动布局"""
        self.workspace.arrange_layout()

    def run_simulation(self):
        """运行仿真"""
        self.workspace.run_simulation(self.matlab_engine)

    def stop_simulation(self):
        """停止仿真"""
        self.workspace.cancel_simulation()

    def on_simulation_completed(self, results):
        """仿真完成"""
        self.message_area.append_message("仿真完成", "SUCCESS")

        # 显示结果对话框（DesignWidget中的SimulationResultsDialog会自动显示）
        # 无需额外操作，因为workspace.show_simulation_results已经调用了对话框

    def on_simulation_error(self, error_message):
        """仿真错误"""
        self.message_area.append_message(f"仿真错误: {error_message}", "ERROR")

    def show_parameter_manager(self):
        """显示参数管理器"""
        # TODO: 实现参数管理器
        self.message_area.append_message("参数管理器功能尚未实现", "WARNING")

    def show_template_manager(self):
        """显示模板管理器"""
        # TODO: 实现模板管理器
        self.message_area.append_message("模板管理器功能尚未实现", "WARNING")

    def show_script_editor(self):
        """显示脚本编辑器"""
        # TODO: 实现脚本编辑器
        self.message_area.append_message("脚本编辑器功能尚未实现", "WARNING")

    def show_data_analyzer(self):
        """显示数据分析器"""
        # TODO: 实现数据分析器
        self.message_area.append_message("数据分析器功能尚未实现", "WARNING")

    def show_documentation(self):
        """显示文档"""
        # TODO: 实现文档查看
        self.message_area.append_message("文档功能尚未实现", "WARNING")

    def show_examples(self):
        """显示示例"""
        # TODO: 实现示例查看
        self.message_area.append_message("示例功能尚未实现", "WARNING")

    def show_about(self):
        """显示关于对话框"""
        about_text = """
        <h1>光通信仿真实验平台</h1>
        <p><b>版本:</b> 1.0.0</p>
        <p><b>开发团队:</b> 香港理工大学光子研究中心</p>
        <p><b>描述:</b> 基于Python和MATLAB的光通信系统仿真平台</p>
        <p><b>功能:</b></p>
        <ul>
            <li>图形化光通信系统设计</li>
            <li>MATLAB仿真引擎集成</li>
            <li>参数化组件配置</li>
            <li>实时仿真结果可视化</li>
        </ul>
        <p><b>技术支持:</b> photonlab@polyu.edu.hk</p>
        <p><b>版权:</b> © 2024 香港理工大学</p>
        """

        QMessageBox.about(self, "关于光通信仿真实验平台", about_text)

    def load_settings(self):
        """加载设置"""
        settings_file = "settings.json"

        if os.path.exists(settings_file):
            try:
                with open(settings_file, 'r') as f:
                    settings = json.load(f)

                self.recent_files = settings.get('recent_files', [])
                self.update_recent_menu()

            except:
                pass

    def save_settings(self):
        """保存设置"""
        settings = {
            'recent_files': self.recent_files
        }

        try:
            with open("settings.json", 'w') as f:
                json.dump(settings, f, indent=2)
        except:
            pass

    def closeEvent(self, event):
        """关闭事件"""
        if self.workspace.components:
            reply = QMessageBox.question(
                self, "退出确认",
                "当前设计尚未保存，是否保存？",
                QMessageBox.StandardButton.Yes |
                QMessageBox.StandardButton.No |
                QMessageBox.StandardButton.Cancel
            )

            if reply == QMessageBox.StandardButton.Yes:
                if not self.save_design():
                    event.ignore()
                    return
            elif reply == QMessageBox.StandardButton.Cancel:
                event.ignore()
                return

        # 停止Matlab引擎
        # self.matlab_engine.stop_engine()

        # 保存设置
        self.save_settings()

        event.accept()

    def show_simulation_results(self):
        """显示最近一次仿真的详细结果（功率预算图 + 表格）"""
        if not hasattr(self.workspace, 'last_sim_results') or self.workspace.last_sim_results is None:
            QMessageBox.information(self, "提示", "尚未运行任何仿真，请先运行仿真。")
            return

        results = self.workspace.last_sim_results
        dialog = SimulationResultsDialog(results, self.workspace, self)
        dialog.exec()








