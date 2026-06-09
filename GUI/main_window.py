"""Main application window."""

from __future__ import annotations

import json
import tempfile
import threading
from pathlib import Path

from PyQt5.QtCore import QThread, Qt, pyqtSignal
from PyQt5.QtGui import QColor, QIcon, QPainter, QPen, QPixmap, QKeySequence
from PyQt5.QtWidgets import QAction, QApplication, QFileDialog, QLabel, QMainWindow, QMessageBox, QProgressDialog, QSplitter, QStyle, QToolBar, QToolButton, QVBoxLayout, QWidget

from component_panel import ComponentPanel
from matlab_engine_manager import MatlabEngineManager
from matlab_topology_runner import MatlabTopologyRunner, SimulationCancelled
from output_widget import OutputWidget
from parameter_sweep_dialog import ParameterSweepDialog
from simulation_result_viewer import AnalyzerPlotDialog, SimulationResultDialog
from signal_plotter import _as_array
from topology_display import build_component_display_names, build_node_display_indices, result_component_allowed
from workspace_panel import WorkspacePanel
from topology_executor import TopologyCycleError, TopologyExecutor


class MatlabTopologyWorker(QThread):
    log_message = pyqtSignal(str, str)
    finished_ok = pyqtSignal(object)
    cancelled = pyqtSignal(str)
    failed = pyqtSignal(str)

    def __init__(self, engine_manager: MatlabEngineManager, topology: dict, parent=None):
        super().__init__(parent)
        self.engine_manager = engine_manager
        self.topology = topology
        self.cancel_event = threading.Event()

    def request_stop(self) -> None:
        self.cancel_event.set()

    def run(self) -> None:
        try:
            runner = MatlabTopologyRunner(
                self.engine_manager,
                log=lambda message, source="INFO": self.log_message.emit(message, source),
                cancel_event=self.cancel_event,
            )
            outputs = runner.run(self.topology)
            self.finished_ok.emit(outputs)
        except SimulationCancelled as exc:
            self.cancelled.emit(str(exc))
        except Exception as exc:
            self.failed.emit(str(exc))


class MatlabShutdownWorker(QThread):
    progress = pyqtSignal(str)
    finished_ok = pyqtSignal()
    failed = pyqtSignal(str)

    def __init__(self, engine_manager: MatlabEngineManager, parent=None):
        super().__init__(parent)
        self.engine_manager = engine_manager

    def run(self) -> None:
        try:
            if self.engine_manager.is_running():
                eng = self.engine_manager.engine
                if eng is not None:
                    self.progress.emit("正在清理 MATLAB 工作区...")
                    try:
                        eng.eval(
                            "try, close all hidden; clearvars; if usejava('jvm'), java.lang.System.gc(); end; drawnow; catch, end",
                            nargout=0,
                        )
                    except Exception:
                        pass
                self.progress.emit("正在断开 MATLAB 引擎...")
                self.engine_manager.stop()
            self.finished_ok.emit()
        except Exception as exc:
            self.failed.emit(str(exc))


