"""MATLAB-backed topology runner."""

from __future__ import annotations

from typing import Any, Callable

from matlab_component_registry import component_type_for_component, matlab_function_for_component
from matlab_engine_manager import MatlabEngineManager
from topology_executor import Node, TopologyExecutor


LogCallback = Callable[[str, str], None]


class MatlabTopologyRunner:
    """Run the current GUI topology by dispatching each node to MATLAB."""

    def __init__(self, engine_manager: MatlabEngineManager, log: LogCallback | None = None):
        self.engine_manager = engine_manager
        self.log = log or (lambda _message, _source="INFO": None)

    def run(self, topology: dict[str, Any]) -> dict[int, dict[str, Any]]:
        executor = TopologyExecutor(topology)
        levels = executor.topological_levels()
        node_contexts = self._build_node_contexts(executor)

        self.log("MATLAB topology execution plan:", "INFO")
        for idx, level in enumerate(levels, start=1):
            names = [executor.nodes[nid].name for nid in level]
            self.log(f"L{idx}: {list(zip(level, names))}", "INFO")

        eng = self.engine_manager.start()
        self._clear_matlab_workspace_cache(eng)

        def component_runner(node: Node, inputs_by_port: dict[str, Any]) -> dict[str, Any]:
            ports = sorted(k for k in inputs_by_port.keys() if not k.startswith("__"))
            function_name = matlab_function_for_component(node.name)
            node_context = node_contexts[node.node_id]
            self.log(
                (
                    f"MATLAB map node {node.node_id} ({node.name}) "
                    f"[{node_context['component_type']} #{node_context['type_index']}/"
                    f"{node_context['type_count']}] -> {function_name or '<unmapped>'}, inputs={ports}"
                ),
                "MATLAB",
            )
            self._log_params(node)

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
            return {
                "default": result,
                "right": result,
                "bottom": result,
                "info": result,
            }

        try:
            outputs = executor.run(component_runner)
            self.log(f"MATLAB topology run finished. Nodes executed: {len(outputs)}", "MATLAB")
            return outputs
        finally:
            self._clear_matlab_workspace_cache(eng)

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

    def _log_workspace_status(self, node: Node, workspace: dict[str, Any]) -> None:
        status = workspace.get("Status")
        if not status:
            return
        parts = [f"  Node {node.node_id} status: {status}"]
        if workspace.get("WaitingFor"):
            parts.append(f"waiting_for={workspace['WaitingFor']}")
        if workspace.get("Error"):
            parts.append(f"error={workspace['Error']}")
        if workspace.get("MemoryNote"):
            parts.append(str(workspace["MemoryNote"]))
        self.log("; ".join(parts), "MATLAB")

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
