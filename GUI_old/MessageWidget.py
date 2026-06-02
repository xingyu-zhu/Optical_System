import datetime
import io
import os
import re
import sys
import tempfile
import time
from typing import Dict, List

from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject
from PyQt6.QtGui import QColor, QFont, QTextCursor, QTextCharFormat, QSyntaxHighlighter
from PyQt6.QtWidgets import (QTextEdit, QWidget, QVBoxLayout, QHBoxLayout, QPushButton,
                             QLabel, QComboBox, QCheckBox, QApplication,
                             QMessageBox, QFileDialog)


# ════════════════════════════════════════════════════════════
#  信号代理 —— 跨线程安全转发消息到主线程 UI
# ════════════════════════════════════════════════════════════
class _MessageSignalProxy(QObject):
    sig = pyqtSignal(str, str, str)   # (message, level, source)


# ════════════════════════════════════════════════════════════
#  Python stdout / stderr 重定向器
# ════════════════════════════════════════════════════════════
class PythonOutputRedirector(io.TextIOBase):
    """
    替换 sys.stdout 或 sys.stderr，将输出逐行转发到 MessageArea。
    继承 io.TextIOBase 兼容所有需要 file-like 对象的场景。
    通过 pyqtSignal 保证子线程 print() 也能安全地更新 UI。
    """

    def __init__(self, proxy: _MessageSignalProxy, level: str, source: str):
        super().__init__()
        self._proxy  = proxy
        self._level  = level
        self._source = source
        self._buf    = ""

    def write(self, text: str) -> int:
        if not text:
            return 0
        self._buf += text
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            line = line.rstrip("\r")
            if line:
                self._proxy.sig.emit(line, self._level, self._source)
        return len(text)

    def flush(self):
        if self._buf.strip():
            self._proxy.sig.emit(self._buf.strip(), self._level, self._source)
            self._buf = ""

    def isatty(self) -> bool:
        return False


