"""Workspace panel widget with drag-drop and topology editing support."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass

from PyQt5.QtCore import QPointF, Qt, pyqtSignal
from PyQt5.QtGui import QBrush, QColor, QKeySequence, QPainter, QPen, QPixmap
from PyQt5.QtWidgets import (
    QAction,
    QDialog,
    QDialogButtonBox,
    QGraphicsEllipseItem,
    QGraphicsItem,
    QGraphicsLineItem,
    QGraphicsPixmapItem,
    QGraphicsRectItem,
    QGraphicsScene,
    QGraphicsSimpleTextItem,
    QGraphicsView,
    QLabel,
    QMenu,
    QShortcut,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from component_catalog import resolve_icon_path


DEFAULT_COMPONENT_PARAMS: dict[str, dict[str, list[str]]] = {
    "Fiber": {
        "Length": ["20", "km", "光纤长度"],
        "Attenuation": ["0.2", "dB/km", "衰减系数"],
        "Dispersion": ["16.7", "ps/nm/km", "色散参数"],
    },
    "ICR": {
        "Responsivity": ["0.8", "A/W", "探测器响应度"],
        "LO_Power": ["10", "dBm", "本振光功率"],
    },
    "OLTTxDSP": {
        "Modulation": ["16QAM", "", "调制格式"],
        "SymbolRate": ["64", "GBaud", "符号率"],
    },
    "ONUTxDSP": {
        "Modulation": ["16QAM", "", "调制格式"],
        "SymbolRate": ["64", "GBaud", "符号率"],
    },
    "ONURxDSP": {
        "CD_Compensation": ["True", "", "色散补偿"],
        "Adaptive_EQ": ["True", "", "自适应均衡"],
    },
    "OLTRxDSP": {
        "CD_Compensation": ["True", "", "色散补偿"],
        "Adaptive_EQ": ["True", "", "自适应均衡"],
    },
}


@dataclass
class ComponentMeta:
    name: str
    icon_path: str
    params: dict[str, list[str]] | None = None


class ComponentParameterDialog(QDialog):
    def __init__(self, component_name: str, params: dict[str, list[str]], parent=None):
        super().__init__(parent)
        self.setWindowTitle(f"编辑参数 - {component_name}")
        self.resize(620, 420)
        self._params = params

        layout = QVBoxLayout(self)

        self.table = QTableWidget(self)
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["参数名", "值", "单位", "描述"])
        self.table.horizontalHeader().setStretchLastSection(True)

        self._load_params()
        layout.addWidget(self.table)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel, self)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _load_params(self) -> None:
        items = list(self._params.items())
        self.table.setRowCount(len(items))
        for row, (k, v) in enumerate(items):
            value = v[0] if len(v) > 0 else ""
            unit = v[1] if len(v) > 1 else ""
            desc = v[2] if len(v) > 2 else ""

            key_item = QTableWidgetItem(k)
            key_item.setFlags(key_item.flags() & ~Qt.ItemIsEditable)
            self.table.setItem(row, 0, key_item)
            self.table.setItem(row, 1, QTableWidgetItem(str(value)))
            self.table.setItem(row, 2, QTableWidgetItem(str(unit)))
            self.table.setItem(row, 3, QTableWidgetItem(str(desc)))

    def get_params(self) -> dict[str, list[str]]:
        out: dict[str, list[str]] = {}
        for row in range(self.table.rowCount()):
            k = self.table.item(row, 0).text().strip()
            value = self.table.item(row, 1).text().strip() if self.table.item(row, 1) else ""
            unit = self.table.item(row, 2).text().strip() if self.table.item(row, 2) else ""
            desc = self.table.item(row, 3).text().strip() if self.table.item(row, 3) else ""
            out[k] = [value, unit, desc]
        return out


class PortItem(QGraphicsEllipseItem):
    def __init__(self, parent_node: "NodeItem", kind: str, side: str):
        super().__init__(-5, -5, 10, 10, parent_node)
        self.parent_node = parent_node
        self.kind = kind
        self.side = side
        self.setBrush(QColor("#2c78c4") if kind == "out" else QColor("#4fa36b"))
        self.setPen(QPen(QColor("#ffffff"), 1.0))
        self.setZValue(10)


class EdgeItem(QGraphicsLineItem):
    def __init__(self, source: PortItem, target: PortItem):
        super().__init__()
        self.source = source
        self.target = target
        self._pen = QPen(QColor("#3c4d63"), 2.0)
        self.setPen(self._pen)
        self.setZValue(1)
        self.setFlag(QGraphicsItem.ItemIsSelectable, True)
        self.update_position()

    def update_position(self) -> None:
        src = self.source.scenePos()
        dst = self.target.scenePos()
        self.setLine(src.x(), src.y(), dst.x(), dst.y())

    def paint(self, painter, option, widget=None):  # noqa: N802
        super().paint(painter, option, widget)
        line = self.line()
        dx = line.x2() - line.x1()
        dy = line.y2() - line.y1()
        length = math.hypot(dx, dy)
        if length < 1e-6:
            return

        ux = dx / length
        uy = dy / length

        arrow_len = 9.0
        arrow_w = 4.0
        tip_x = line.x2()
        tip_y = line.y2()

        base_x = tip_x - ux * arrow_len
        base_y = tip_y - uy * arrow_len
        left_x = base_x - uy * arrow_w
        left_y = base_y + ux * arrow_w
        right_x = base_x + uy * arrow_w
        right_y = base_y - ux * arrow_w

        painter.setPen(Qt.NoPen)
        painter.setBrush(self._pen.color())
        painter.drawPolygon(
            QPointF(tip_x, tip_y),
            QPointF(left_x, left_y),
            QPointF(right_x, right_y),
        )


class NodeItem(QGraphicsRectItem):
    WIDTH = 84
    HEIGHT = 96

    def __init__(self, node_id: int, meta: ComponentMeta):
        super().__init__(0, 0, self.WIDTH, self.HEIGHT)
        self.node_id = node_id
        self.meta = meta
        self.edges: list[EdgeItem] = []

        self.setPen(QPen(Qt.NoPen))
        self.setBrush(QBrush(Qt.NoBrush))
        self.setFlags(
            QGraphicsItem.ItemIsMovable
            | QGraphicsItem.ItemIsSelectable
            | QGraphicsItem.ItemSendsGeometryChanges
        )

        pix = QPixmap(meta.icon_path)
        if not pix.isNull():
            icon_pix = pix.scaled(64, 64, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            icon_item = QGraphicsPixmapItem(icon_pix, self)
            icon_item.setPos((self.WIDTH - icon_pix.width()) / 2, 6)

        self.name_item = QGraphicsSimpleTextItem(meta.name, self)
        font = self.name_item.font()
        font.setPointSize(8)
        self.name_item.setFont(font)
        self.name_item.setBrush(QColor("#24384f"))
        self.name_item.setPos((self.WIDTH - self.name_item.boundingRect().width()) / 2, 74)

        self.highlight_rect = QGraphicsRectItem(2, 2, self.WIDTH - 4, self.HEIGHT - 4, self)
        self.highlight_rect.setPen(QPen(QColor("#3d8bfd"), 1.5, Qt.DashLine))
        self.highlight_rect.setBrush(QBrush(Qt.NoBrush))
        self.highlight_rect.setVisible(False)
        self.highlight_rect.setZValue(2)

        self.left_port = PortItem(self, "in", "left")
        self.right_port = PortItem(self, "out", "right")
        self.top_port = PortItem(self, "in", "top")
        self.bottom_port = PortItem(self, "out", "bottom")

        self.left_port.setPos(0, self.HEIGHT / 2)
        self.right_port.setPos(self.WIDTH, self.HEIGHT / 2)
        self.top_port.setPos(self.WIDTH / 2, 0)
        self.bottom_port.setPos(self.WIDTH / 2, self.HEIGHT)

    def itemChange(self, change, value):  # noqa: N802
        if change == QGraphicsItem.ItemPositionHasChanged:
            for edge in self.edges:
                edge.update_position()
        elif change == QGraphicsItem.ItemSelectedHasChanged:
            self.highlight_rect.setVisible(bool(value))
        return super().itemChange(change, value)

    def to_dict(self) -> dict:
        pos = self.pos()
        return {
            "id": self.node_id,
            "name": self.meta.name,
            "icon_path": self.meta.icon_path,
            "x": pos.x(),
            "y": pos.y(),
            "params": self.meta.params or {},
        }


class TopologyScene(QGraphicsScene):
    topology_changed = pyqtSignal(int, int)
    node_double_clicked = pyqtSignal(object)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setSceneRect(0, 0, 3000, 2000)
        self._next_id = 1
        self._drag_port: PortItem | None = None
        self._preview_line: QGraphicsLineItem | None = None

    def dragMoveEvent(self, event) -> None:  # noqa: N802
        if event.mimeData().hasFormat("application/x-optical-component"):
            event.acceptProposedAction()
        else:
            super().dragMoveEvent(event)

    def dropEvent(self, event) -> None:  # noqa: N802
        mime = event.mimeData()
        if not mime.hasFormat("application/x-optical-component"):
            super().dropEvent(event)
            return

        comp_name = bytes(mime.data("application/x-optical-component")).decode("utf-8")
        icon_path = bytes(mime.data("application/x-optical-icon")).decode("utf-8")
        self.create_node(comp_name, icon_path, event.scenePos())
        event.acceptProposedAction()

    def mousePressEvent(self, event) -> None:  # noqa: N802
        if event.button() == Qt.LeftButton:
            port = self._port_at(event.scenePos())
            if port is not None and port.kind == "out":
                self._start_port_drag(port)
                event.accept()
                return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:  # noqa: N802
        if self._drag_port is not None and self._preview_line is not None:
            src = self._drag_port.scenePos()
            dst = event.scenePos()
            self._preview_line.setLine(src.x(), src.y(), dst.x(), dst.y())
            event.accept()
            return
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event) -> None:  # noqa: N802
        if self._drag_port is not None and event.button() == Qt.LeftButton:
            target_port = self._port_at(event.scenePos())
            self._finish_port_drag(target_port)
            event.accept()
            return
        super().mouseReleaseEvent(event)

    def mouseDoubleClickEvent(self, event) -> None:  # noqa: N802
        for item in self.items(event.scenePos()):
            if isinstance(item, NodeItem):
                self.node_double_clicked.emit(item)
                event.accept()
                return
            if isinstance(item, PortItem):
                self.node_double_clicked.emit(item.parent_node)
                event.accept()
                return
        super().mouseDoubleClickEvent(event)

    def _port_at(self, scene_pos: QPointF) -> PortItem | None:
        for item in self.items(scene_pos):
            if isinstance(item, PortItem):
                return item
        return None

    def _start_port_drag(self, port: PortItem) -> None:
        self._drag_port = port
        self._preview_line = QGraphicsLineItem()
        self._preview_line.setPen(QPen(QColor("#3d8bfd"), 1.6, Qt.DashLine))
        self._preview_line.setZValue(0)
        src = port.scenePos()
        self._preview_line.setLine(src.x(), src.y(), src.x(), src.y())
        self.addItem(self._preview_line)

    def _finish_port_drag(self, target_port: PortItem | None) -> None:
        source_port = self._drag_port

        if self._preview_line is not None:
            self.removeItem(self._preview_line)
        self._preview_line = None
        self._drag_port = None

        if source_port is None or target_port is None:
            return
        if source_port.parent_node is target_port.parent_node:
            return
        if source_port.kind != "out" or target_port.kind != "in":
            return

        edge = EdgeItem(source_port, target_port)
        self.addItem(edge)
        source_port.parent_node.edges.append(edge)
        target_port.parent_node.edges.append(edge)
        self._emit_counts()

    def create_node(self, name: str, icon_path: str, pos: QPointF) -> NodeItem:
        resolved_icon = resolve_icon_path(name, icon_path)
        default_params = self._default_params(name)
        node = NodeItem(
            self._next_id,
            ComponentMeta(name=name, icon_path=resolved_icon, params=default_params),
        )
        self._next_id += 1
        node.setPos(pos)
        self.addItem(node)
        self._emit_counts()
        return node

    @staticmethod
    def _default_params(name: str) -> dict[str, list[str]]:
        name_lower = name.lower()
        if "txdsp" in name_lower:
            return dict(DEFAULT_COMPONENT_PARAMS.get("OLTTxDSP", {}))
        if "rxdsp" in name_lower:
            return dict(DEFAULT_COMPONENT_PARAMS.get("ONURxDSP", {}))
        for key, v in DEFAULT_COMPONENT_PARAMS.items():
            if key.lower() in name_lower:
                return dict(v)
        return {"Enabled": ["True", "", "是否启用"], "Comment": ["", "", "备注"]}

    def selected_nodes(self) -> list[NodeItem]:
        return [i for i in self.selectedItems() if isinstance(i, NodeItem)]

    def delete_selected(self) -> None:
        for item in list(self.selectedItems()):
            if isinstance(item, EdgeItem):
                self._remove_edge(item)
            elif isinstance(item, NodeItem):
                for edge in list(item.edges):
                    self._remove_edge(edge)
                self.removeItem(item)
        self._emit_counts()

    def delete_at(self, scene_pos: QPointF) -> None:
        for item in self.items(scene_pos):
            if isinstance(item, PortItem):
                item = item.parent_node
            if isinstance(item, NodeItem):
                item.setSelected(True)
                self.delete_selected()
                return
            if isinstance(item, EdgeItem):
                item.setSelected(True)
                self.delete_selected()
                return

    def _remove_edge(self, edge: EdgeItem) -> None:
        if edge in edge.source.parent_node.edges:
            edge.source.parent_node.edges.remove(edge)
        if edge in edge.target.parent_node.edges:
            edge.target.parent_node.edges.remove(edge)
        self.removeItem(edge)

    def serialize(self) -> dict:
        nodes = [item.to_dict() for item in self.items() if isinstance(item, NodeItem)]
        edges = []
        for item in self.items():
            if isinstance(item, EdgeItem):
                edges.append(
                    {
                        "source_id": item.source.parent_node.node_id,
                        "source_side": item.source.side,
                        "target_id": item.target.parent_node.node_id,
                        "target_side": item.target.side,
                    }
                )
        return {"nodes": nodes, "edges": edges}

    def deserialize(self, data: dict) -> None:
        self.clear()

        id_to_node: dict[int, NodeItem] = {}
        max_id = 0

        nodes_data = data.get("nodes", [])
        edges_data = data.get("edges", [])
        has_xy = all(("x" in n and "y" in n) for n in nodes_data)

        layered_pos: dict[int, tuple[float, float]] = {}
        if not has_xy:
            adjacency: dict[int, list[int]] = {}
            indegree: dict[int, int] = {}
            for n in nodes_data:
                nid = int(n["id"])
                adjacency[nid] = []
                indegree[nid] = 0
            for e in edges_data:
                s_id = int(e["source_id"])
                t_id = int(e["target_id"])
                if s_id in adjacency and t_id in adjacency:
                    adjacency[s_id].append(t_id)
                    indegree[t_id] += 1

            from collections import deque

            q = deque([nid for nid, d in indegree.items() if d == 0])
            level_map: dict[int, int] = {nid: 0 for nid in indegree}
            while q:
                u = q.popleft()
                for v in adjacency.get(u, []):
                    level_map[v] = max(level_map.get(v, 0), level_map.get(u, 0) + 1)
                    indegree[v] -= 1
                    if indegree[v] == 0:
                        q.append(v)

            level_groups: dict[int, list[int]] = {}
            for nid in level_map:
                lvl = level_map[nid]
                level_groups.setdefault(lvl, []).append(nid)

            for lvl, ids in sorted(level_groups.items()):
                for row, nid in enumerate(ids):
                    layered_pos[nid] = (120.0 + lvl * 190.0, 120.0 + row * 140.0)

        for idx, node_data in enumerate(nodes_data):
            node_id = int(node_data["id"])
            name = node_data.get("name", f"Node{node_id}")
            icon_path = resolve_icon_path(name, node_data.get("icon_path", ""))
            params = node_data.get("params") or self._default_params(name)
            node = NodeItem(node_id, ComponentMeta(name=name, icon_path=icon_path, params=params))

            if has_xy:
                x = float(node_data["x"])
                y = float(node_data["y"])
            else:
                x, y = layered_pos.get(node_id, (120.0 + (idx % 6) * 150.0, 120.0 + (idx // 6) * 130.0))

            node.setPos(QPointF(x, y))
            self.addItem(node)
            id_to_node[node_id] = node
            max_id = max(max_id, node_id)

        for edge_data in edges_data:
            src_node = id_to_node.get(int(edge_data["source_id"]))
            tgt_node = id_to_node.get(int(edge_data["target_id"]))
            if not src_node or not tgt_node:
                continue
            src_port = self._get_port(src_node, edge_data.get("source_side", "right"))
            tgt_port = self._get_port(tgt_node, edge_data.get("target_side", "left"))
            edge = EdgeItem(src_port, tgt_port)
            self.addItem(edge)
            src_node.edges.append(edge)
            tgt_node.edges.append(edge)

        self._next_id = max_id + 1
        self._emit_counts()

    @staticmethod
    def _get_port(node: NodeItem, side: str) -> PortItem:
        mapping = {
            "left": node.left_port,
            "right": node.right_port,
            "top": node.top_port,
            "bottom": node.bottom_port,
        }
        return mapping.get(side, node.right_port)

    def _emit_counts(self) -> None:
        component_count = sum(1 for item in self.items() if isinstance(item, NodeItem))
        connection_count = sum(1 for item in self.items() if isinstance(item, EdgeItem))
        self.topology_changed.emit(component_count, connection_count)


class WorkspaceView(QGraphicsView):
    delete_requested = pyqtSignal()
    copy_requested = pyqtSignal()
    paste_requested = pyqtSignal()

    def __init__(self, scene: TopologyScene, parent=None):
        super().__init__(scene, parent)
        self.setRenderHint(QPainter.Antialiasing)
        self.setAcceptDrops(True)
        self.setDragMode(QGraphicsView.RubberBandDrag)
        self.setViewportUpdateMode(QGraphicsView.BoundingRectViewportUpdate)
        self.setBackgroundBrush(QColor("#fbfcff"))

    def dragEnterEvent(self, event) -> None:  # noqa: N802
        if event.mimeData().hasFormat("application/x-optical-component"):
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def keyPressEvent(self, event) -> None:  # noqa: N802
        if event.key() == Qt.Key_Delete:
            self.delete_requested.emit()
            event.accept()
            return
        if event.matches(QKeySequence.Copy):
            self.copy_requested.emit()
            event.accept()
            return
        if event.matches(QKeySequence.Paste):
            self.paste_requested.emit()
            event.accept()
            return
        super().keyPressEvent(event)

    def contextMenuEvent(self, event) -> None:  # noqa: N802
        scene = self.scene()
        if not isinstance(scene, TopologyScene):
            return super().contextMenuEvent(event)

        menu = QMenu(self)
        delete_action = QAction("删除", self)
        delete_action.triggered.connect(lambda: self._delete_by_context(scene, event))
        menu.addAction(delete_action)
        menu.exec_(event.globalPos())

    def _delete_by_context(self, scene: TopologyScene, event) -> None:
        if scene.selectedItems():
            scene.delete_selected()
        else:
            scene.delete_at(self.mapToScene(event.pos()))


class WorkspacePanel(QWidget):
    """Middle workspace area for topology editing."""

    topology_changed = pyqtSignal(int, int)
    node_parameter_updated = pyqtSignal(int, dict)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._clipboard_nodes: list[dict] = []
        self._setup_ui()
        self._setup_shortcuts()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(6)

        title = QLabel("工作区")
        title.setObjectName("panelTitle")

        hint = QLabel("拖拽组件到工作区；双击组件编辑参数；支持连线、框选、复制粘贴、删除与缩放。")
        hint.setObjectName("panelBody")
        hint.setAlignment(Qt.AlignLeft)

        self.scene = TopologyScene(self)
        self.scene.topology_changed.connect(self.topology_changed.emit)
        self.scene.node_double_clicked.connect(self._edit_node_parameters)

        self.view = WorkspaceView(self.scene, self)
        self.view.delete_requested.connect(self.delete_selected)
        self.view.copy_requested.connect(self.copy_selected)
        self.view.paste_requested.connect(self.paste_selected)

        layout.addWidget(title)
        layout.addWidget(hint)
        layout.addWidget(self.view, 1)

    def _setup_shortcuts(self) -> None:
        self._sc_delete = QShortcut(QKeySequence.Delete, self)
        self._sc_delete.setContext(Qt.WidgetWithChildrenShortcut)
        self._sc_delete.activated.connect(self.delete_selected)

        self._sc_copy = QShortcut(QKeySequence.Copy, self)
        self._sc_copy.setContext(Qt.WidgetWithChildrenShortcut)
        self._sc_copy.activated.connect(self.copy_selected)

        self._sc_paste = QShortcut(QKeySequence.Paste, self)
        self._sc_paste.setContext(Qt.WidgetWithChildrenShortcut)
        self._sc_paste.activated.connect(self.paste_selected)

    def _edit_node_parameters(self, node: NodeItem) -> None:
        params = node.meta.params or self.scene._default_params(node.meta.name)
        dialog = ComponentParameterDialog(node.meta.name, params, parent=self)
        if dialog.exec_() == QDialog.Accepted:
            node.meta.params = dialog.get_params()
            self.node_parameter_updated.emit(node.node_id, node.meta.params)

    def delete_selected(self) -> None:
        self.scene.delete_selected()

    def copy_selected(self) -> None:
        nodes = self.scene.selected_nodes()
        if not nodes:
            self._clipboard_nodes = []
            return

        self._clipboard_nodes = []
        base = nodes[0].pos()
        for node in nodes:
            p = node.pos()
            self._clipboard_nodes.append(
                {
                    "name": node.meta.name,
                    "icon_path": node.meta.icon_path,
                    "params": node.meta.params or {},
                    "dx": p.x() - base.x(),
                    "dy": p.y() - base.y(),
                }
            )

    def paste_selected(self) -> None:
        if not self._clipboard_nodes:
            return

        for item in self.scene.selectedItems():
            item.setSelected(False)

        center = self.view.mapToScene(self.view.viewport().rect().center())
        for node_data in self._clipboard_nodes:
            pos = QPointF(center.x() + node_data["dx"] + 25, center.y() + node_data["dy"] + 25)
            node = self.scene.create_node(node_data["name"], node_data["icon_path"], pos)
            node.meta.params = dict(node_data.get("params", {}))
            node.setSelected(True)

    def zoom_in(self) -> None:
        self.view.scale(1.15, 1.15)

    def zoom_out(self) -> None:
        self.view.scale(1 / 1.15, 1 / 1.15)

    def reset_zoom(self) -> None:
        self.view.resetTransform()

    def save_topology(self, file_path: str) -> None:
        data = self.scene.serialize()
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load_topology(self, file_path: str) -> None:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        self.scene.deserialize(data)

    def clear_topology(self) -> None:
        self.scene.deserialize({"nodes": [], "edges": []})
