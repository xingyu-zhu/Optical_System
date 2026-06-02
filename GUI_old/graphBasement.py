import math

from PyQt6.QtCore import Qt, QRectF, QPointF
from PyQt6.QtGui import QBrush, QColor, QPen, QPainter, QFontMetrics, QPainterPath, QPainterPathStroker, QTransform, \
    QPolygonF, QPixmap
from PyQt6.QtWidgets import QGraphicsEllipseItem, QGraphicsItem, QStyleOptionGraphicsItem, QGraphicsPathItem


class PortGraphicsItem(QGraphicsEllipseItem):
    PORT_RADIUS = 5
    PORT_HOVER_RADIUS = 7

    def __init__(self, x, y, port_type, port_loc, component_id, parent=None):
        radius = self.PORT_RADIUS
        super().__init__(-radius, -radius, radius * 2, radius * 2, parent)

        # port_type有两种类型 'in' 或 'out', 用于标识输入和输出端口，避免连接问题
        self.port_type = port_type
        # port_loc有四种类型 'top', 'bottom', 'left' 和 'right', 用于标注port相对组件的位置及绘图
        self.port_loc = port_loc
        self.component_id = component_id
        self.setPos(x, y)

        self.normal_brush = QBrush(QColor(255, 255, 255))
        self.normal_pen = QPen(Qt.GlobalColor.black, 1)

        if port_type == 'in':
            self.hover_brush = QBrush(QColor(100, 255, 100))
            self.hover_pen = QPen(Qt.GlobalColor.darkGreen, 2)
        elif port_type == 'out':
            self.hover_brush = QBrush(QColor(255, 100, 100))
            self.hover_pen = QPen(Qt.GlobalColor.darkRed, 2)

        self.setBrush(self.normal_brush)
        self.setPen(self.normal_pen)

        self.setAcceptHoverEvents(True)
        self.setAcceptedMouseButtons(Qt.MouseButton.LeftButton)
        self.setFlag(QGraphicsItem.GraphicsItemFlag.ItemIsSelectable, False)

        self.is_hovered = False

    def hoverEnterEvent(self, event):
        self.is_hovered = True
        self.setBrush(self.hover_brush)
        self.setPen(self.hover_pen)
        super().hoverEnterEvent(event)

    def hoverLeaveEvent(self, event):
        self.is_hovered = False
        self.setBrush(self.normal_brush)
        self.setPen(self.normal_pen)
        super().hoverLeaveEvent(event)

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            if self.parentItem():
                self.parentItem().port_clicked(self)
                event.accept()
        else:
            super().mousePressEvent(event)