# ════════════════════════════════════════════════════════════
#  MATLAB 输出捕获器（正确方案：log 文件轮询）
#
#  【根本原因】StringIO 方案无法实时：
#    MATLAB Engine 只在 eng.eval()/eng.func() 调用完成后
#    才把内容一次性写入 stdout 参数，执行过程中 StringIO 始终为空。
#    这是 MathWorks 官方已知限制。
#
#  【正确方案】
#    1. MATLAB 脚本内部用 java.io.BufferedWriter 实时写 log 文件
#    2. Python 用 background=True 异步执行，不阻塞主线程
#    3. QTimer 轮询 log 文件，读取新增行发到 MessageArea
#    4. 调用结束后通过 StringIO 读取普通 disp/fprintf 输出
# ════════════════════════════════════════════════════════════
class MatlabOutputCapture:
    """
    MATLAB 实时输出捕获器。

    Python 侧使用方式：
        capture = self.msg.matlab_capture

        # 每次执行前
        capture.prepare()                        # 创建新 log 文件，重置缓冲
        future = eng.your_func(...,
                                background=True, # 必须异步，否则阻塞
                                stdout=capture.stdout_buf,
                                stderr=capture.stderr_buf)
        capture.watch(future)                    # 启动轮询，future 完成后自动停止

    MATLAB 脚本内部写 log 文件（实现实时输出）：
        function your_func(logfile)
            fw = java.io.FileWriter(logfile, false);
            bw = java.io.BufferedWriter(fw);
            cleanup = onCleanup(@() bw.close());

            bw.write('Step 1 starting...'); bw.newLine(); bw.flush();
            % ... 你的代码 ...
            bw.write('Step 1 done.');      bw.newLine(); bw.flush();
        end
    """

    def __init__(self, proxy: _MessageSignalProxy, poll_ms: int = 300):
        self._proxy      = proxy
        self._poll_ms    = poll_ms
        self.stdout_buf  = io.StringIO()   # 调用结束后读取普通输出
        self.stderr_buf  = io.StringIO()
        self._log_path   = None            # 实时 log 文件路径
        self._log_pos    = 0               # 已读取位置
        self._future     = None            # MATLAB FutureResult
        self._timer      = QTimer()
        self._timer.timeout.connect(self._poll)

    # ── 公开接口 ──────────────────────────────────────────────

    def prepare(self) -> str:
        """
        每次执行 MATLAB 前调用。
        创建新的临时 log 文件，重置所有缓冲区。
        返回 log 文件路径（需要传给 MATLAB 脚本）。
        """
        # 关闭上一次的 log 文件
        if self._log_path and os.path.exists(self._log_path):
            try:
                os.remove(self._log_path)
            except OSError:
                pass

        # 创建新的临时 log 文件
        fd, self._log_path = tempfile.mkstemp(suffix=".log", prefix="matlab_out_")
        os.close(fd)
        self._log_pos   = 0
        self.stdout_buf = io.StringIO()
        self.stderr_buf = io.StringIO()
        return self._log_path

    def watch(self, future=None):
        """
        启动轮询。
        future: matlab.engine.FutureResult（background=True 时的返回值）。
                传入后，future 完成时自动停止轮询并读取最终输出。
                若为 None，需手动调用 stop()。
        """
        self._future = future
        self._timer.start(self._poll_ms)

    def stop(self):
        """手动停止轮询，并做最终一次刷新"""
        self._timer.stop()
        self._flush_log()
        self._flush_stringio()

    @property
    def log_path(self) -> str:
        """当前 log 文件的完整路径（传给 MATLAB 脚本使用）"""
        return self._log_path or ""

    # ── 内部轮询 ──────────────────────────────────────────────

    def _poll(self):
        # 1. 实时读取 log 文件新增内容
        self._flush_log()

        # 2. 检查 future 是否完成
        if self._future is not None:
            try:
                done = self._future.done()
            except Exception:
                done = True

            if done:
                self._timer.stop()
                # 最终刷新（确保最后几行不遗漏）
                self._flush_log()
                # 读取 StringIO 中的普通输出（调用结束后才可读）
                self._flush_stringio()
                self._future = None
                self._proxy.sig.emit("MATLAB 执行完成", "SUCCESS", "MATLAB")

    def _flush_log(self):
        """从 log 文件读取新增行"""
        if not self._log_path or not os.path.exists(self._log_path):
            return
        try:
            with open(self._log_path, "r", encoding="utf-8", errors="replace") as f:
                f.seek(self._log_pos)
                chunk = f.read()
                if chunk:
                    self._log_pos = f.tell()
                    for line in chunk.splitlines():
                        line = line.strip()
                        if line:
                            self._proxy.sig.emit(line, "INFO", "MATLAB")
        except OSError:
            pass

    def _flush_stringio(self):
        """读取 StringIO 中的普通 disp/fprintf 输出（调用结束后）"""
        out_val = self.stdout_buf.getvalue().strip()
        if out_val:
            for line in out_val.splitlines():
                line = line.strip()
                if line:
                    self._proxy.sig.emit(line, "INFO", "MATLAB")

        err_val = self.stderr_buf.getvalue().strip()
        if err_val:
            for line in err_val.splitlines():
                line = line.strip()
                if line:
                    self._proxy.sig.emit(line, "ERROR", "MATLAB")

    def cleanup(self):
        """清理临时文件（程序退出时调用）"""
        self._timer.stop()
        if self._log_path and os.path.exists(self._log_path):
            try:
                os.remove(self._log_path)
            except OSError:
                pass


# ════════════════════════════════════════════════════════════
#  MessageHighlighter（原始代码，完全不变）
# ════════════════════════════════════════════════════════════
class MessageHighlighter(QSyntaxHighlighter):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.highlighting_rules = []

        def _add(pattern, color, bold=False, italic=False):
            fmt = QTextCharFormat()
            fmt.setForeground(QColor(color))
            if bold:   fmt.setFontWeight(QFont.Weight.Bold)
            if italic: fmt.setFontItalic(True)
            self.highlighting_rules.append((pattern, fmt))

        _add(r"\[INFO\]",               "#000000")
        _add(r"\[SUCCESS\]",            "#008000", bold=True)
        _add(r"\[WARNING\]",            "#FF8C00", bold=True)
        _add(r"\[ERROR\]",              "#FF0000", bold=True)
        _add(r"\[MATLAB\]",             "#0000FF", italic=True)
        _add(r"\[Python\]",             "#228B22", italic=True)
        _add(r"\[\d{2}:\d{2}:\d{2}\]", "#808080")
        _add(r"组件\s+[\w_]+:",         "#800080")

    def highlightBlock(self, text):
        for pattern, fmt in self.highlighting_rules:
            for m in re.finditer(pattern, text):
                self.setFormat(m.start(), m.end() - m.start(), fmt)


