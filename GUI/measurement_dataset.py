"""Measured bandwidth dataset import, validation, and catalog storage."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import platform
import re
import shutil
import tempfile
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from xml.etree import ElementTree as ET


LANE_NAMES = ("XI", "XQ", "YI", "YQ")
DATASET_FORMAT = "OpticalSystemMeasuredBandwidth/1"
DEVICE_LABELS = {"modulator": "调制器", "receiver": "相干接收机"}


def default_dataset_root() -> Path:
    system = platform.system().lower()
    if system == "windows":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    elif system == "darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return base / "OpticalSystemGUI" / "measurement_datasets"


def file_sha256(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bandwidth_3db(frequency_hz: list[float], magnitude_db: list[float]) -> float | None:
    start = next((i for i, value in enumerate(frequency_hz) if value >= 2e9), 0)
    crossing = next((i for i in range(start, len(magnitude_db)) if magnitude_db[i] <= -3), None)
    if crossing is None:
        return None
    if crossing == 0:
        return frequency_hz[0]
    f1, f2 = frequency_hz[crossing - 1], frequency_hz[crossing]
    m1, m2 = magnitude_db[crossing - 1], magnitude_db[crossing]
    if m2 == m1:
        return f2
    return f1 + (-3 - m1) * (f2 - f1) / (m2 - m1)


@dataclass(frozen=True)
class DatasetSummary:
    dataset_id: str
    name: str
    device_type: str
    created_at: str
    path: Path
    lane_bandwidths_hz: dict[str, float | None]


class MeasurementDatasetCatalog:
    def __init__(self, root: str | Path | None = None) -> None:
        self.root = Path(root) if root else default_dataset_root()

    def dataset_path(self, dataset_id: str) -> Path:
        safe_id = self._safe_id(dataset_id)
        return self.root / safe_id / "dataset.json"

    def exists(self, dataset_id: str) -> bool:
        try:
            return self.dataset_path(dataset_id).is_file()
        except ValueError:
            return False

    def get(self, dataset_id: str) -> dict[str, Any]:
        path = self.dataset_path(dataset_id)
        data = json.loads(path.read_text(encoding="utf-8"))
        self.validate_dataset(data, expected_id=dataset_id)
        return data

    def list(self) -> list[DatasetSummary]:
        if not self.root.is_dir():
            return []
        summaries: list[DatasetSummary] = []
        for path in self.root.glob("*/dataset.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                self.validate_dataset(data)
                summaries.append(
                    DatasetSummary(
                        dataset_id=str(data["id"]),
                        name=str(data["name"]),
                        device_type=str(data["device_type"]),
                        created_at=str(data.get("created_at", "")),
                        path=path,
                        lane_bandwidths_hz={
                            lane: data["lanes"][lane].get("bandwidth_3db_hz")
                            for lane in LANE_NAMES
                        },
                    )
                )
            except Exception:
                continue
        return sorted(summaries, key=lambda item: item.created_at, reverse=True)

    def prepare_import(
        self,
        name: str,
        device_type: str,
        files: Iterable[str | Path],
        frequency_column: int = 1,
        response_column: int = 2,
        frequency_unit: str = "GHz",
        normalize: bool = True,
    ) -> dict[str, Any]:
        device = str(device_type).strip().lower()
        if device not in DEVICE_LABELS:
            raise ValueError("设备类型必须是 modulator 或 receiver。")
        source_paths = [Path(item).expanduser().resolve() for item in files]
        if len(source_paths) != 4:
            raise ValueError("必须按 XI、XQ、YI、YQ 顺序选择 4 个文件。")
        if any(not path.is_file() for path in source_paths):
            missing = [str(path) for path in source_paths if not path.is_file()]
            raise FileNotFoundError("测试文件不存在: " + ", ".join(missing))
        if frequency_column < 1 or response_column < 1:
            raise ValueError("列号从 1 开始。")

        scale = {"hz": 1.0, "mhz": 1e6, "ghz": 1e9}.get(frequency_unit.lower())
        if scale is None:
            raise ValueError("频率单位只支持 Hz、MHz 或 GHz。")

        lanes: dict[str, Any] = {}
        sources: list[dict[str, Any]] = []
        source_hashes: list[str] = []
        for lane, path in zip(LANE_NAMES, source_paths):
            rows = read_numeric_columns(path, frequency_column, response_column)
            frequency, magnitude = clean_response(rows, scale, normalize)
            digest = file_sha256(path)
            source_hashes.append(digest)
            lanes[lane] = {
                "frequency_hz": frequency,
                "magnitude_db": magnitude,
                "points": len(frequency),
                "bandwidth_3db_hz": bandwidth_3db(frequency, magnitude),
            }
            sources.append(
                {
                    "lane": lane,
                    "file_name": path.name,
                    "sha256": digest,
                    "frequency_column": frequency_column,
                    "response_column": response_column,
                }
            )

        clean_name = str(name).strip() or f"{DEVICE_LABELS[device]}实测带宽"
        identity = hashlib.sha256(
            (
                f"{device}\n{frequency_column}\n{response_column}\n"
                f"{frequency_unit.lower()}\n{int(normalize)}\n"
                + "\n".join(source_hashes)
            ).encode("utf-8")
        ).hexdigest()[:12]
        slug = re.sub(r"[^0-9A-Za-z_-]+", "-", clean_name).strip("-")[:32]
        dataset_id = f"{slug + '-' if slug else ''}{identity}"
        payload = {
            "format": DATASET_FORMAT,
            "id": dataset_id,
            "name": clean_name,
            "device_type": device,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "response_kind": "magnitude_db",
            "normalization": "median_0.5_to_2_GHz" if normalize else "none",
            "interpolation": "linear_hold_endpoints",
            "lane_order": list(LANE_NAMES),
            "sources": sources,
            "lanes": lanes,
        }
        self.validate_dataset(payload)
        return payload

    def commit(self, payload: dict[str, Any]) -> Path:
        self.validate_dataset(payload)
        target = self.dataset_path(str(payload["id"]))
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, temp_name = tempfile.mkstemp(prefix="dataset-", suffix=".json", dir=target.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_name, target)
        except Exception:
            try:
                os.unlink(temp_name)
            except OSError:
                pass
            raise
        return target

    def delete(self, dataset_id: str) -> None:
        path = self.dataset_path(dataset_id)
        folder = path.parent.resolve()
        root = self.root.resolve()
        if folder.parent != root:
            raise ValueError("数据集路径超出目录范围。")
        if folder.is_dir():
            shutil.rmtree(folder)

    def diagnostics(self) -> dict[str, Any]:
        items = self.list()
        return {
            "measurement_dataset_root": str(self.root),
            "measurement_dataset_count": len(items),
            "measurement_datasets": [
                {
                    "id": item.dataset_id,
                    "name": item.name,
                    "device": item.device_type,
                    "path": str(item.path),
                }
                for item in items
            ],
        }

    @staticmethod
    def validate_dataset(data: dict[str, Any], expected_id: str | None = None) -> None:
        if data.get("format") != DATASET_FORMAT:
            raise ValueError("不支持的实测带宽数据集格式。")
        dataset_id = str(data.get("id", ""))
        MeasurementDatasetCatalog._safe_id(dataset_id)
        if expected_id is not None and dataset_id != expected_id:
            raise ValueError("数据集 ID 与目录不一致。")
        if data.get("device_type") not in DEVICE_LABELS:
            raise ValueError("数据集设备类型无效。")
        lanes = data.get("lanes")
        if not isinstance(lanes, dict):
            raise ValueError("数据集缺少通道数据。")
        for lane in LANE_NAMES:
            response = lanes.get(lane) or {}
            frequency = response.get("frequency_hz") or []
            magnitude = response.get("magnitude_db") or []
            if len(frequency) != len(magnitude) or len(frequency) < 2:
                raise ValueError(f"{lane} 通道数据不足或长度不一致。")
            if any(not math.isfinite(float(v)) for v in frequency + magnitude):
                raise ValueError(f"{lane} 通道包含非有限数值。")
            if any(float(frequency[i]) >= float(frequency[i + 1]) for i in range(len(frequency) - 1)):
                raise ValueError(f"{lane} 通道频率必须严格递增。")

    @staticmethod
    def _safe_id(dataset_id: str) -> str:
        text = str(dataset_id).strip()
        if not text or not re.fullmatch(r"[0-9A-Za-z_-]+", text):
            raise ValueError("数据集 ID 无效。")
        return text


def clean_response(
    rows: Iterable[tuple[float, float]], frequency_scale: float, normalize: bool
) -> tuple[list[float], list[float]]:
    unique: dict[float, float] = {}
    for raw_frequency, raw_magnitude in rows:
        frequency = float(raw_frequency) * frequency_scale
        magnitude = float(raw_magnitude)
        if math.isfinite(frequency) and math.isfinite(magnitude) and frequency >= 0:
            unique[frequency] = magnitude
    ordered = sorted(unique.items())
    if len(ordered) < 2:
        raise ValueError("每个文件至少需要 2 个有效且不同的非负频率点。")
    frequency = [item[0] for item in ordered]
    magnitude = [item[1] for item in ordered]
    if normalize:
        reference = [
            value for freq, value in zip(frequency, magnitude) if 0.5e9 <= freq <= 2e9
        ]
        if not reference:
            upper = min(frequency[-1], 2e9)
            reference = [value for freq, value in zip(frequency, magnitude) if freq <= upper]
        reference.sort()
        middle = len(reference) // 2
        baseline = (
            reference[middle]
            if len(reference) % 2
            else (reference[middle - 1] + reference[middle]) / 2
        )
        magnitude = [value - baseline for value in magnitude]
    if frequency[0] > 0:
        frequency.insert(0, 0.0)
        magnitude.insert(0, magnitude[0])
    return frequency, magnitude


def read_numeric_columns(
    path: str | Path, frequency_column: int, response_column: int
) -> list[tuple[float, float]]:
    source = Path(path)
    suffix = source.suffix.lower()
    if suffix == ".xlsx":
        return _read_xlsx_columns(source, frequency_column, response_column)
    if suffix in {".csv", ".txt", ".tsv"}:
        return _read_delimited_columns(source, frequency_column, response_column)
    raise ValueError(f"不支持的测试文件格式: {source.suffix}")


def _read_delimited_columns(path: Path, frequency_column: int, response_column: int) -> list[tuple[float, float]]:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;\t ")
    except csv.Error:
        dialect = csv.excel
    result: list[tuple[float, float]] = []
    for row in csv.reader(text.splitlines(), dialect):
        try:
            result.append((float(row[frequency_column - 1]), float(row[response_column - 1])))
        except (ValueError, IndexError):
            continue
    return result


def _read_xlsx_columns(path: Path, frequency_column: int, response_column: int) -> list[tuple[float, float]]:
    main_ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    rel_ns = "http://schemas.openxmlformats.org/package/2006/relationships"
    office_rel_ns = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    with zipfile.ZipFile(path) as book:
        workbook = ET.fromstring(book.read("xl/workbook.xml"))
        sheet = workbook.find(f"{{{main_ns}}}sheets/{{{main_ns}}}sheet")
        if sheet is None:
            raise ValueError(f"工作簿没有工作表: {path.name}")
        rel_id = sheet.attrib.get(f"{{{office_rel_ns}}}id")
        rels = ET.fromstring(book.read("xl/_rels/workbook.xml.rels"))
        target = None
        for rel in rels.findall(f"{{{rel_ns}}}Relationship"):
            if rel.attrib.get("Id") == rel_id:
                target = rel.attrib.get("Target")
                break
        if not target:
            raise ValueError(f"无法定位首个工作表: {path.name}")
        clean_target = target.lstrip("/")
        sheet_path = clean_target if clean_target.startswith("xl/") else "xl/" + clean_target

        shared: list[str] = []
        if "xl/sharedStrings.xml" in book.namelist():
            root = ET.fromstring(book.read("xl/sharedStrings.xml"))
            for item in root.findall(f"{{{main_ns}}}si"):
                shared.append("".join(node.text or "" for node in item.iter(f"{{{main_ns}}}t")))

        result: list[tuple[float, float]] = []
        row_values: dict[int, str] = {}
        for event, elem in ET.iterparse(book.open(sheet_path), events=("end",)):
            if elem.tag == f"{{{main_ns}}}c":
                ref = elem.attrib.get("r", "")
                match = re.match(r"([A-Z]+)", ref)
                if match:
                    col = _column_index(match.group(1))
                    if col in {frequency_column, response_column}:
                        value_node = elem.find(f"{{{main_ns}}}v")
                        value = value_node.text if value_node is not None else None
                        if elem.attrib.get("t") == "s" and value is not None:
                            value = shared[int(value)]
                        elif elem.attrib.get("t") == "inlineStr":
                            value = "".join(
                                node.text or "" for node in elem.iter(f"{{{main_ns}}}t")
                            )
                        if value is not None:
                            row_values[col] = value
                elem.clear()
            elif elem.tag == f"{{{main_ns}}}row":
                try:
                    result.append(
                        (float(row_values[frequency_column]), float(row_values[response_column]))
                    )
                except (KeyError, ValueError):
                    pass
                row_values = {}
                elem.clear()
        return result


def _column_index(letters: str) -> int:
    value = 0
    for char in letters:
        value = value * 26 + ord(char) - 64
    return value
