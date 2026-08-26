"""Checkpoint, export, and reproducibility artifacts for simulations."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import platform
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape


def json_safe(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, bool)):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else str(value)
    if isinstance(value, complex):
        return {"real": value.real, "imag": value.imag}
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [json_safe(item) for item in value]
    if hasattr(value, "tolist"):
        try:
            return json_safe(value.tolist())
        except Exception:
            pass
    if hasattr(value, "item"):
        try:
            return json_safe(value.item())
        except Exception:
            pass
    return str(value)


def topology_signature(topology: dict[str, Any]) -> str:
    payload = json.dumps(json_safe(topology), ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def atomic_write_json(path: str | Path, data: dict[str, Any]) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=str(target.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(json_safe(data), stream, ensure_ascii=False, indent=2)
        Path(temporary_name).replace(target)
    except Exception:
        try:
            Path(temporary_name).unlink()
        except OSError:
            pass
        raise
    return target


class SweepCheckpoint:
    VERSION = 1

    def __init__(self, path: str | Path, signature: str) -> None:
        self.path = Path(path)
        self.signature = signature

    def load_rows(self) -> list[dict[str, Any]]:
        rows, _ = self.load_state()
        return rows

    def load_state(self) -> tuple[list[dict[str, Any]], int]:
        if not self.path.exists():
            return [], 0
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise ValueError(f"扫描断点文件损坏: {exc}") from exc
        if data.get("version") != self.VERSION or data.get("topology_signature") != self.signature:
            raise ValueError("扫描断点与当前拓扑或扫描参数不匹配。")
        rows = data.get("rows", [])
        rows = rows if isinstance(rows, list) else []
        return rows, max(0, int(data.get("completed_points", 0)))

    def save_rows(self, rows: list[dict[str, Any]], total_points: int, completed_points: int) -> None:
        atomic_write_json(self.path, {
            "version": self.VERSION,
            "topology_signature": self.signature,
            "completed_points": completed_points,
            "total_points": total_points,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "rows": rows,
        })

    def remove(self) -> None:
        try:
            self.path.unlink()
        except FileNotFoundError:
            pass


def _headers(rows: list[dict[str, Any]]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for key in row:
            text = str(key)
            if text not in seen:
                seen.add(text)
                result.append(text)
    return result


def write_csv(path: str | Path, rows: list[dict[str, Any]]) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    headers = _headers(rows)
    with target.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=headers, extrasaction="ignore")
        if headers:
            writer.writeheader()
            for row in rows:
                writer.writerow({key: _cell_value(row.get(key)) for key in headers})
    return target


def write_xlsx(path: str | Path, sheets: dict[str, list[dict[str, Any]]]) -> Path:
    """Write a dependency-free XLSX workbook using inline strings."""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    valid_sheets = [(name[:31] or "Sheet", rows) for name, rows in sheets.items()] or [("Sheet1", [])]
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as book:
        book.writestr("[Content_Types].xml", _content_types(len(valid_sheets)))
        book.writestr("_rels/.rels", _root_rels())
        book.writestr("xl/workbook.xml", _workbook_xml(valid_sheets))
        book.writestr("xl/_rels/workbook.xml.rels", _workbook_rels(len(valid_sheets)))
        book.writestr("xl/styles.xml", _styles_xml())
        for index, (_, rows) in enumerate(valid_sheets, start=1):
            book.writestr(f"xl/worksheets/sheet{index}.xml", _sheet_xml(rows))
    return target


def write_reproducibility_record(
    path: str | Path,
    topology: dict[str, Any],
    outputs: dict[str, Any],
    engine_diagnostics: dict[str, Any],
    measurement_datasets: list[dict[str, Any]] | None = None,
) -> Path:
    return atomic_write_json(path, {
        "format": "OpticalSystemSimulationRecord/1",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "topology_signature": topology_signature(topology),
        "environment": {
            "platform": platform.platform(),
            "python": sys.version,
            "executable": sys.executable,
            "matlab": engine_diagnostics,
        },
        "topology": topology,
        "measurement_datasets": measurement_datasets or [],
        "outputs": outputs,
    })


def result_sheets(summary_rows: list[dict[str, Any]], sweep: dict[str, Any] | None) -> dict[str, list[dict[str, Any]]]:
    sheets = {"Summary": summary_rows}
    if sweep and isinstance(sweep.get("rows"), list):
        sheets["Sweep"] = sweep["rows"]
    return sheets


def _cell_value(value: Any) -> Any:
    safe = json_safe(value)
    return json.dumps(safe, ensure_ascii=False) if isinstance(safe, (dict, list)) else safe


def _column_name(index: int) -> str:
    name = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        name = chr(65 + remainder) + name
    return name


def _sheet_xml(rows: list[dict[str, Any]]) -> str:
    headers = _headers(rows)
    grid = [headers] + [[row.get(header, "") for header in headers] for row in rows] if headers else []
    xml_rows: list[str] = []
    for row_index, row in enumerate(grid, start=1):
        cells: list[str] = []
        for column_index, raw in enumerate(row, start=1):
            ref = f"{_column_name(column_index)}{row_index}"
            value = _cell_value(raw)
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                cells.append(f'<c r="{ref}"><v>{value}</v></c>')
            else:
                cells.append(f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">{escape(str(value))}</t></is></c>')
        xml_rows.append(f'<row r="{row_index}">{"".join(cells)}</row>')
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' + "".join(xml_rows) + "</sheetData></worksheet>"


def _content_types(count: int) -> str:
    sheets = "".join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' for i in range(1, count + 1))
    return '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' + sheets + "</Types>"


def _root_rels() -> str:
    return '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'


def _workbook_xml(sheets: list[tuple[str, Any]]) -> str:
    entries = "".join(f'<sheet name="{escape(name)}" sheetId="{i}" r:id="rId{i}"/>' for i, (name, _) in enumerate(sheets, start=1))
    return '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' + entries + "</sheets></workbook>"


def _workbook_rels(count: int) -> str:
    entries = "".join(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>' for i in range(1, count + 1))
    entries += f'<Relationship Id="rId{count + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    return '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + entries + "</Relationships>"


def _styles_xml() -> str:
    return '<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