class ComponentGraphicsItem(QGraphicsItem):

    WIDTH = 70
    HEIGHT = 70
    BORDER_RADIUS = 0

    def __init__(self, component, parent=None):
        super().__init__(parent)

        self.component = component
        self.width = self.WIDTH
        self.height = self.HEIGHT

        self.normal_color = QColor(255, 255, 255)
        self.selected_color = QColor(173, 216, 230)
        self.border_color = QColor(70, 130, 180)
        self.text_color = Qt.GlobalColor.black

        self.is_selected = False
        self.is_hovered = False

        self.setPos(component.x, component.y)

        self.setFlags(
            QGraphicsItem.GraphicsItemFlag.ItemIsMovable |
            QGraphicsItem.GraphicsItemFlag.ItemIsSelectable |
            QGraphicsItem.GraphicsItemFlag.ItemSendsGeometryChanges
        )

        self.create_ports()

        self.connections = []

    def create_ports(self):
        self.top_port = PortGraphicsItem(
            x=self.width / 2 + PortGraphicsItem.PORT_RADIUS,
            y=-PortGraphicsItem.PORT_RADIUS,
            port_type='in',
            port_loc='top',
            component_id=self.component.id,
            parent=self
        )

        self.bottom_port = PortGraphicsItem(
            x=self.width / 2 + PortGraphicsItem.PORT_RADIUS,
            y=self.height + PortGraphicsItem.PORT_RADIUS,
            port_type='out',
            port_loc='bottom',
            component_id=self.component.id,
            parent=self
        )

        self.left_port = PortGraphicsItem(
            x=-PortGraphicsItem.PORT_RADIUS,
            y=self.height / 2,
            port_type='in',
            port_loc='left',
            component_id=self.component.id,
            parent=self
        )

        self.right_port = PortGraphicsItem(
            x=self.width + PortGraphicsItem.PORT_RADIUS,
            y=self.height / 2,
            port_type='out',
            port_loc='right',
            component_id=self.component.id,
            parent=self
        )

    def boundingRect(self):
        """返回边界矩形"""
        return QRectF(0, 0, self.width, self.height).adjusted(-10, -5, 10, 5)

    def paint(self, painter: QPainter, option: QStyleOptionGraphicsItem, widget=None):
        """绘制组件"""
        icon_size = 68
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # 根据状态选择颜色
        if self.is_selected:
            fill_color = self.selected_color
            border_width = 2
        else:
            fill_color = self.normal_color
            border_width = 1

        if self.is_hovered:
            border_color = QColor(30, 144, 255)  # 道奇蓝
        else:
            border_color = self.border_color

        # 绘制背景
        painter.setBrush(QBrush(fill_color))
        painter.setPen(QPen(border_color, border_width))
        painter.drawRoundedRect(0, 0, self.width, self.height,
                                self.BORDER_RADIUS, self.BORDER_RADIUS)

        # 绘制阴影效果
        if self.is_selected:
            painter.setPen(QPen(QColor(30, 144, 255, 100), 4))
            painter.drawRoundedRect(2, 2, self.width - 4, self.height - 4,
                                    self.BORDER_RADIUS, self.BORDER_RADIUS)

        if self.component.icon_path is not None:
            pixmap = QPixmap(self.component.icon_path)
            if not pixmap.isNull():
                pixmap = pixmap.scaled(
                    icon_size, icon_size,
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation
                )
                icon_x = pixmap.width()
                icon_y = pixmap.height()
                source = QRectF(0, 0, icon_x, icon_y)

                painter.drawPixmap(source, pixmap, source)

            else:
                painter.setPen(QPen(self.text_color))
                font = painter.font()
                font.setBold(True)
                font.setPointSize(10)
                painter.setFont(font)

                # 计算文本位置
                font_metrics = QFontMetrics(font)
                name_text = font_metrics.elidedText(self.component.name,
                                                    Qt.TextElideMode.ElideRight,
                                                    self.width - 20)

                painter.drawText(QRectF(10, 15, self.width - 20, 20),
                                 Qt.AlignmentFlag.AlignCenter, name_text)

                # 绘制组件类型
                font.setBold(False)
                font.setPointSize(8)
                painter.setFont(font)

                type_text = font_metrics.elidedText(self.component.type,
                                                    Qt.TextElideMode.ElideRight,
                                                    self.width - 20)

                painter.drawText(QRectF(10, 40, self.width - 20, 20),
                                 Qt.AlignmentFlag.AlignCenter, type_text)


    def itemChange(self, change, value):
        """项变化事件"""
        if change == QGraphicsItem.GraphicsItemChange.ItemPositionChange:
            # 更新组件位置
            self.component.x = value.x()
            self.component.y = value.y()

            # 更新所有连接
            self.update_connections()

            if self.scene():
                self.scene().update()

        elif change == QGraphicsItem.GraphicsItemChange.ItemSelectedChange:
            self.is_selected = bool(value)
            self.update()

        elif change == QGraphicsItem.GraphicsItemChange.ItemPositionHasChanged:
            self.update()

        return super().itemChange(change, value)

    def hoverEnterEvent(self, event):
        """悬停进入事件"""
        self.is_hovered = True
        self.update()
        super().hoverEnterEvent(event)

    def hoverLeaveEvent(self, event):
        """悬停离开事件"""
        self.is_hovered = False
        self.update()
        super().hoverLeaveEvent(event)

    def update_connections(self):
        """更新所有连接"""
        for connection in self.connections:
            if hasattr(connection, 'update_line'):
                connection.update_line()

    def get_port_position(self, port_loc):
        """获取端口位置（场景坐标）"""
        if port_loc == 'top':
            return self.mapToScene(self.top_port.pos())
        elif port_loc == 'bottom':
            return self.mapToScene(self.bottom_port.pos())
        elif port_loc == 'left':
            return self.mapToScene(self.left_port.pos())
        elif port_loc == 'right':
            return self.mapToScene(self.right_port.pos())
        else:
            return None

    def add_connection(self, connection):
        """添加连接"""
        if connection not in self.connections:
            self.connections.append(connection)

    def remove_connection(self, connection):
        """移除连接"""
        if connection in self.connections:
            self.connections.remove(connection)

    def port_clicked(self, port):
        """端口被点击"""
        if self.scene():
            view = self.scene().views()[0]
            if hasattr(view, 'port_clicked'):
                view.port_clicked(self, port)

    def get_clicked_port_type(self, pos):
        """检测点击的是哪个端口区域"""
        local_pos = self.mapFromScene(pos) if isinstance(pos, QPointF) else pos

        top_port_rect = QRectF(self.width / 2 + PortGraphicsItem.PORT_RADIUS, -PortGraphicsItem.PORT_RADIUS,
                               PortGraphicsItem.PORT_RADIUS, PortGraphicsItem.PORT_RADIUS)
        bottom_port_rect = QRectF(self.width / 2 + PortGraphicsItem.PORT_RADIUS, self.height + PortGraphicsItem.PORT_RADIUS,
                                  PortGraphicsItem.PORT_RADIUS, PortGraphicsItem.PORT_RADIUS)
        right_port_rect = QRectF(self.width + PortGraphicsItem.PORT_RADIUS, self.height / 2,
                                 PortGraphicsItem.PORT_RADIUS, PortGraphicsItem.PORT_RADIUS)
        left_port_rect = QRectF(-PortGraphicsItem.PORT_RADIUS, self.height / 2,
                                PortGraphicsItem.PORT_RADIUS, PortGraphicsItem.PORT_RADIUS)

        if top_port_rect.contains(local_pos):
            return 'top'
        elif bottom_port_rect.contains(local_pos):
            return 'bottom'
        elif right_port_rect.contains(local_pos):
            return 'right'
        elif left_port_rect.contains(local_pos):
            return 'left'

        return None

    def mouseDoubleClickEvent(self, event):
        """鼠标双击事件"""
        if event.button() == Qt.MouseButton.LeftButton:
            if self.scene():
                view = self.scene().views()[0]
                if hasattr(view, 'edit_component_parameters'):
                    view.edit_component_parameters(self.component.id)
            event.accept()
        else:
            super().mouseDoubleClickEvent(event)

