"""MATLAB-backed topology runner."""

from __future__ import annotations

import copy
import itertools
import math
import gc
import re
import subprocess
from typing import Any, Callable

import numpy as np

from matlab_component_registry import component_type_for_component, matlab_function_for_component
from matlab_engine_manager import MatlabEngineManager
from topology_display import build_component_display_names, build_node_display_indices, result_component_allowed
from topology_executor import Node, TopologyExecutor


LogCallback = Callable[[str, str], None]


class MatlabTopologyRunner:
    """Run the current GUI topology by dispatching each node to MATLAB."""

    def __init__(self, engine_manager: MatlabEngineManager, log: LogCallback | None = None):
        self.engine_manager = engine_manager
        self.log = log or (lambda _message, _source="INFO": None)

    def run(self, topology: dict[str, Any]) -> dict[int, dict[str, Any]]:
        sweep = self._build_parameter_sweep(topology)
        if sweep:
            return self._run_parameter_sweep(topology, sweep)
        return self._run_once(topology)

    def _run_once(self, topology: dict[str, Any]) -> dict[int, dict[str, Any]]:
        executor = TopologyExecutor(topology)
        levels = executor.topological_levels()
        node_contexts = self._build_node_contexts(executor)
        _, _, incoming_edges, outgoing_edges = executor._build_graph()
        remaining_cache_consumers = {
            node_id: len(outgoing_edges.get(node_id, []))
            for node_id in executor.nodes
        }

        eng = self.engine_manager.start()
        self._clear_matlab_workspace_cache(eng)

        def component_runner(node: Node, inputs_by_port: dict[str, Any]) -> dict[str, Any]:
            function_name = matlab_function_for_component(node.name)
            node_context = node_contexts[node.node_id]

            matlab_inputs = self._to_matlab_inputs(inputs_by_port)
            matlab_params = self._to_matlab_params(node.params or {})
            node_context["return_lightweight"] = True
            outputs = eng.feval(
                "OC_GUI_RunWorkspaceComponent",
                node.name,
                function_name,
                matlab_inputs,
                matlab_params,
                node_context,
                nargout=1,
            )
            self._close_hidden_matlab_figures(eng)
            result = dict(outputs)
            self._log_workspace_status(node, result)
            for edge in incoming_edges.get(node.node_id, []):
                remaining_cache_consumers[edge.source_id] = max(
                    0,
                    remaining_cache_consumers.get(edge.source_id, 0) - 1,
                )
                if remaining_cache_consumers[edge.source_id] == 0:
                    source_node = executor.nodes.get(edge.source_id)
                    if source_node is not None:
                        self._delete_matlab_workspace_cache_ref(eng, source_node.node_id, source_node.name)
            if remaining_cache_consumers.get(node.node_id, 0) == 0:
                self._delete_matlab_workspace_cache_ref(eng, node.node_id, node.name)
            return {
                "default": result,
                "right": result,
                "bottom": result,
                "info": result,
            }

        try:
            outputs = executor.run(component_runner)
            self._log_final_metrics(outputs, topology)
            return outputs
        finally:
            self._cleanup_matlab_after_run(eng)

    def _run_parameter_sweep(self, topology: dict[str, Any], sweep: dict[str, Any]) -> dict[int, dict[str, Any]]:
        points = list(self._iter_sweep_points(sweep["depth_groups"]))
        rows: list[dict[str, Any]] = []
        last_outputs: dict[int, dict[str, Any]] = {}

        total = len(points)

        for index, point in enumerate(points, start=1):
            point_topology = self._topology_with_sweep_values(topology, point["assignments"])
            self.log(f"参数扫描 {index}/{total}", "INFO")
            outputs = self._run_once(point_topology)
            last_outputs = outputs
            rows.extend(self._collect_sweep_rows(outputs, point_topology, point, index))

        result = dict(last_outputs)
        result["__sweep__"] = {
            "axes": sweep["axes"],
            "rows": rows,
            "power_budget": self._compute_power_budget(rows),
        }
        return result

    def _build_parameter_sweep(self, topology: dict[str, Any]) -> dict[str, Any] | None:
        axes: list[dict[str, Any]] = []
        node_by_id = {int(node["id"]): node for node in topology.get("nodes", []) if "id" in node}
        for item in topology.get("parameter_sweeps", []):
            if not item.get("enabled", True):
                continue
            node_id = self._int_or_none(item.get("node_id"))
            parameter = str(item.get("parameter", "")).strip()
            if node_id is None or not parameter:
                continue
            node = node_by_id.get(node_id)
            if not node:
                continue
            values = self._range_from_values(item.get("start"), item.get("stop"), item.get("step"))
            if not values:
                continue
            component = str(item.get("component") or node.get("name", ""))
            unit = str(item.get("unit", ""))
            axes.append(
                {
                    "kind": self._sweep_kind(component, parameter),
                    "label": f"{component}.{parameter}",
                    "node_id": node_id,
                    "component": component,
                    "param": parameter,
                    "values": values,
                    "unit": unit,
                    "depth": max(1, int(self._float_or_none(item.get("depth")) or 1)),
                }
            )

        if not axes:
            return None

        depth_groups: list[dict[str, Any]] = []
        for depth in sorted({int(axis["depth"]) for axis in axes}):
            group_axes = [axis for axis in axes if int(axis["depth"]) == depth]
            depth_groups.append({"depth": depth, "axes": group_axes})
        return {"axes": axes, "depth_groups": depth_groups}

    def _iter_sweep_points(self, depth_groups: list[dict[str, Any]]):
        grouped_points = [self._simultaneous_group_points(group["axes"]) for group in depth_groups]
        for combo in itertools.product(*grouped_points):
            assignments: list[dict[str, Any]] = []
            values_by_kind: dict[str, float] = {}
            value_labels: list[str] = []
            for group_point in combo:
                assignments.extend(group_point["assignments"])
                values_by_kind.update(group_point["values_by_kind"])
                value_labels.extend(group_point["labels"])
            yield {
                "assignments": assignments,
                "values_by_kind": values_by_kind,
                "label": ", ".join(value_labels),
            }

    def _simultaneous_group_points(self, axes: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not axes:
            return [{"assignments": [], "values_by_kind": {}, "labels": []}]
        length = max(len(axis["values"]) for axis in axes)
        points: list[dict[str, Any]] = []
        for index in range(length):
            assignments = []
            values_by_kind: dict[str, float] = {}
            labels = []
            for axis in axes:
                values = axis["values"]
                value = values[min(index, len(values) - 1)]
                assignment = dict(axis)
                assignment["value"] = value
                assignments.append(assignment)
                if axis["kind"] not in {"parameter"}:
                    values_by_kind[axis["kind"]] = value
                labels.append(f"{axis['label']}={self._format_number(value)}{axis.get('unit', '')}")
            points.append({"assignments": assignments, "values_by_kind": values_by_kind, "labels": labels})
        return points

    def _topology_with_sweep_values(
        self,
        topology: dict[str, Any],
        assignments: list[dict[str, Any]],
    ) -> dict[str, Any]:
        data = copy.deepcopy(topology)
        nodes = {int(node["id"]): node for node in data.get("nodes", [])}
        for assignment in assignments:
            value = assignment["value"]
            node = nodes.get(int(assignment["node_id"]))
            if not node:
                continue
            params = node.setdefault("params", {})
            old = params.get(assignment["param"], ["", assignment.get("unit", ""), ""])
            unit = old[1] if isinstance(old, list) and len(old) > 1 else assignment.get("unit", "")
            desc = old[2] if isinstance(old, list) and len(old) > 2 else assignment.get("label", "")
            params[assignment["param"]] = [self._format_number(value), unit, desc]
        return data

    def _collect_sweep_rows(
        self,
        outputs: dict[int, dict[str, Any]],
        topology: dict[str, Any],
        point: dict[str, Any],
        point_index: int,
    ) -> list[dict[str, Any]]:
        nodes = topology.get("nodes", [])
        names = {int(n["id"]): str(n.get("name", "")) for n in nodes}
        display_names = build_component_display_names(nodes)
        display_indices = build_node_display_indices(nodes)
        values_by_kind = point.get("values_by_kind", {})
        sweep_values = {
            assignment["label"]: assignment["value"]
            for assignment in point.get("assignments", [])
        }
        rows: list[dict[str, Any]] = []
        for node_id, node_outputs in outputs.items():
            if not isinstance(node_id, int):
                continue
            component_name = names.get(node_id, "")
            if not result_component_allowed(component_name):
                continue
            workspace = self._workspace_from_outputs(node_outputs)
            if not workspace or ("SNR" not in workspace and "BER" not in workspace):
                continue
            display_name = display_names.get(node_id, component_name)
            snr_values = self._as_flat_array(workspace.get("SNR"))
            ber_values = self._as_flat_array(workspace.get("BER"))
            metric_count = max(len(snr_values), len(ber_values), 1)
            for metric_index in range(metric_count):
                suffix = f" - ONU {metric_index + 1}" if metric_count > 1 else ""
                rows.append(
                    {
                        "point_index": point_index,
                        "node_id": node_id,
                        "display_node_id": display_indices.get(node_id, node_id),
                        "component": f"{display_name}{suffix}",
                        "sweep_label": point.get("label", ""),
                        "sweep_values": sweep_values,
                        "tx_power_dbm": values_by_kind.get("tx_power_dbm"),
                        "rop_dbm": values_by_kind.get("rop_dbm"),
                        "SNR": self._metric_value(snr_values, metric_index),
                        "BER": self._metric_value(ber_values, metric_index),
                    }
                )
        return rows

    def _compute_power_budget(self, rows: list[dict[str, Any]], fec_limit: float = 1e-2) -> list[dict[str, Any]]:
        by_key: dict[tuple[float | None, int, str], list[dict[str, Any]]] = {}
        for row in rows:
            if row.get("tx_power_dbm") is None or row.get("rop_dbm") is None:
                continue
            key = (row.get("tx_power_dbm"), int(row.get("node_id", 0)), str(row.get("component", "")))
            by_key.setdefault(key, []).append(row)

        budget_rows: list[dict[str, Any]] = []
        for (tx_power, node_id, component), group in sorted(by_key.items(), key=lambda item: (item[0][0], item[0][1])):
            sensitivity = self._interpolate_sensitivity(group, fec_limit)
            budget = None if sensitivity is None else float(tx_power) - sensitivity
            budget_rows.append(
                {
                    "tx_power_dbm": tx_power,
                    "node_id": node_id,
                    "display_node_id": group[0].get("display_node_id", node_id),
                    "component": component,
                    "sensitivity_dbm": sensitivity,
                    "power_budget_db": budget,
                    "fec_limit": fec_limit,
                }
            )
        return budget_rows

    def _interpolate_sensitivity(self, rows: list[dict[str, Any]], fec_limit: float) -> float | None:
        points = []
        for row in rows:
            rop = self._float_or_none(row.get("rop_dbm"))
            ber = self._float_or_none(row.get("BER"))
            if rop is not None and ber is not None and ber > 0:
                points.append((rop, ber))
        points.sort()
        if not points:
            return None

        target = math.log10(fec_limit)
        for (rop_a, ber_a), (rop_b, ber_b) in zip(points, points[1:]):
            log_a = math.log10(ber_a)
            log_b = math.log10(ber_b)
            if (log_a - target) * (log_b - target) <= 0 and log_a != log_b:
                ratio = (target - log_a) / (log_b - log_a)
                return rop_a + ratio * (rop_b - rop_a)
        return None

    @staticmethod
    def _range_from_values(start_value: Any, stop_value: Any, step_value: Any) -> list[float] | None:
        start = MatlabTopologyRunner._float_or_none(start_value)
        stop = MatlabTopologyRunner._float_or_none(stop_value)
        step = MatlabTopologyRunner._float_or_none(step_value)
        return MatlabTopologyRunner._range_from_numbers(start, stop, step)

    @staticmethod
    def _range_from_numbers(start: float | None, stop: float | None, step: float | None) -> list[float] | None:
        if start is None or stop is None:
            return None
        if step is None or step == 0:
            step = 1.0 if stop >= start else -1.0
        if (stop - start) * step < 0:
            step = -step

        values: list[float] = []
        current = start
        limit = 1000
        while len(values) < limit and ((step > 0 and current <= stop + 1e-12) or (step < 0 and current >= stop - 1e-12)):
            values.append(round(current, 12))
            current += step
        return values or None

    @staticmethod
    def _sweep_kind(component: str, parameter: str) -> str:
        component_type = component_type_for_component(component)
        param = parameter.strip().lower()
        if component_type in {"lasercw", "laser"} and param == "power":
            return "tx_power_dbm"
        if component_type == "voa" and param == "outputpower":
            return "rop_dbm"
        return "parameter"

    @staticmethod
    def _int_or_none(value: Any) -> int | None:
        try:
            if value is None:
                return None
            return int(float(value))
        except Exception:
            return None

    @staticmethod
    def _as_flat_array(value: Any) -> list[Any]:
        try:
            arr = np.asarray(value)
            if arr.dtype == object:
                arr = np.array(arr.tolist())
            arr = np.squeeze(arr).reshape(-1)
            return list(arr)
        except Exception:
            return [] if value is None else [value]

    @staticmethod
    def _metric_value(values: list[Any], index: int) -> Any:
        if not values:
            return None
        return values[min(index, len(values) - 1)]

    @staticmethod
    def _workspace_from_outputs(outputs: Any) -> dict[str, Any]:
        if not isinstance(outputs, dict):
            return {}
        workspace = outputs.get("default") or outputs.get("right") or outputs.get("bottom") or outputs.get("info")
        return workspace if isinstance(workspace, dict) else {}

    @staticmethod
    def _float_or_none(value: Any) -> float | None:
        try:
            if value is None:
                return None
            if isinstance(value, (list, tuple)) and value:
                value = value[0]
            return float(value)
        except Exception:
            return None

    @staticmethod
    def _format_number(value: float) -> str:
        if abs(value - round(value)) < 1e-12:
            return str(int(round(value)))
        return f"{value:.12g}"

    def _close_hidden_matlab_figures(self, eng) -> None:
        """Prevent MATLAB plotting code from accumulating invisible figures."""
        try:
            eng.eval("close all hidden;", nargout=0)
        except Exception:
            pass

    def _clear_matlab_workspace_cache(self, eng) -> None:
        """Release full per-node MATLAB workspaces after Python has summaries."""
        try:
            eng.feval("OC_GUI_RunWorkspaceComponent", "__clear_cache__", "", {}, {}, {}, nargout=0)
        except Exception:
            pass

    def _delete_matlab_workspace_cache_ref(self, eng, node_id: int, component_name: str) -> None:
        try:
            ref = self._workspace_ref_for_node(node_id, component_name)
            eng.feval("OC_GUI_RunWorkspaceComponent", "__delete_cache__", ref, {}, {}, {}, nargout=0)
        except Exception:
            pass

    @staticmethod
    def _workspace_ref_for_node(node_id: int, component_name: str) -> str:
        component = re.sub(r"[^a-zA-Z0-9]", "", str(component_name)).lower() or "node"
        return f"node_{int(node_id)}_{component}"

    def _cleanup_matlab_after_run(self, eng) -> None:
        """Release MATLAB-side temporary data while keeping Python summaries."""
        before_memory_mb = self._matlab_memory_mb(eng)
        self._clear_matlab_workspace_cache(eng)
        self._close_hidden_matlab_figures(eng)
        for command in (
            "clearvars;",
            "if usejava('jvm'), java.lang.System.gc(); end",
            "drawnow;",
        ):
            try:
                eng.eval(command, nargout=0)
            except Exception:
                pass
        gc.collect()
        after_memory_mb = self._matlab_memory_mb(eng)
        if before_memory_mb is not None and after_memory_mb is not None:
            delta = after_memory_mb - before_memory_mb
            if delta > 512:
                self.log(f"MATLAB 内存清理后仍增长 {delta:.1f} MB", "INFO")

    def _matlab_memory_mb(self, eng) -> float | None:
        try:
            pid = int(float(eng.eval("feature('getpid')", nargout=1)))
            result = subprocess.run(
                ["ps", "-o", "rss=", "-p", str(pid)],
                check=False,
                capture_output=True,
                text=True,
                timeout=2,
            )
            if result.returncode != 0 or not result.stdout.strip():
                return None
            rss_kb = float(result.stdout.strip().splitlines()[0].strip())
            return rss_kb / 1024.0
        except Exception:
            return None

    def _log_workspace_status(self, node: Node, workspace: dict[str, Any]) -> None:
        status = workspace.get("Status")
        if not status:
            return
        parts = [f"{node.name}: {status}"]
        if workspace.get("WaitingFor"):
            parts.append(f"waiting_for={workspace['WaitingFor']}")
        if workspace.get("Error"):
            parts.append(f"error={workspace['Error']}")
        self.log("; ".join(parts), "MATLAB")

    def _log_final_metrics(self, outputs: dict[int, dict[str, Any]], topology: dict[str, Any]) -> None:
        nodes = topology.get("nodes", [])
        names = {int(n["id"]): str(n.get("name", "")) for n in nodes}
        display_names = build_component_display_names(nodes)
        rows: list[str] = []
        for node_id, node_outputs in outputs.items():
            if not isinstance(node_id, int):
                continue
            component_name = names.get(node_id, "")
            if not result_component_allowed(component_name):
                continue
            workspace = self._workspace_from_outputs(node_outputs)
            if not workspace or ("SNR" not in workspace and "BER" not in workspace):
                continue
            snr_values = self._as_flat_array(workspace.get("SNR"))
            ber_values = self._as_flat_array(workspace.get("BER"))
            metric_count = max(len(snr_values), len(ber_values), 1)
            display_name = display_names.get(node_id, component_name)
            for idx in range(metric_count):
                suffix = f" ONU {idx + 1}" if metric_count > 1 else ""
                snr = self._metric_value(snr_values, idx)
                ber = self._metric_value(ber_values, idx)
                rows.append(f"{display_name}{suffix}: SNR={self._format_metric(snr)} dB, BER={self._format_metric(ber)}")
        if rows:
            self.log("最终 BER/SNR:", "MATLAB")
            for row in rows:
                self.log(f"  {row}", "MATLAB")

    @staticmethod
    def _format_metric(value: Any) -> str:
        if value is None:
            return "-"
        try:
            return f"{float(np.real(value)):.6g}"
        except Exception:
            return str(value)

    def _build_node_contexts(self, executor: TopologyExecutor) -> dict[int, dict[str, Any]]:
        """Assign per-type indices and topology metadata to every node."""
        _, indegree, incoming_edges, outgoing_edges = executor._build_graph()

        component_types = {
            node_id: component_type_for_component(node.name)
            for node_id, node in executor.nodes.items()
        }

        type_counts: dict[str, int] = {}
        for component_type in component_types.values():
            type_counts[component_type] = type_counts.get(component_type, 0) + 1

        downstream_tx_bands = self._configured_tx_bands(
            executor,
            component_types,
            tx_type="olttxdsp",
            rx_fallback_count=type_counts.get("onurxdsp", 0),
        )
        upstream_tx_bands = self._configured_tx_bands(
            executor,
            component_types,
            tx_type="onutxdsp",
            rx_fallback_count=type_counts.get("oltrxdsp", 0),
        )

        running_index: dict[str, int] = {}
        type_indices: dict[int, int] = {}
        contexts: dict[int, dict[str, Any]] = {}

        for node_id in sorted(executor.nodes):
            component_type = component_types[node_id]
            running_index[component_type] = running_index.get(component_type, 0) + 1
            type_indices[node_id] = running_index[component_type]

        for node_id in sorted(executor.nodes):
            node = executor.nodes[node_id]
            component_type = component_types[node_id]
            downstream_rx = self._first_downstream_rx(
                node_id,
                component_types,
                type_indices,
                outgoing_edges,
            )

            contexts[node_id] = {
                "node_id": node_id,
                "component_name": node.name,
                "component_type": component_type,
                "type_index": type_indices[node_id],
                "type_count": type_counts[component_type],
                "tx_count": sum(1 for t in component_types.values() if "txdsp" in t),
                "rx_count": sum(1 for t in component_types.values() if "rxdsp" in t),
                "olttxdsp_count": type_counts.get("olttxdsp", 0),
                "onutxdsp_count": type_counts.get("onutxdsp", 0),
                "oltrxdsp_count": type_counts.get("oltrxdsp", 0),
                "onurxdsp_count": type_counts.get("onurxdsp", 0),
                "downstream_tx_bands": downstream_tx_bands,
                "upstream_tx_bands": upstream_tx_bands,
                "is_source": indegree[node_id] == 0,
                "is_sink": len(outgoing_edges.get(node_id, [])) == 0,
                "incoming_ports": [edge.target_side for edge in incoming_edges.get(node_id, [])],
                "outgoing_ports": [edge.source_side for edge in outgoing_edges.get(node_id, [])],
                "downstream_rx_type": downstream_rx[0],
                "downstream_rx_index": downstream_rx[1],
                "downstream_rx_count": downstream_rx[2],
            }

        return contexts

    def _configured_tx_bands(
        self,
        executor: TopologyExecutor,
        component_types: dict[int, str],
        tx_type: str,
        rx_fallback_count: int,
    ) -> int:
        """Return the explicitly configured Tx subcarrier count for a direction."""
        tx_nodes = [
            node
            for node_id, node in executor.nodes.items()
            if component_types.get(node_id) == tx_type
        ]
        for node in tx_nodes:
            value = self._param_value((node.params or {}).get("NumBands"))
            if isinstance(value, (int, float)) and value > 0:
                return max(1, int(round(value)))
        if tx_type == "olttxdsp":
            return 4
        return max(1, int(round(rx_fallback_count or 1)))

    def _first_downstream_rx(
        self,
        node_id: int,
        component_types: dict[int, str],
        type_indices: dict[int, int],
        outgoing_edges: dict[int, list],
    ) -> tuple[str, int, int]:
        """Find the nearest downstream RxDSP so MATLAB can tune LO like the DEMO."""
        queue = [edge.target_id for edge in outgoing_edges.get(node_id, [])]
        seen: set[int] = set()
        rx_matches: list[int] = []

        while queue and not rx_matches:
            next_queue: list[int] = []
            for current in queue:
                if current in seen:
                    continue
                seen.add(current)
                component_type = component_types.get(current, "")
                if "rxdsp" in component_type:
                    rx_matches.append(current)
                else:
                    next_queue.extend(edge.target_id for edge in outgoing_edges.get(current, []))
            queue = next_queue

        if len(rx_matches) == 1:
            rx_id = rx_matches[0]
            rx_type = component_types[rx_id]
            rx_count = sum(1 for t in component_types.values() if t == rx_type)
            return rx_type, type_indices[rx_id], rx_count

        return "", 0, 0

    def _log_params(self, node: Node) -> None:
        params = node.params or {}
        if not params:
            self.log("  Parameters: <none>", "MATLAB")
            return

        self.log("  Parameters:", "MATLAB")
        for key, value in params.items():
            self.log(f"    {key} = {self._param_value(value)}", "MATLAB")

    def _to_matlab_inputs(self, inputs_by_port: dict[str, Any]) -> dict[str, Any]:
        return {
            key: value
            for key, value in inputs_by_port.items()
            if not key.startswith("__")
        }

    def _to_matlab_params(self, params: dict[str, Any]) -> dict[str, Any]:
        converted: dict[str, Any] = {}
        for key, value in params.items():
            safe_key = self._safe_matlab_field(key)
            converted[safe_key] = self._param_value(value)
        return converted

    @staticmethod
    def _param_value(value: Any) -> Any:
        if isinstance(value, (list, tuple)) and value:
            raw = value[0]
        else:
            raw = value

        if isinstance(raw, str):
            text = raw.strip()
            if text.lower() == "true":
                return True
            if text.lower() == "false":
                return False
            try:
                return float(text)
            except ValueError:
                return text
        return raw

    @staticmethod
    def _safe_matlab_field(name: str) -> str:
        out = []
        for ch in name:
            out.append(ch if ch.isalnum() or ch == "_" else "_")
        field = "".join(out).strip("_")
        if not field:
            field = "Param"
        if field[0].isdigit():
            field = f"p_{field}"
        return field
