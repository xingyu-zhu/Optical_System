"""Topology execution planner and runner for optical component graphs."""

from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any


@dataclass
class Node:
    node_id: int
    name: str
    icon_path: str = ""
    params: dict[str, Any] | None = None


@dataclass
class Edge:
    source_id: int
    source_side: str
    target_id: int
    target_side: str


class TopologyCycleError(RuntimeError):
    """Raised when topology contains directed cycles."""


class TopologyExecutor:
    """Build execution order from topology and optionally run component callbacks."""

    def __init__(self, topology: dict[str, Any]) -> None:
        self.nodes: dict[int, Node] = {}
        self.edges: list[Edge] = []
        self._parse(topology)

    @classmethod
    def from_json_file(cls, file_path: str | Path) -> "TopologyExecutor":
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return cls(data)

    def _parse(self, topology: dict[str, Any]) -> None:
        for n in topology.get("nodes", []):
            node_id = int(n["id"])
            self.nodes[node_id] = Node(
                node_id=node_id,
                name=str(n.get("name", f"Node{node_id}")),
                icon_path=str(n.get("icon_path", "")),
                params=n.get("params", {}),
            )

        for e in topology.get("edges", []):
            self.edges.append(
                Edge(
                    source_id=int(e["source_id"]),
                    source_side=str(e.get("source_side", "")),
                    target_id=int(e["target_id"]),
                    target_side=str(e.get("target_side", "")),
                )
            )

    def _build_graph(self):
        adjacency: dict[int, list[int]] = defaultdict(list)
        indegree: dict[int, int] = {nid: 0 for nid in self.nodes}
        incoming_edges: dict[int, list[Edge]] = defaultdict(list)
        outgoing_edges: dict[int, list[Edge]] = defaultdict(list)

        for edge in self.edges:
            if edge.source_id not in self.nodes or edge.target_id not in self.nodes:
                raise ValueError(
                    f"Invalid edge {edge.source_id}->{edge.target_id}: missing node"
                )
            adjacency[edge.source_id].append(edge.target_id)
            indegree[edge.target_id] += 1
            incoming_edges[edge.target_id].append(edge)
            outgoing_edges[edge.source_id].append(edge)

        return adjacency, indegree, incoming_edges, outgoing_edges

    def topological_levels(self) -> list[list[int]]:
        """Return execution levels for parallel-safe scheduling.

        Each inner list is a batch that can run in parallel.
        """
        adjacency, indegree, _, _ = self._build_graph()
        q = deque(sorted([nid for nid, d in indegree.items() if d == 0]))
        levels: list[list[int]] = []
        visited = 0

        while q:
            level_size = len(q)
            level: list[int] = []
            for _ in range(level_size):
                u = q.popleft()
                level.append(u)
                visited += 1
                for v in adjacency[u]:
                    indegree[v] -= 1
                    if indegree[v] == 0:
                        q.append(v)
            levels.append(level)

        if visited != len(self.nodes):
            raise TopologyCycleError("Cycle detected in topology; cannot topologically schedule")

        return levels

    def linear_order(self) -> list[int]:
        """Flattened topological order."""
        return [nid for level in self.topological_levels() for nid in level]

    def run(
        self,
        component_runner,
        initial_inputs: dict[int, dict[str, Any]] | None = None,
    ) -> dict[int, dict[str, Any]]:
        """Execute nodes in topological order using a user-supplied runner.

        Args:
            component_runner: callable(node: Node, inputs_by_port: dict[str, Any]) -> dict[str, Any]
            initial_inputs: optional pre-seeded inputs by node id and port name.

        Returns:
            outputs_by_node: node_id -> outputs_by_port
        """
        _, _, incoming_edges, outgoing_edges = self._build_graph()
        levels = self.topological_levels()

        routed_inputs: dict[int, dict[str, Any]] = defaultdict(dict)
        if initial_inputs:
            for nid, port_map in initial_inputs.items():
                routed_inputs[nid].update(port_map)

        outputs_by_node: dict[int, dict[str, Any]] = {}

        for level in levels:
            for node_id in level:
                node = self.nodes[node_id]
                node_inputs = dict(routed_inputs.get(node_id, {}))

                # Optional introspection: include upstream edge metadata.
                node_inputs["__incoming_edges__"] = [
                    {
                        "source_id": e.source_id,
                        "source_side": e.source_side,
                        "target_side": e.target_side,
                    }
                    for e in incoming_edges.get(node_id, [])
                ]

                outputs = component_runner(node, node_inputs) or {}
                if not isinstance(outputs, dict):
                    raise TypeError(f"Runner must return dict, got {type(outputs)} for node {node_id}")
                outputs_by_node[node_id] = outputs

                # Route outputs to downstream targets by matching edge source/target sides.
                # Multiple wires may legally land on the same target port (for example
                # several ONU branches entering one Combiner). Preserve all of them by
                # suffixing repeated target ports instead of overwriting earlier inputs.
                for e in outgoing_edges.get(node_id, []):
                    if e.source_side not in outputs:
                        # Allow generic fallback when component returns one primary output.
                        if "default" in outputs:
                            target_port = self._available_input_port(routed_inputs[e.target_id], e.target_side)
                            routed_inputs[e.target_id][target_port] = outputs["default"]
                        continue
                    target_port = self._available_input_port(routed_inputs[e.target_id], e.target_side)
                    routed_inputs[e.target_id][target_port] = outputs[e.source_side]

        return outputs_by_node

    @staticmethod
    def _available_input_port(port_map: dict[str, Any], requested_port: str) -> str:
        base = requested_port or "input"
        if base not in port_map:
            return base

        index = 2
        while f"{base}_{index}" in port_map:
            index += 1
        return f"{base}_{index}"


def demo_runner(node: Node, inputs_by_port: dict[str, Any]) -> dict[str, Any]:
    """Simple demo runner for dry-run validation without MATLAB."""
    print(f"Running node {node.node_id}: {node.name}")
    print(f"  Inputs: {sorted(k for k in inputs_by_port.keys() if not k.startswith('__'))}")
    return {"default": f"signal_from_{node.name}"}


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Topology execution planner")
    parser.add_argument("topology_json", help="Path to topology json file")
    parser.add_argument("--dry-run", action="store_true", help="Execute using demo runner")
    args = parser.parse_args()

    executor = TopologyExecutor.from_json_file(args.topology_json)
    levels = executor.topological_levels()
    print("Execution levels:")
    for idx, level in enumerate(levels, start=1):
        names = [executor.nodes[nid].name for nid in level]
        print(f"  L{idx}: {list(zip(level, names))}")

    if args.dry_run:
        executor.run(demo_runner)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
