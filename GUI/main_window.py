"""Main application window."""

from __future__ import annotations

from PyQt5.QtCore import QThread, Qt, pyqtSignal
from PyQt5.QtWidgets import QAction, QFileDialog, QLabel, QMainWindow, QSplitter, QToolBar, QVBoxLayout, QWidget

from component_panel import ComponentPanel
from matlab_engine_manager import MatlabEngineManager
from matlab_topology_runner import MatlabTopologyRunner
from output_widget import OutputWidget
from simulation_result_viewer import AnalyzerPlotDialog, SimulationResultDialog
from workspace_panel import WorkspacePanel
from topology_executor import TopologyCycleError, TopologyExecutor


class MatlabTopologyWorker(QThread):
    log_message = pyqtSignal(str, str)
    finished_ok = pyqtSignal(object)
    failed = pyqtSignal(str)

    def __init__(self, engine_manager: MatlabEngineManager, topology: dict, parent=None):
        super().__init__(parent)
        self.engine_manager = engine_manager
        self.topology = topology

    def run(self) -> None:
        try:
            runner = MatlabTopologyRunner(
                self.engine_manager,
                log=lambda message, source="INFO": self.log_message.emit(message, source),
            )
            outputs = runner.run(self.topology)
            self.finished_ok.emit(outputs)
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
        self._latest_topology = None
        self._latest_outputs = {}
        self._analysis_windows = []
        self.setWindowTitle("多维复用超高速光网络仿真平台")
        self.resize(1280, 820)

        self._setup_central(engine_manager)
        self._create_menu_bar()
        self._create_tool_bars()
        self._create_status_area(initial_engine_status)
        self._connect_signals()

    def _setup_central(self, engine_manager: MatlabEngineManager) -> None:
        central = QWidget(self)
        root_layout = QVBoxLayout(central)
        root_layout.setContentsMargins(6, 6, 6, 6)
        root_layout.setSpacing(6)

        title_label = QLabel("多维复用超高速光网络仿真平台")
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
        file_menu.addAction(self._make_action("新建", "Ctrl+N", self._new_topology))
        file_menu.addAction(self._make_action("打开拓扑", "Ctrl+O", self._open_topology))
        file_menu.addAction(self._make_action("保存拓扑", "Ctrl+S", self._save_topology))
        file_menu.addSeparator()
        file_menu.addAction(self._make_action("退出", "Ctrl+Q", self.close))

        edit_menu = menu.addMenu("编辑")
        edit_menu.addAction(self._make_action("删除", "Delete", self.workspace_panel.delete_selected))
        edit_menu.addAction(self._make_action("复制", "Ctrl+C", self.workspace_panel.copy_selected))
        edit_menu.addAction(self._make_action("粘贴", "Ctrl+V", self.workspace_panel.paste_selected))

        view_menu = menu.addMenu("视图")
        view_menu.addAction(self._make_action("放大", "Ctrl++", self.workspace_panel.zoom_in))
        view_menu.addAction(self._make_action("缩小", "Ctrl+-", self.workspace_panel.zoom_out))
        view_menu.addAction(self._make_action("重置缩放", "Ctrl+0", self.workspace_panel.reset_zoom))

        sim_menu = menu.addMenu("仿真")
        sim_menu.addAction(self._make_action("拓扑仿真", "F5", self._run_topology_simulation))
        sim_menu.addAction(self._make_action("仿真结果", None, self._show_simulation_results))
        sim_menu.addAction(self._make_action("停止仿真", "Shift+F5", self._stub_action))

    def _create_tool_bars(self) -> None:
        file_tb = QToolBar("文件", self)
        file_tb.addAction(self._make_action("打开", None, self._open_topology))
        file_tb.addAction(self._make_action("保存", None, self._save_topology))
        self.addToolBar(file_tb)

        edit_tb = QToolBar("编辑", self)
        edit_tb.addAction(self._make_action("删除", None, self.workspace_panel.delete_selected))
        edit_tb.addAction(self._make_action("复制", None, self.workspace_panel.copy_selected))
        edit_tb.addAction(self._make_action("粘贴", None, self.workspace_panel.paste_selected))
        self.addToolBar(edit_tb)

        view_tb = QToolBar("视图", self)
        view_tb.addAction(self._make_action("放大", None, self.workspace_panel.zoom_in))
        view_tb.addAction(self._make_action("缩小", None, self.workspace_panel.zoom_out))
        view_tb.addAction(self._make_action("重置", None, self.workspace_panel.reset_zoom))
        self.addToolBar(view_tb)

        sim_tb = QToolBar("仿真", self)
        sim_tb.addAction(self._make_action("运行", None, self._run_topology_simulation))
        sim_tb.addAction(self._make_action("仿真结果", None, self._show_simulation_results))
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
        self.workspace_panel.analyzer_open_requested.connect(self._show_analyzer_for_node)
        self.output_widget.log_python_output("GUI initialized.")

    def _make_action(self, text: str, shortcut: str | None, callback) -> QAction:
        action = QAction(text, self)
        if shortcut:
            action.setShortcut(shortcut)
        action.triggered.connect(callback)
        return action

    def _new_topology(self) -> None:
        self.workspace_panel.clear_topology()
        self.status_label.setText("新建拓扑")

    def _open_topology(self) -> None:
        file_path, _ = QFileDialog.getOpenFileName(self, "打开拓扑文件", "", "JSON (*.json)")
        if file_path:
            self.workspace_panel.load_topology(file_path)
            self.status_label.setText("拓扑已加载")
            self.output_widget.append_message(f"Topology loaded: {file_path}", source="INFO")

    def _save_topology(self) -> None:
        file_path, _ = QFileDialog.getSaveFileName(self, "保存拓扑文件", "topology.json", "JSON (*.json)")
        if file_path:
            self.workspace_panel.save_topology(file_path)
            self.status_label.setText("拓扑已保存")
            self.output_widget.append_message(f"Topology saved: {file_path}", source="INFO")

    def _run_topology_test(self) -> None:
        topology = self.workspace_panel.scene.serialize()
        try:
            executor = TopologyExecutor(topology)
            levels = executor.topological_levels()
            self.output_widget.append_message("Topology execution plan:", source="INFO")
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
                f"Topology run finished. Nodes executed: {len(outputs)}",
                source="MATLAB",
            )
            self.status_label.setText("拓扑运行完成")
        except TopologyCycleError as exc:
            self.output_widget.append_message(f"Topology error: {exc}", source="ERROR")
            self.status_label.setText("拓扑存在环")
        except Exception as exc:
            self.output_widget.append_message(f"Run error: {exc}", source="ERROR")
            self.status_label.setText("运行失败")

    def _run_topology_simulation(self) -> None:
        if self._simulation_worker is not None and self._simulation_worker.isRunning():
            self.output_widget.append_message("拓扑仿真正在运行中。", source="INFO")
            return

        topology = self.workspace_panel.scene.serialize()
        self._latest_topology = topology
        self.status_label.setText("正在运行拓扑仿真")

        worker = MatlabTopologyWorker(self.engine_manager, topology, self)
        self._simulation_worker = worker
        worker.log_message.connect(lambda message, source: self.output_widget.append_message(message, source=source))
        worker.finished_ok.connect(self._on_topology_simulation_finished)
        worker.failed.connect(self._on_topology_simulation_failed)
        worker.start()

    def _on_topology_simulation_finished(self, outputs: dict) -> None:
        self._latest_outputs = outputs or {}
        self.status_label.setText("拓扑仿真完成")
        self.output_widget.append_message("拓扑仿真完成。双击光/电分析仪组件可查看对应结果。", source="INFO")

    def _on_topology_simulation_failed(self, message: str) -> None:
        self.output_widget.append_message(f"MATLAB run error: {message}", source="ERROR")
        self.status_label.setText("拓扑仿真失败")

    def _show_analyzer_for_node(self, node_id: int, name: str) -> None:
        normalized = "".join(ch.lower() for ch in name if ch.isalnum())
        workspace = self._node_workspace(node_id)
        if not workspace:
            self.output_widget.append_message(
                f"{name} 暂无可显示结果，请先运行拓扑仿真并确保该分析仪已连接信号。",
                source="INFO",
            )
            return
        if workspace.get("Status") != "called" or workspace.get("AnalyzerSignal") is None:
            waiting_for = workspace.get("WaitingFor")
            error = workspace.get("Error")
            detail = f"等待: {waiting_for}" if waiting_for else (f"错误: {error}" if error else "无有效分析仪信号")
            self.output_widget.append_message(
                f"{name} 暂无可显示结果，{detail}。",
                source="INFO",
            )
            return

        if "oanalyzer" in normalized:
            dialog = AnalyzerPlotDialog.optical(name, workspace, self)
        elif "eanalyzer" in normalized:
            dialog = AnalyzerPlotDialog.electrical(name, workspace, self)
        else:
            return

        self._analysis_windows.append(dialog)
        dialog.show()

    def _show_simulation_results(self) -> None:
        rows = []
        topology = self._latest_topology or self.workspace_panel.scene.serialize()
        node_names = {int(n.get("id")): str(n.get("name", "")) for n in topology.get("nodes", [])}

        for node_id, outputs in (self._latest_outputs or {}).items():
            workspace = self._workspace_from_outputs(outputs)
            if workspace and ("SNR" in workspace or "BER" in workspace):
                rows.append(
                    {
                        "node_id": node_id,
                        "name": node_names.get(int(node_id), ""),
                        "SNR": workspace.get("SNR"),
                        "BER": workspace.get("BER"),
                    }
                )

        dialog = SimulationResultDialog(rows, self)
        self._analysis_windows.append(dialog)
        dialog.show()

    def _node_workspace(self, node_id: int) -> dict:
        outputs = (self._latest_outputs or {}).get(node_id)
        return self._workspace_from_outputs(outputs)

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

    def _stub_action(self) -> None:
        self.output_widget.append_message("该功能正在重构中。", source="INFO")

    def update_engine_status(self, status: str) -> None:
        if hasattr(self, "engine_status_label"):
            self.engine_status_label.setText(f"MATLAB Engine Status: {status}")
