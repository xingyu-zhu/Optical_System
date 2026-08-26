"""Offline topology and parameter validation before MATLAB execution."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from matlab_component_registry import matlab_function_for_component
from measurement_dataset import MeasurementDatasetCatalog
from topology_executor import TopologyExecutor


@dataclass
class PreflightReport:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    checks: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors

    def to_text(self) -> str:
        lines = ["预检查通过" if self.ok else "预检查未通过"]
        for title, values in (("错误", self.errors), ("警告", self.warnings), ("检查", self.checks)):
            if values:
                lines.append(f"\n{title}：")
                lines.extend(f"- {value}" for value in values)
        return "\n".join(lines)


def run_preflight(
    topology: dict[str, Any],
    offline: bool = False,
    dataset_catalog: MeasurementDatasetCatalog | None = None,
) -> PreflightReport:
    report = PreflightReport()
    nodes = topology.get("nodes", [])
    edges = topology.get("edges", [])
    if not nodes:
        report.errors.append("工作区没有组件。")
        return report
    try:
        executor = TopologyExecutor(topology)
        levels = executor.topological_levels()
        report.checks.append(f"拓扑无环，共 {len(nodes)} 个组件、{len(edges)} 条连接、{len(levels)} 个执行层级。")
    except Exception as exc:
        report.errors.append(f"拓扑结构无效: {exc}")
        return report

    connected: set[int] = set()
    dataset_catalog = dataset_catalog or MeasurementDatasetCatalog()
    measured_count = 0
    for edge in edges:
        try:
            connected.update((int(edge["source_id"]), int(edge["target_id"])))
        except Exception:
            report.errors.append(f"连接记录缺少有效节点编号: {edge}")

    for raw in nodes:
        node_id = int(raw.get("id", 0))
        name = str(raw.get("name", ""))
        function_name = matlab_function_for_component(name)
        if not function_name:
            report.errors.append(f"节点 {node_id}（{name}）没有 MATLAB 函数映射。")
        if len(nodes) > 1 and node_id not in connected:
            report.warnings.append(f"节点 {node_id}（{name}）未连接。")
        if "matlabfile" in "".join(ch.lower() for ch in name if ch.isalnum()):
            _check_external_component(report, node_id, raw.get("params") or {})
        model_config = raw.get("model_config") or {}
        if str(model_config.get("BandwidthModel", "IdealBessel")).lower() == "measured":
            measured_count += 1
            _check_measurement_dataset(report, dataset_catalog, node_id, name, model_config)

    enabled_sweeps = [item for item in topology.get("parameter_sweeps", []) if item.get("enabled", True)]
    node_ids = {int(node.get("id", 0)) for node in nodes}
    for item in enabled_sweeps:
        try:
            node_id = int(item.get("node_id"))
            float(item.get("start"))
            float(item.get("stop"))
            step = float(item.get("step"))
            if step == 0:
                raise ValueError("步长不能为 0")
            if node_id not in node_ids:
                raise ValueError(f"节点 {node_id} 不存在")
            if not str(item.get("parameter", "")).strip():
                raise ValueError("参数名为空")
        except Exception as exc:
            report.errors.append(f"参数扫描配置无效: {exc}")
    if enabled_sweeps:
        report.checks.append(f"已校验 {len(enabled_sweeps)} 个启用的扫描轴。")
    if measured_count:
        report.checks.append(f"已校验 {measured_count} 个实测带宽模型及其四通道数据。")
    if offline:
        report.warnings.append("当前为离线模式；可编辑和预检查，但不能运行 MATLAB 仿真。")
    return report


def _check_external_component(report: PreflightReport, node_id: int, params: dict[str, Any]) -> None:
    file_path = str(_value(params.get("FilePath") or params.get("MatlabFile") or "")).strip()
    function_name = str(_value(params.get("FunctionName") or "")).strip()
    if not file_path:
        report.errors.append(f"外部 MATLAB 节点 {node_id} 未设置 .m 文件。")
    elif Path(file_path).suffix.lower() != ".m" or not Path(file_path).is_file():
        report.errors.append(f"外部 MATLAB 节点 {node_id} 的文件不存在或不是 .m 文件: {file_path}")
    if not function_name:
        report.errors.append(f"外部 MATLAB 节点 {node_id} 未设置函数名。")


def _check_measurement_dataset(
    report: PreflightReport,
    catalog: MeasurementDatasetCatalog,
    node_id: int,
    name: str,
    model_config: dict[str, Any],
) -> None:
    dataset_id = str(model_config.get("BandwidthDataset", "")).strip()
    if not dataset_id:
        report.errors.append(f"节点 {node_id}（{name}）已选择实测模型，但未指定数据集。")
        return
    try:
        dataset = catalog.get(dataset_id)
    except Exception as exc:
        report.errors.append(f"节点 {node_id}（{name}）的实测数据集不可用: {exc}")
        return
    normalized = "".join(ch.lower() for ch in name if ch.isalnum())
    expected = "modulator" if "modulator" in normalized else "receiver"
    if dataset.get("device_type") != expected:
        report.errors.append(f"节点 {node_id}（{name}）的数据集设备类型不匹配。")


def _value(value: Any) -> Any:
    return value[0] if isinstance(value, (list, tuple)) and value else value
