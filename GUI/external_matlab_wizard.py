"""Wizard for adding an external MATLAB component node."""

from __future__ import annotations

import re
from pathlib import Path

from PyQt5.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
)


class ExternalMatlabWizard(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("外部 MATLAB 组件向导")
        self.resize(680, 320)
        root = QVBoxLayout(self)
        form = QFormLayout()
        file_row = QHBoxLayout()
        self.file_edit = QLineEdit(self)
        browse = QPushButton("选择 .m 文件", self)
        browse.clicked.connect(self._browse)
        file_row.addWidget(self.file_edit, 1)
        file_row.addWidget(browse)
        form.addRow("MATLAB 文件", file_row)
        self.function_edit = QLineEdit(self)
        self.function_edit.setPlaceholderText("函数名，或 [out]=function_name(input)")
        form.addRow("调用表达式", self.function_edit)
        self.nargout = QSpinBox(self)
        self.nargout.setRange(0, 32)
        self.nargout.setValue(1)
        form.addRow("输出数量", self.nargout)
        self.add_path = QCheckBox("运行前加入 MATLAB 路径", self)
        self.add_path.setChecked(True)
        form.addRow("路径", self.add_path)
        self.merge_output = QCheckBox("struct 输出合并到组件工作区", self)
        self.merge_output.setChecked(True)
        form.addRow("输出处理", self.merge_output)
        root.addLayout(form)
        note = QLabel("向导会从 function 声明读取函数名；复杂参数可在创建后双击组件继续编辑。", self)
        note.setWordWrap(True)
        root.addWidget(note)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel, self)
        buttons.accepted.connect(self._validate)
        buttons.rejected.connect(self.reject)
        root.addWidget(buttons)

    def _browse(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "选择 MATLAB 文件", "", "MATLAB 文件 (*.m)")
        if not path:
            return
        self.file_edit.setText(path)
        function_name, output_count = self._read_signature(Path(path))
        if function_name:
            self.function_edit.setText(function_name)
        if output_count is not None:
            self.nargout.setValue(output_count)

    def _validate(self) -> None:
        path = Path(self.file_edit.text().strip())
        call = self.function_edit.text().strip()
        if not path.is_file() or path.suffix.lower() != ".m":
            QMessageBox.warning(self, "外部 MATLAB 组件", "请选择存在的 .m 文件。")
            return
        file_function, _ = self._read_signature(path)
        called_function = self._called_function(call)
        if not called_function:
            QMessageBox.warning(self, "外部 MATLAB 组件", "请输入有效的函数名或调用表达式。")
            return
        if file_function and called_function != file_function:
            QMessageBox.warning(self, "外部 MATLAB 组件", f"调用函数必须与文件声明一致：{file_function}")
            return
        self.accept()

    def parameters(self) -> dict[str, list[str]]:
        return {
            "MatlabFile": [self.file_edit.text().strip(), "", "外部 .m 文件完整路径"],
            "FunctionName": [self.function_edit.text().strip(), "", "函数名或调用表达式"],
            "AddToPath": [str(self.add_path.isChecked()), "", "运行前加入 MATLAB 路径"],
            "Nargout": [str(self.nargout.value()), "", "外部函数输出数量"],
            "MergeOutput": [str(self.merge_output.isChecked()), "", "合并 struct 输出"],
        }

    @staticmethod
    def _called_function(text: str) -> str:
        match = re.search(r"(?:=\s*)?([A-Za-z]\w*)\s*(?:\(|$)", text.strip())
        return match.group(1) if match else ""

    @staticmethod
    def _read_signature(path: Path) -> tuple[str, int | None]:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return "", None
        line = next((line.strip() for line in text.splitlines() if line.strip().lower().startswith("function")), "")
        if not line:
            return path.stem, None
        match = re.match(r"function\s+(?:(\[[^]]*\]|\w+)\s*=\s*)?([A-Za-z]\w*)", line, re.IGNORECASE)
        if not match:
            return path.stem, None
        output = (match.group(1) or "").strip()
        count = 0 if not output else len([part for part in output.strip("[]").split(",") if part.strip()])
        return match.group(2), count