class ConnectionGraphicsItem(QGraphicsPathItem):

    def __init__(self, source_component, target_component, source_port, target_port, connection_id, parent=None):
        super().__init__(parent)

        self.source_component = source_component
        self.target_component = target_component
        self.connection_id = connection_id
        self.source_port = source_port
        self.target_port = target_port

        self.setFlags(
            QGraphicsItem.GraphicsItemFlag.ItemIsSelectable |
            QGraphicsItem.GraphicsItemFlag.ItemSendsGeometryChanges
        )
        self.setAcceptHoverEvents(True)

        self.normal_pen = QPen(QColor(70, 130, 180), 2, Qt.PenStyle.SolidLine,
                               Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
        self.selected_pen = QPen(QColor(220, 20, 60), 3, Qt.PenStyle.SolidLine,
                                 Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
        self.hover_pen = QPen(QColor(30, 144, 255), 3, Qt.PenStyle.SolidLine,
                              Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)

        self.setPen(self.normal_pen)
        self.setZValue(-1)  # 确保连接线在组件下面

        self.is_selected = False
        self.is_hovered = False

        # 添加到组件
        if source_component:
            source_component.add_connection(self)
        if target_component:
            target_component.add_connection(self)

        # 更新线条
        self.update_line()

    def update_line(self):
        """更新连接线"""
        try:
            if not self.source_component or not self.target_component:
                return

            # 获取端口位置
            source_pos = self.source_component.get_port_position(self.source_port)
            target_pos = self.target_component.get_port_position(self.target_port)

            # 创建贝塞尔曲线路径
            path = QPainterPath(source_pos)

            # 计算控制点
            dx = target_pos.x() - source_pos.x()
            dy = target_pos.y() - source_pos.y()

            # 控制点位置（创建平滑曲线）
            ctrl1 = QPointF(source_pos.x() + dx * 0.5, source_pos.y())
            ctrl2 = QPointF(target_pos.x() - dx * 0.5, target_pos.y())

            # 添加三次贝塞尔曲线
            path.cubicTo(ctrl1, ctrl2, target_pos)

            self.setPath(path)

            # 创建箭头
            self.create_arrow(path)

        except RuntimeError:
            pass  # 忽略已删除的组件

    def create_arrow(self, path):
        """创建箭头"""
        arrow_size = 8

        # 在路径的95%处放置箭头
        percent = 0.95
        arrow_point = path.pointAtPercent(percent)

        # 计算角度
        if percent < 1.0:
            next_point = path.pointAtPercent(min(percent + 0.01, 1.0))
            angle = math.atan2(next_point.y() - arrow_point.y(),
                               next_point.x() - arrow_point.x()) * 180 / math.pi
        else:
            prev_point = path.pointAtPercent(max(percent - 0.01, 0.0))
            angle = math.atan2(arrow_point.y() - prev_point.y(),
                               arrow_point.x() - prev_point.x()) * 180 / math.pi

        # 创建箭头多边形
        arrow_p1 = QPointF(-arrow_size, -arrow_size / 2)
        arrow_p2 = QPointF(-arrow_size, arrow_size / 2)

        # 应用变换
        transform = QTransform()
        transform.translate(arrow_point.x(), arrow_point.y())
        transform.rotate(angle)

        arrow_p1 = transform.map(arrow_p1)
        arrow_p2 = transform.map(arrow_p2)

        self.arrow_polygon = QPolygonF([arrow_point, arrow_p1, arrow_p2])

    def paint(self, painter: QPainter, option: QStyleOptionGraphicsItem, widget=None):
        """绘制连接线"""
        try:
            if not self.path():
                return

            painter.setRenderHint(QPainter.RenderHint.Antialiasing)

            # 选择笔刷
            if self.is_selected:
                pen = self.selected_pen
            elif self.is_hovered:
                pen = self.hover_pen
            else:
                pen = self.normal_pen

            painter.setPen(pen)
            painter.drawPath(self.path())

            # 绘制箭头
            if hasattr(self, 'arrow_polygon'):
                painter.setBrush(pen.color())
                painter.drawPolygon(self.arrow_polygon)

        except RuntimeError:
            pass

    def hoverEnterEvent(self, event):
        """悬停进入事件"""
        self.is_hovered = True
        self.update()
        super().hoverEnterEvent(event)

    def hoverLeaveEvent(self, event):
        """悬停离开事件"""
        self.is_hovered = False
        self.update()
        super().hoverLeaveEvent(event)

    def itemChange(self, change, value):
        """项变化事件"""
        if change == QGraphicsItem.GraphicsItemChange.ItemSelectedChange:
            self.is_selected = bool(value)
            self.update()
        return super().itemChange(change, value)

    def shape(self):
        """返回点击区域形状"""
        stroker = QPainterPathStroker()
        stroker.setWidth(10)  # 点击区域宽度
        stroker.setCapStyle(Qt.PenCapStyle.RoundCap)
        stroker.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
        return stroker.createStroke(self.path())

    def boundingRect(self):
        """返回边界矩形"""
        if hasattr(self, 'arrow_polygon') and self.path():
            rect = self.path().boundingRect()
            arrow_rect = self.arrow_polygon.boundingRect()
            return rect.united(arrow_rect).adjusted(-5, -5, 5, 5)
        elif self.path():
            return self.path().boundingRect().adjusted(-5, -5, 5, 5)
        else:
            return QRectF()

    def remove_from_components(self):
        """从组件中移除连接"""
        try:
            if self.source_component:
                self.source_component.remove_connection(self)
            if self.target_component:
                self.target_component.remove_connection(self)
        except RuntimeError:
            pass  # 组件可能已被删除