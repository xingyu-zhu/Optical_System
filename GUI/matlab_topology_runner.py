"""MATLAB-backed topology runner."""

from __future__ import annotations

from typing import Any, Callable

from matlab_component_registry import matlab_function_for_component
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

        self.log("MATLAB topology execution plan:", "INFO")
        for idx, level in enumerate(levels, start=1):
            names = [executor.nodes[nid].name for nid in level]
            self.log(f"L{idx}: {list(zip(level, names))}", "INFO")

        eng = self.engine_manager.start()

        def component_runner(node: Node, inputs_by_port: dict[str, Any]) -> dict[str, Any]:
            ports = sorted(k for k in inputs_by_port.keys() if not k.startswith("__"))
            function_name = matlab_function_for_component(node.name)
            self.log(
                f"MATLAB map node {node.node_id} ({node.name}) -> {function_name or '<unmapped>'}, inputs={ports}",
                "MATLAB",
            )

            matlab_inputs = self._to_matlab_inputs(inputs_by_port)
            outputs = eng.feval(
                "GUI_RunMappedComponent",
                node.name,
                function_name,
                matlab_inputs,
                nargout=1,
            )
            result = dict(outputs)
            return {
                "default": result,
                "right": result,
                "bottom": result,
                "info": result,
            }

        outputs = executor.run(component_runner)
        self.log(f"MATLAB topology run finished. Nodes executed: {len(outputs)}", "MATLAB")
        return outputs

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