# ════════════════════════════════════════════════════════════
#  MessageArea（在原始代码基础上最小改动）
# ════════════════════════════════════════════════════════════
class MessageArea(QWidget):
    """消息区域 —— 支持 Python stdout/stderr 和 MATLAB 实时输出捕获"""

    def __init__(self, parent=None):
        super().__init__(parent)

        self.message_count = 0
        self.error_count   = 0
        self.warning_count = 0
        self.messages: List[dict] = []
        self.max_messages  = 1000

        self.init_ui()
        self.init_context_menu()

        self.auto_scroll = True

        self.cleanup_timer = QTimer()
        self.cleanup_timer.timeout.connect(self.cleanup_old_messages)
        self.cleanup_timer.start(60000)

        # ── 新增：信号代理 & 捕获器初始化 ──────────────────────
        self._proxy = _MessageSignalProxy(self)
        self._proxy.sig.connect(self.append_message)   # 直接连接到原有方法

        self._orig_stdout = None
        self._orig_stderr = None

        self.matlab_capture = MatlabOutputCapture(self._proxy)
        # ── 新增结束 ────────────────────────────────────────────

    # ── 新增：Python 重定向开关 ─────────────────────────────────
    def install_python_redirect(self):
        """将 sys.stdout/stderr 重定向到本消息区域（调用一次即可）"""
        if self._orig_stdout is not None:
            return
        self._orig_stdout = sys.stdout
        self._orig_stderr = sys.stderr
        sys.stdout = PythonOutputRedirector(self._proxy, "INFO",  "Python")
        sys.stderr = PythonOutputRedirector(self._proxy, "ERROR", "Python")
        self.append_message("Python stdout/stderr 已重定向到此区域", "SUCCESS", "System")

    def uninstall_python_redirect(self):
        """恢复 sys.stdout/stderr 为原始流"""
        if self._orig_stdout is None:
            return
        sys.stdout = self._orig_stdout
        sys.stderr = self._orig_stderr
        self._orig_stdout = None
        self._orig_stderr = None
    # ── 新增结束 ────────────────────────────────────────────────

    # ════ 以下为原始代码，仅有以下两处微调：
    #   1. filter_combo 加了 "Python" 选项
    #   2. append_message / filter_messages 中的重复逻辑提取为私有方法
    # ════════════════════════════════════════════════════════════

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(5)

        toolbar = QWidget()
        tl = QHBoxLayout(toolbar)
        tl.setContentsMargins(5, 2, 5, 2)

        title = QLabel("输出信息")
        title.setStyleSheet("font-weight: bold; font-size: 11pt;")
        tl.addWidget(title)
        tl.addStretch()

        self.stats_label = QLabel("消息: 0")
        self.stats_label.setStyleSheet("color: gray; font-size: 9pt;")
        tl.addWidget(self.stats_label)

        self.filter_combo = QComboBox()
        # ← 新增了 "Python" 选项
        self.filter_combo.addItems(["全部", "信息", "成功", "警告", "错误", "MATLAB", "Python"])
        self.filter_combo.currentTextChanged.connect(self.filter_messages)
        tl.addWidget(self.filter_combo)

        self.auto_scroll_check = QCheckBox("自动滚动")
        self.auto_scroll_check.setChecked(True)
        self.auto_scroll_check.stateChanged.connect(self.toggle_auto_scroll)
        tl.addWidget(self.auto_scroll_check)

        clear_button = QPushButton("清除")
        clear_button.setFixedSize(60, 22)
        clear_button.clicked.connect(self.clear_messages)
        tl.addWidget(clear_button)

        layout.addWidget(toolbar)

        self.text_edit = QTextEdit()
        self.text_edit.setReadOnly(True)
        self.text_edit.setStyleSheet("""
            QTextEdit {
                background-color: #f8f8f8;
                border: 1px solid #cccccc;
                border-radius: 3px;
                font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
                font-size: 10pt;
            }
        """)
        self.highlighter = MessageHighlighter(self.text_edit.document())
        layout.addWidget(self.text_edit, 1)

    def init_context_menu(self):
        self.text_edit.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.text_edit.customContextMenuRequested.connect(self.show_context_menu)

    def show_context_menu(self, position):
        menu = self.text_edit.createStandardContextMenu()
        menu.addSeparator()
        menu.addAction("复制全部").triggered.connect(self.copy_all)
        menu.addAction("保存到文件").triggered.connect(self.save_to_file)
        menu.addAction("清除消息").triggered.connect(self.clear_messages)
        menu.exec(self.text_edit.mapToGlobal(position))

    def append_message(self, message: str, level: str = "INFO", source: str = ""):
        timestamp = datetime.datetime.now().strftime("%H:%M:%S")
        prefix    = f"[{timestamp}] [{level}]" + (f" [{source}]" if source else "")
        full_msg  = f"{prefix} {message}"

        self.messages.append({
            'timestamp': timestamp, 'level': level, 'source': source,
            'message': message, 'full_message': full_msg, 'time': time.time()
        })

        self.message_count += 1
        if level == "ERROR":   self.error_count   += 1
        elif level == "WARNING": self.warning_count += 1

        self.update_stats()

        if self._match_filter({'level': level, 'source': source},
                              self.filter_combo.currentText()):
            self.text_edit.append(
                f'{full_msg}')
            if self.auto_scroll:
                self.scroll_to_bottom()

        if len(self.messages) > self.max_messages:
            self.messages = self.messages[-self.max_messages:]

    # ── 私有辅助（消除重复代码）─────────────────────────────────
    @staticmethod
    def _level_color(level: str) -> str:
        return {"INFO": "#000000", "SUCCESS": "#009900",
                "WARNING": "#FF9900", "ERROR": "#FF0000"}.get(level, "#000000")

    @staticmethod
    def _match_filter(msg: dict, ft: str) -> bool:
        if ft == "全部":    return True
        if ft == "信息"   and msg.get("level")  == "INFO":    return True
        if ft == "成功"   and msg.get("level")  == "SUCCESS":  return True
        if ft == "警告"   and msg.get("level")  == "WARNING":  return True
        if ft == "错误"   and msg.get("level")  == "ERROR":    return True
        if ft == "MATLAB" and msg.get("source") == "MATLAB":   return True
        if ft == "Python" and msg.get("source") == "Python":   return True
        return False

    # ════ 以下全部原始代码，一字未改 ════════════════════════════

    def should_display_message(self, level: str) -> bool:
        return self._match_filter({'level': level, 'source': ''},
                                  self.filter_combo.currentText())

    def filter_messages(self, filter_text: str):
        scrollbar     = self.text_edit.verticalScrollBar()
        was_at_bottom = scrollbar.value() == scrollbar.maximum()
        self.text_edit.clear()
        for msg in self.messages:
            if self._match_filter(msg, filter_text):
                self.text_edit.append(
                    f''
                    f'{msg["full_message"]}')
        if was_at_bottom and self.auto_scroll:
            self.scroll_to_bottom()

    def scroll_to_bottom(self):
        cursor = self.text_edit.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        self.text_edit.setTextCursor(cursor)

    def toggle_auto_scroll(self, state):
        self.auto_scroll = (state == Qt.CheckState.Checked.value)

    def update_stats(self):
        txt = f"消息: {self.message_count}"
        if self.error_count   > 0: txt += f" | 错误: {self.error_count}"
        if self.warning_count > 0: txt += f" | 警告: {self.warning_count}"
        self.stats_label.setText(txt)

    def clear_messages(self):
        reply = QMessageBox.question(
            self, "清除消息", "确定要清除所有消息吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply == QMessageBox.StandardButton.Yes:
            self.text_edit.clear()
            self.messages.clear()
            self.message_count = self.error_count = self.warning_count = 0
            self.update_stats()
            self.append_message("消息已清除", "INFO")

    def copy_all(self):
        QApplication.clipboard().setText(
            "\n".join(m["full_message"] for m in self.messages))
        self.append_message("所有消息已复制到剪贴板", "INFO")

    def save_to_file(self):
        filename, _ = QFileDialog.getSaveFileName(
            self, "保存消息", "./messages.log",
            "日志文件 (*.log);;文本文件 (*.txt);;所有文件 (*)")
        if filename:
            try:
                with open(filename, "w", encoding="utf-8") as f:
                    for msg in self.messages:
                        f.write(msg["full_message"] + "\n")
                self.append_message(f"消息已保存到 {filename}", "SUCCESS")
            except Exception as e:
                self.append_message(f"保存失败: {e}", "ERROR")

    def cleanup_old_messages(self):
        now = time.time()
        self.messages = [m for m in self.messages if now - m["time"] <= 3600]
        self.filter_messages(self.filter_combo.currentText())

    def get_message_summary(self) -> Dict:
        return {"total": self.message_count, "errors": self.error_count,
                "warnings": self.warning_count, "recent_count": len(self.messages)}

    def find_messages(self, keyword: str, level: str = None) -> List[Dict]:
        return [m for m in self.messages
                if keyword.lower() in m["message"].lower()
                and (level is None or m["level"] == level)]

    def highlight_messages(self, keyword: str):
        pass
