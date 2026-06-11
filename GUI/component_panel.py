"""Component panel widget."""

from __future__ import annotations

from pathlib import Path

from PyQt5.QtCore import QMimeData, QPoint, QSize, Qt, pyqtSignal
from PyQt5.QtGui import QDrag, QIcon
from PyQt5.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QVBoxLayout,
    QWidget,
)

from component_catalog import COMPONENT_GROUPS, resolve_icon_path


class DraggableComponentList(QListWidget):
    def startDrag(self, supportedActions) -> None:  # noqa: N802 (Qt API style)
        item = self.currentItem()
        if item is None:
            return

        component_name = item.data(Qt.UserRole)
        icon_path = item.data(Qt.UserRole + 1)

        mime = QMimeData()
        mime.setData("application/x-optical-component", component_name.encode("utf-8"))
        mime.setText(component_name)
        mime.setData("application/x-optical-icon", str(icon_path).encode("utf-8"))

        drag = QDrag(self)
        drag.setMimeData(mime)
        if not item.icon().isNull():
            drag.setPixmap(item.icon().pixmap(52, 52))
            drag.setHotSpot(QPoint(26, 26))
        drag.exec_(Qt.CopyAction)


class ComponentPanel(QWidget):
    """Top component library panel with icon and drag support."""

    component_selected = pyqtSignal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._list_widgets: list[QListWidget] = []
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(6)

        title = QLabel("组件库")
        title.setObjectName("panelTitle")
        title.setAlignment(Qt.AlignCenter)
        title.setStyleSheet("font-size: 12pt; font-weight: 700;")
        layout.addWidget(title)

        row = QHBoxLayout()
        row.setSpacing(8)

        for group_name, components in COMPONENT_GROUPS.items():
            group_widget, list_widget = self._create_group(group_name, components)
            self._list_widgets.append(list_widget)
            row.addWidget(group_widget, 1)
            list_widget.itemClicked.connect(
                lambda item, _lw=list_widget: self._on_component_clicked(item, _lw)
            )

        layout.addLayout(row, 1)

    def _create_group(self, title: str, components: list[tuple[str, str]]):
        container = QWidget(self)
        c_layout = QVBoxLayout(container)
        c_layout.setContentsMargins(0, 0, 0, 0)
        c_layout.setSpacing(4)

        label = QLabel(title)
        label.setObjectName("panelBody")

        list_widget = DraggableComponentList(container)
        list_widget.setAlternatingRowColors(True)
        list_widget.setViewMode(QListWidget.IconMode)
        list_widget.setWrapping(True)
        list_widget.setResizeMode(QListWidget.Adjust)
        list_widget.setIconSize(QSize(42, 42))
        list_widget.setDragEnabled(True)
        list_widget.setSpacing(6)

        for comp_name, _icon_name in components:
            icon_path = resolve_icon_path(comp_name)
            item = QListWidgetItem(comp_name)
            if icon_path and Path(icon_path).exists():
                item.setIcon(QIcon(icon_path))
            item.setData(Qt.UserRole, comp_name)
            item.setData(Qt.UserRole + 1, str(icon_path))
            item.setTextAlignment(Qt.AlignCenter)
            list_widget.addItem(item)

        c_layout.addWidget(label)
        c_layout.addWidget(list_widget, 1)
        return container, list_widget

    def _on_component_clicked(
        self, item: QListWidgetItem, source_list: QListWidget
    ) -> None:
        for list_widget in self._list_widgets:
            if list_widget is source_list:
                continue
            list_widget.clearSelection()
            list_widget.setCurrentItem(None)
        self.component_selected.emit(item.data(Qt.UserRole))