class MainWindow(QMainWindow):
    """Main window with legacy-consistent three-section layout."""

    def __init__(
        self,
        engine_manager: MatlabEngineManager,
        initial_engine_status: str = "Unknown",
        parent=None,
    ):
        super().__init__(parent)
        self.engine_manager = engine_manager
        self._simulation_worker = None
        self._shutdown_worker = None
        self._shutdown_dialog = None
        self._shutdown_in_progress = False
        self._allow_close_after_shutdown = False
        self.stop_simulation_actions = []
        self._latest_topology = None
        self._latest_outputs = {}
        self._analysis_windows = []
        self._topology_file_path: Path | None = None
        self._topology_path_is_temporary = False
        self._design_dirty = False
        self._saved_design_snapshot = ""
        self._suppress_dirty_tracking = False
        self.setWindowTitle("多维复用超高速光接入端到端系统仿真平台")
        self.resize(1280, 820)

        self._setup_central(engine_manager)
        self._create_menu_bar()
        self._create_tool_bars()
        self._create_status_area(initial_engine_status)
        self._connect_signals()
        self._set_simulation_running(False)
        self._mark_design_clean()

    def _setup_central(self, engine_manager: MatlabEngineManager) -> None:
        central = QWidget(self)
        root_layout = QVBoxLayout(central)
        root_layout.setContentsMargins(6, 6, 6, 6)
        root_layout.setSpacing(6)

        title_label = QLabel("多维复用超高速光接入端到端系统仿真平台")
        title_label.setObjectName("windowTitleLabel")
        title_label.setAlignment(Qt.AlignCenter)
        root_layout.addWidget(title_label)

        splitter = QSplitter(Qt.Vertical)
        root_layout.addWidget(splitter, 1)

        self.component_panel = ComponentPanel(self)
        self.workspace_panel = WorkspacePanel(self)

        message_container = QWidget(self)
        message_layout = QVBoxLayout(message_container)
        message_layout.setContentsMargins(4, 4, 4, 4)
        self.output_widget = OutputWidget(self, engine_manager=engine_manager)
        message_layout.addWidget(self.output_widget)

        splitter.addWidget(self.component_panel)
        splitter.addWidget(self.workspace_panel)
        splitter.addWidget(message_container)
        splitter.setSizes([220, 420, 220])

        self.setCentralWidget(central)

    def _create_menu_bar(self) -> None:
        menu = self.menuBar()

        file_menu = menu.addMenu("文件")
        file_menu.addAction(self._make_action("新建设计", QKeySequence.New, self._new_topology))
        file_menu.addAction(self._make_action("打开设计", QKeySequence.Open, self._open_topology))
        file_menu.addAction(self._make_action("保存设计", QKeySequence.Save, self._save_topology))
        file_menu.addAction(self._make_action("另存为", QKeySequence.SaveAs, self._save_topology_as))
        file_menu.addSeparator()
        file_menu.addAction(self._make_action("退出", QKeySequence.Quit, self.close))

        edit_menu = menu.addMenu("编辑")
        edit_menu.addAction(self._make_action("全选", QKeySequence.SelectAll, self.workspace_panel.select_all))
        edit_menu.addAction(
            self._make_action(
                "删除",
                [QKeySequence.Delete, QKeySequence("Ctrl+Backspace"), QKeySequence("Meta+Backspace")],
                self.workspace_panel.delete_selected,
            )
        )
        edit_menu.addAction(self._make_action("复制", QKeySequence.Copy, self.workspace_panel.copy_selected))
        edit_menu.addAction(self._make_action("粘贴", QKeySequence.Paste, self.workspace_panel.paste_selected))

        view_menu = menu.addMenu("视图")
        view_menu.addAction(self._make_action("放大", "Ctrl++", self.workspace_panel.zoom_in))
        view_menu.addAction(self._make_action("缩小", "Ctrl+-", self.workspace_panel.zoom_out))
        view_menu.addAction(self._make_action("重置缩放", "Ctrl+0", self.workspace_panel.reset_zoom))

        sim_menu = menu.addMenu("仿真")
        sim_menu.addAction(self._make_action("设计仿真", "F5", self._run_topology_simulation))
        sim_menu.addAction(self._make_action("参数扫描", None, self._configure_parameter_sweep))
        sim_menu.addAction(self._make_action("仿真结果", None, self._show_simulation_results))
        self.stop_simulation_action = self._make_action("停止仿真", "Shift+F5", self._stop_topology_simulation)
        self.stop_simulation_actions.append(self.stop_simulation_action)
        sim_menu.addAction(self.stop_simulation_action)

    def _create_tool_bars(self) -> None:
        file_tb = QToolBar("文件", self)
        self._add_toolbar_action(file_tb, "新建", "SP_FileIcon", self._new_topology)
        self._add_toolbar_action(file_tb, "打开", "SP_DialogOpenButton", self._open_topology)
        self._add_toolbar_action(file_tb, "保存", "SP_DialogSaveButton", self._save_topology)
        self._add_toolbar_action(file_tb, "另存为", "SP_DriveFDIcon", self._save_topology_as)
        self.addToolBar(file_tb)

        edit_tb = QToolBar("编辑", self)
        self._add_toolbar_action(edit_tb, "全选", "custom:select-all", self.workspace_panel.select_all)
        self._add_toolbar_action(edit_tb, "删除", "custom:delete", self.workspace_panel.delete_selected)
        self._add_toolbar_action(edit_tb, "复制", "SP_FileDialogDetailedView", self.workspace_panel.copy_selected)
        self._add_toolbar_action(edit_tb, "粘贴", "custom:paste", self.workspace_panel.paste_selected)
        self.addToolBar(edit_tb)

        view_tb = QToolBar("视图", self)
        self._add_toolbar_action(view_tb, "放大", "custom:zoom-in", self.workspace_panel.zoom_in)
        self._add_toolbar_action(view_tb, "缩小", "custom:zoom-out", self.workspace_panel.zoom_out)
        self._add_toolbar_action(view_tb, "重置", "SP_BrowserReload", self.workspace_panel.reset_zoom)
        self.addToolBar(view_tb)

        sim_tb = QToolBar("仿真", self)
        self._add_toolbar_action(sim_tb, "运行", "SP_MediaPlay", self._run_topology_simulation)
        toolbar_stop_action = self._add_toolbar_action(sim_tb, "停止仿真", "SP_MediaStop", self._stop_topology_simulation)
        self.stop_simulation_actions.append(toolbar_stop_action)
        self._add_toolbar_action(sim_tb, "参数扫描", "custom:sweep", self._configure_parameter_sweep)
        self._add_toolbar_action(sim_tb, "仿真结果", "SP_FileDialogContentsView", self._show_simulation_results)
        self.addToolBar(sim_tb)

    def _create_status_area(self, initial_engine_status: str) -> None:
        self.status_label = QLabel("就绪", self)
        self.design_info_label = QLabel("组件: 0 | 连接: 0", self)
        self.engine_status_label = QLabel(self)

        self.statusBar().addWidget(self.status_label, 1)
        self.statusBar().addWidget(self.design_info_label)
        self.statusBar().addWidget(self.engine_status_label)

        self.update_engine_status(initial_engine_status)

    def _connect_signals(self) -> None:
        self.output_widget.engine_status_changed.connect(self.update_engine_status)
        self.component_panel.component_selected.connect(self._on_component_selected)
        self.workspace_panel.topology_changed.connect(self._on_topology_changed)
        self.workspace_panel.design_changed.connect(self._on_design_changed)
        self.workspace_panel.analyzer_open_requested.connect(self._show_analyzer_for_node)
        self.output_widget.log_python_output("GUI initialized.")

    def _make_action(self, text: str, shortcut, callback) -> QAction:
        action = QAction(text, self)
        if shortcut:
            if isinstance(shortcut, list):
                action.setShortcuts([QKeySequence(item) for item in shortcut])
            else:
                action.setShortcut(QKeySequence(shortcut))
        action.triggered.connect(callback)
        return action

    def _add_toolbar_action(self, toolbar: QToolBar, text: str, icon_name: str, callback) -> QAction:
        action = self._make_action(text, None, callback)
        icon = self._standard_icon(icon_name)
        if not icon.isNull():
            action.setIcon(icon)
            action.setText("")
        action.setToolTip(text)
        action.setStatusTip(text)
        toolbar.addAction(action)

        button = toolbar.widgetForAction(action)
        if isinstance(button, QToolButton):
            button.setToolButtonStyle(Qt.ToolButtonIconOnly if not icon.isNull() else Qt.ToolButtonTextOnly)
            button.setAccessibleName(text)
        return action

    def _standard_icon(self, icon_name: str):
        if icon_name.startswith("custom:"):
            return self._custom_toolbar_icon(icon_name.removeprefix("custom:"))
        pixmap_id = getattr(QStyle, icon_name, None)
        if pixmap_id is None:
            return QIcon()
        return self.style().standardIcon(pixmap_id)

    def _custom_toolbar_icon(self, name: str) -> QIcon:
        pixmap = QPixmap(24, 24)
        pixmap.fill(Qt.transparent)

        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.Antialiasing)
        ink = QColor("#26394d")
        accent = QColor("#2f80c2")
        painter.setPen(QPen(ink, 2.0, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))

        if name == "select-all":
            painter.setPen(QPen(ink, 1.6, Qt.DashLine, Qt.RoundCap, Qt.RoundJoin))
            painter.drawRoundedRect(4, 4, 16, 16, 2, 2)
            painter.setPen(QPen(accent, 1.6, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
            painter.drawRoundedRect(8, 8, 8, 8, 1, 1)
        elif name == "delete":
            painter.setPen(QPen(QColor("#c62828"), 3.0, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
            painter.drawLine(6, 6, 18, 18)
            painter.drawLine(18, 6, 6, 18)
        elif name == "sweep":
            painter.setPen(QPen(ink, 1.6, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
            painter.drawLine(4, 18, 20, 18)
            painter.drawLine(4, 18, 4, 5)
            painter.setPen(QPen(accent, 2.0, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
            painter.drawLine(5, 16, 9, 13)
            painter.drawLine(9, 13, 13, 9)
            painter.drawLine(13, 9, 19, 6)
            painter.setBrush(accent)
            painter.setPen(Qt.NoPen)
            painter.drawEllipse(7, 11, 4, 4)
            painter.drawEllipse(15, 4, 4, 4)
        elif name in {"zoom-in", "zoom-out"}:
            painter.drawEllipse(4, 4, 12, 12)
            painter.drawLine(14, 14, 20, 20)
            painter.setPen(QPen(accent, 2.0, Qt.SolidLine, Qt.RoundCap))
            painter.drawLine(8, 10, 12, 10)
            if name == "zoom-in":
                painter.drawLine(10, 8, 10, 12)
        elif name == "paste":
            painter.drawRoundedRect(6, 5, 13, 16, 2, 2)
            painter.setPen(QPen(accent, 2.0, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
            painter.drawRoundedRect(9, 3, 7, 4, 1, 1)
            painter.drawLine(9, 11, 16, 11)
            painter.drawLine(9, 15, 15, 15)

        painter.end()
        return QIcon(pixmap)

    def _new_topology(self) -> None:
        if not self._confirm_saved_or_continue():
            return
        self._suppress_dirty_tracking = True
        try:
            self.workspace_panel.clear_topology()
        finally:
            self._suppress_dirty_tracking = False
        self._set_topology_file_path(None)
        self._mark_design_clean()
        self.status_label.setText("新建设计")

    def _open_topology(self) -> None:
        if not self._confirm_saved_or_continue():
            return
        file_path, _ = QFileDialog.getOpenFileName(self, "打开设计文件", "", "JSON (*.json)")
        if file_path:
            self._suppress_dirty_tracking = True
            try:
                self.workspace_panel.load_topology(file_path)
            finally:
                self._suppress_dirty_tracking = False
            self._set_topology_file_path(file_path)
            self._mark_design_clean()
            self.status_label.setText("设计已加载")
            self.output_widget.append_message(f"Design loaded: {file_path}", source="INFO")

    def _save_topology(self) -> bool:
        if self._topology_file_path is not None and not self._topology_path_is_temporary:
            self.workspace_panel.save_topology(str(self._topology_file_path))
            self._mark_design_clean()
            self.status_label.setText("设计已保存")
            self.output_widget.append_message(f"Design saved: {self._topology_file_path}", source="INFO")
            return True
        return self._save_topology_as()

    def _save_topology_as(self) -> bool:
        default_name = self._topology_file_path.name if self._topology_file_path else "design.json"
        file_path, _ = QFileDialog.getSaveFileName(self, "另存设计文件", default_name, "JSON (*.json)")
        if file_path:
            file_path = str(self._ensure_json_suffix(Path(file_path)))
            self.workspace_panel.save_topology(file_path)
            self._set_topology_file_path(file_path, force_saved=True)
            self._mark_design_clean()
            self.status_label.setText("设计已保存")
            self.output_widget.append_message(f"Design saved: {file_path}", source="INFO")
            return True
        return False

    def _set_topology_file_path(self, file_path: str | Path | None, force_saved: bool = False) -> None:
        self._topology_file_path = Path(file_path).expanduser().resolve() if file_path else None
        self._topology_path_is_temporary = (
            False if force_saved or self._topology_file_path is None else self._is_temporary_path(self._topology_file_path)
        )
        self._refresh_window_title()

    def _refresh_window_title(self) -> None:
        app_name = "多维复用超高速光接入端到端系统仿真平台"
        dirty = "*" if self._design_dirty else ""
        if self._topology_file_path is None:
            self.setWindowTitle(f"{dirty}{app_name}")
            return
        suffix = "临时文件，保存时将另存为" if self._topology_path_is_temporary else str(self._topology_file_path)
        self.setWindowTitle(f"{dirty}{app_name} - {self._topology_file_path.name} ({suffix})")

    def _current_design_snapshot(self) -> str:
        data = self.workspace_panel.scene.serialize()
        nodes = sorted(data.get("nodes", []), key=lambda item: int(item.get("id", 0)))
        edges = sorted(
            data.get("edges", []),
            key=lambda item: (
                int(item.get("source_id", 0)),
                str(item.get("source_side", "")),
                int(item.get("target_id", 0)),
                str(item.get("target_side", "")),
            ),
        )
        normalized = {
            "nodes": nodes,
            "edges": edges,
            "parameter_sweeps": data.get("parameter_sweeps", []),
        }
        return json.dumps(normalized, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

    def _mark_design_clean(self) -> None:
        self._saved_design_snapshot = self._current_design_snapshot()
        self._design_dirty = False
        self._refresh_window_title()

    def _on_design_changed(self) -> None:
        if self._suppress_dirty_tracking:
            return
        self._design_dirty = self._current_design_snapshot() != self._saved_design_snapshot
        self._refresh_window_title()

    def _confirm_saved_or_continue(self) -> bool:
        self._on_design_changed()
        if not self._design_dirty:
            return True

        reply = QMessageBox.warning(
            self,
            "保存当前设计",
            "当前设计包含未保存的修改。是否在继续前保存？",
            QMessageBox.Save | QMessageBox.Discard | QMessageBox.Cancel,
            QMessageBox.Save,
        )
        if reply == QMessageBox.Save:
            return self._save_topology()
        if reply == QMessageBox.Discard:
            return True
        return False

    @staticmethod
    def _ensure_json_suffix(path: Path) -> Path:
        return path if path.suffix.lower() == ".json" else path.with_suffix(".json")

    @staticmethod
    def _is_temporary_path(path: Path) -> bool:
        path = path.expanduser().resolve()
        candidates = {Path(tempfile.gettempdir()), Path("/tmp"), Path("/private/tmp")}
        for candidate in candidates:
            try:
                path.relative_to(candidate.expanduser().resolve())
                return True
            except ValueError:
                continue
        return False

    def _run_topology_test(self) -> None:
        topology = self.workspace_panel.scene.serialize()
        try:
            executor = TopologyExecutor(topology)
            levels = executor.topological_levels()
            self.output_widget.append_message("Design execution plan:", source="INFO")
            for i, level in enumerate(levels, start=1):
                names = [executor.nodes[nid].name for nid in level]
                self.output_widget.append_message(f"L{i}: {list(zip(level, names))}", source="INFO")

            def _runner(node, inputs_by_port):
                ports = sorted(k for k in inputs_by_port.keys() if not k.startswith("__"))
                self.output_widget.append_message(
                    f"Run node {node.node_id} ({node.name}), inputs={ports}",
                    source="PYTHON",
                )
                return {"default": f"signal_from_{node.name}"}

            outputs = executor.run(_runner)
            self.output_widget.append_message(
                f"Design run finished. Nodes executed: {len(outputs)}",
                source="MATLAB",
            )
            self.status_label.setText("设计运行完成")
        except TopologyCycleError as exc:
            self.output_widget.append_message(f"Design error: {exc}", source="ERROR")
            self.status_label.setText("设计存在环")
        except Exception as exc:
            self.output_widget.append_message(f"Run error: {exc}", source="ERROR")
            self.status_label.setText("运行失败")

    def _run_topology_simulation(self) -> None:
        if self._simulation_worker is not None and self._simulation_worker.isRunning():
            self.output_widget.append_message("设计仿真正在运行中。", source="INFO")
            return

        topology = self.workspace_panel.scene.serialize()
        self._latest_topology = topology
        self.status_label.setText("正在运行设计仿真")

        worker = MatlabTopologyWorker(self.engine_manager, topology, self)
        self._simulation_worker = worker
        worker.log_message.connect(lambda message, source: self.output_widget.append_message(message, source=source))
        worker.finished_ok.connect(self._on_topology_simulation_finished)
        worker.cancelled.connect(self._on_topology_simulation_cancelled)
        worker.failed.connect(self._on_topology_simulation_failed)
        worker.finished.connect(lambda: self._set_simulation_running(False))
        worker.start()
        self._set_simulation_running(True)

    def _stop_topology_simulation(self) -> None:
        worker = self._simulation_worker
        if worker is None or not worker.isRunning():
            self.output_widget.append_message("当前没有正在运行的设计仿真。", source="INFO")
            return
        worker.request_stop()
        self._set_simulation_running(False)
        self.status_label.setText("正在停止设计仿真")
        self.output_widget.append_message("已请求停止仿真，正在等待当前 MATLAB 调用结束或取消。", source="INFO")

    def _configure_parameter_sweep(self) -> None:
        topology = self.workspace_panel.scene.serialize()
        nodes = topology.get("nodes", [])
        if not nodes:
            self.output_widget.append_message("请先在工作区添加组件，再配置参数扫描。", source="INFO")
            return

        dialog = ParameterSweepDialog(nodes, topology.get("parameter_sweeps", []), self)
        if dialog.exec_():
            sweeps = dialog.get_sweeps()
            self.workspace_panel.set_sweep_config(sweeps)
            enabled_count = sum(1 for item in sweeps if item.get("enabled", True))
            self.status_label.setText(f"参数扫描: {enabled_count} 项已启用")
            self.output_widget.append_message(
                f"Parameter sweep configured: {enabled_count} enabled item(s).",
                source="INFO",
            )

    def _on_topology_simulation_finished(self, outputs: dict) -> None:
        self._latest_outputs = outputs or {}
        self._simulation_worker = None
        self.status_label.setText("设计仿真完成")
        self.output_widget.append_message("设计仿真完成。双击光/电分析仪组件可查看对应结果。", source="INFO")

    def _on_topology_simulation_cancelled(self, message: str) -> None:
        self._simulation_worker = None
        self.status_label.setText("设计仿真已停止")
        self.output_widget.append_message(message or "设计仿真已停止。", source="INFO")

    def _on_topology_simulation_failed(self, message: str) -> None:
        self._simulation_worker = None
        self.output_widget.append_message(f"MATLAB run error: {message}", source="ERROR")
        self.status_label.setText("设计仿真失败")

    def _show_analyzer_for_node(self, node_id: int, name: str) -> None:
        normalized = "".join(ch.lower() for ch in name if ch.isalnum())
        display_name = self._display_name_for_node(node_id, name)
        workspace = self._node_workspace(node_id)
        if not workspace:
            self.output_widget.append_message(
                f"{display_name} 暂无可显示结果，请先运行设计仿真并确保该组件已连接信号。",
                source="INFO",
            )
            return
        if "powermeter" in normalized:
            self._show_power_meter_result(display_name, workspace)
            return
        if workspace.get("Status") != "called" or workspace.get("AnalyzerSignal") is None:
            waiting_for = workspace.get("WaitingFor")
            error = workspace.get("Error")
            detail = f"等待: {waiting_for}" if waiting_for else (f"错误: {error}" if error else "无有效分析仪信号")
            self.output_widget.append_message(
                f"{display_name} 暂无可显示结果，{detail}。",
                source="INFO",
            )
            return

        if "oanalyzer" in normalized:
            dialog = AnalyzerPlotDialog.optical(display_name, workspace, self)
        elif "eanalyzer" in normalized:
            dialog = AnalyzerPlotDialog.electrical(display_name, workspace, self)
        else:
            return

        self._analysis_windows.append(dialog)
        dialog.show()

    def _show_power_meter_result(self, display_name: str, workspace: dict) -> None:
        if workspace.get("Status") != "called" or "Power_dBm" not in workspace:
            waiting_for = workspace.get("WaitingFor")
            error = workspace.get("Error")
            detail = f"等待: {waiting_for}" if waiting_for else (f"错误: {error}" if error else "无有效光功率")
            self.output_widget.append_message(f"{display_name} 暂无可显示功率，{detail}。", source="INFO")
            return

        power_dbm = self._scalar_display(workspace.get("Power_dBm"), "dBm")
        power_w = self._scalar_display(workspace.get("Power_Watts"), "W")
        QMessageBox.information(
            self,
            f"光功率 - {display_name}",
            f"{display_name}\n\n光功率: {power_dbm}\n光功率: {power_w}",
        )

    @staticmethod
    def _scalar_display(value, unit: str) -> str:
        arr = _as_array(value)
        if arr.size == 0:
            return "-"
        try:
            return f"{float(arr.reshape(-1)[0]):.6g} {unit}"
        except Exception:
            return f"{value} {unit}"

    def _show_simulation_results(self) -> None:
        rows = []
        topology = self._latest_topology or self.workspace_panel.scene.serialize()
        nodes = topology.get("nodes", [])
        node_names = {int(n.get("id")): str(n.get("name", "")) for n in nodes}
        display_names = build_component_display_names(nodes)
        display_indices = build_node_display_indices(nodes)

        for node_id, outputs in (self._latest_outputs or {}).items():
            if not isinstance(node_id, int):
                continue
            component_name = node_names.get(int(node_id), "")
            if not result_component_allowed(component_name):
                continue
            workspace = self._workspace_from_outputs(outputs)
            if workspace and ("SNR" in workspace or "BER" in workspace):
                rows.extend(
                    self._metric_rows_for_workspace(
                        node_id,
                        display_indices.get(int(node_id), int(node_id)),
                        display_names.get(int(node_id), component_name),
                        workspace,
                    )
                )

        sweep = (self._latest_outputs or {}).get("__sweep__")
        dialog = SimulationResultDialog(rows, sweep, self)
        self._analysis_windows.append(dialog)
        dialog.show()

    def _node_workspace(self, node_id: int) -> dict:
        outputs = (self._latest_outputs or {}).get(node_id)
        return self._workspace_from_outputs(outputs)

    @staticmethod
    def _metric_rows_for_workspace(
        node_id: int,
        display_node_id: int,
        display_name: str,
        workspace: dict,
    ) -> list[dict]:
        snr = _as_array(workspace.get("SNR"))
        ber = _as_array(workspace.get("BER"))
        count = max(int(snr.size), int(ber.size), 1)
        rows = []
        for idx in range(count):
            suffix = f" - ONU {idx + 1}" if count > 1 else ""
            rows.append(
                {
                    "node_id": node_id,
                    "display_node_id": display_node_id,
                    "name": f"{display_name}{suffix}",
                    "SNR": MainWindow._metric_value(snr, idx),
                    "BER": MainWindow._metric_value(ber, idx),
                    "constellation": MainWindow._constellation_for_index(workspace, idx),
                }
            )
        return rows

    @staticmethod
    def _metric_value(values, index: int):
        if values.size == 0:
            return None
        flat = values.reshape(-1)
        return flat[min(index, flat.size - 1)]

    @staticmethod
    def _constellation_for_index(workspace: dict, index: int):
        previews = workspace.get("ConstellationPreviews")
        if previews is not None:
            try:
                if isinstance(previews, (list, tuple)) and previews:
                    return previews[min(index, len(previews) - 1)]
                if hasattr(previews, "__len__") and len(previews) > 0:
                    return previews[min(index, len(previews) - 1)]
            except Exception:
                pass
        return workspace.get("ConstellationPreview") if index == 0 else None

    def _display_name_for_node(self, node_id: int, fallback: str) -> str:
        topology = self._latest_topology or self.workspace_panel.scene.serialize()
        return build_component_display_names(topology.get("nodes", [])).get(int(node_id), fallback)

    @staticmethod
    def _workspace_from_outputs(outputs) -> dict:
        if not isinstance(outputs, dict):
            return {}
        workspace = outputs.get("default") or outputs.get("right") or outputs.get("bottom") or outputs.get("info")
        return workspace if isinstance(workspace, dict) else {}

    def _on_component_selected(self, name: str) -> None:
        self.status_label.setText(f"已选择组件: {name}")
        self.output_widget.append_message(f"Component selected: {name}", source="INFO")

    def _on_topology_changed(self, component_count: int, connection_count: int) -> None:
        self.design_info_label.setText(f"组件: {component_count} | 连接: {connection_count}")

    def closeEvent(self, event) -> None:  # noqa: N802
        if self._allow_close_after_shutdown:
            event.accept()
            return
        if self._shutdown_in_progress:
            event.ignore()
            return
        if not self._confirm_saved_or_continue():
            event.ignore()
            return
        event.ignore()
        self._begin_shutdown()

    def _begin_shutdown(self) -> None:
        if self._shutdown_in_progress:
            return
        self._shutdown_in_progress = True
        self.update_engine_status("Disconnecting")

        worker = self._simulation_worker
        if worker is not None and worker.isRunning():
            worker.request_stop()
            self.output_widget.append_message("关闭程序前正在停止当前仿真。", source="INFO")

        self._shutdown_dialog = QProgressDialog("正在断开 MATLAB 引擎，请稍候...", None, 0, 0, self)
        self._shutdown_dialog.setWindowTitle("正在关闭")
        self._shutdown_dialog.setWindowModality(Qt.ApplicationModal)
        self._shutdown_dialog.setCancelButton(None)
        self._shutdown_dialog.setMinimumDuration(0)
        self._shutdown_dialog.show()
        QApplication.processEvents()

        shutdown_worker = MatlabShutdownWorker(self.engine_manager, self)
        self._shutdown_worker = shutdown_worker
        shutdown_worker.progress.connect(self._on_shutdown_progress)
        shutdown_worker.finished_ok.connect(self._on_shutdown_finished)
        shutdown_worker.failed.connect(self._on_shutdown_failed)
        shutdown_worker.start()

    def _on_shutdown_progress(self, message: str) -> None:
        if self._shutdown_dialog is not None:
            self._shutdown_dialog.setLabelText(message)

    def _on_shutdown_finished(self) -> None:
        self._finish_shutdown("Disconnected")

    def _on_shutdown_failed(self, message: str) -> None:
        if self.output_widget is not None:
            self.output_widget.append_message(f"MATLAB disconnect error: {message}", source="ERROR")
        self._finish_shutdown("Disconnect Error")

    def _finish_shutdown(self, engine_status: str) -> None:
        self.update_engine_status(engine_status)
        if self._shutdown_dialog is not None:
            self._shutdown_dialog.close()
            self._shutdown_dialog = None
        self._allow_close_after_shutdown = True
        self.close()

    def _stub_action(self) -> None:
        self.output_widget.append_message("该功能正在重构中。", source="INFO")

    def _set_simulation_running(self, running: bool) -> None:
        for action in getattr(self, "stop_simulation_actions", []):
            action.setEnabled(running)

    def update_engine_status(self, status: str) -> None:
        if hasattr(self, "engine_status_label"):
            self.engine_status_label.setText(f"MATLAB Engine Status: {status}")
