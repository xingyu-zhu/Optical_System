"""Display helpers for topology components and simulation result rows."""

from __future__ import annotations

from typing import Any

from matlab_component_registry import component_type_for_component


RESULT_EXCLUDED_TYPES = {"eanalyzer"}


def build_component_display_names(nodes: list[dict[str, Any]]) -> dict[int, str]:
    """Return labels like 'ONURxDSP 1' while preserving stable node ids."""
    sorted_nodes = sorted(nodes, key=lambda item: int(item.get("id", 0)))
    counters: dict[str, int] = {}
    labels: dict[int, str] = {}
    for node in sorted_nodes:
        node_id = int(node.get("id", 0))
        name = str(node.get("name", "Component"))
        component_type = component_type_for_component(name)
        counters[component_type] = counters.get(component_type, 0) + 1
        labels[node_id] = f"{name} {counters[component_type]}"
    return labels


def result_component_allowed(component_name: str) -> bool:
    """Filter components whose BER/SNR would duplicate receiver DSP results."""
    return component_type_for_component(component_name) not in RESULT_EXCLUDED_TYPES
