"""Build and run GUI-style uplink topology cases.

Usage:
  python3 uplink_topology_test.py --cases 1 2 4 --plan-only
  python3 uplink_topology_test.py --cases 1 2 4
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from matlab_engine_manager import MatlabEngineManager
from matlab_topology_runner import MatlabTopologyRunner
from topology_executor import TopologyExecutor


def node(
    node_id: int, name: str, params: dict[str, list[str]] | None = None
) -> dict[str, Any]:
    return {
        "id": node_id,
        "name": name,
        "icon_path": "",
        "x": 0,
        "y": 0,
        "params": params or {},
    }


def edge(source_id: int, target_id: int, target_side: str) -> dict[str, Any]:
    return {
        "source_id": source_id,
        "source_side": "default",
        "target_id": target_id,
        "target_side": target_side,
    }


def build_uplink_topology(num_onu: int, target_onu: int) -> dict[str, Any]:
    nodes: list[dict[str, Any]] = []
    edges: list[dict[str, Any]] = []
    next_id = 1
    modulator_ids: list[int] = []

    for _ in range(num_onu):
        txdsp = next_id
        dac = next_id + 1
        driver = next_id + 2
        laser = next_id + 3
        mod = next_id + 4
        next_id += 5

        nodes.extend(
            [
                node(
                    txdsp,
                    "ONUTxDSP",
                    {
                        "TransmitFrequency": ["193.1", "THz", "发射频率"],
                        "BaudRate": ["25", "GBaud", "单 ONU 波特率"],
                        "Modulation": ["QPSK", "", "调制格式"],
                        "SymbolNumber": ["32768", "", "符号数"],
                        "NumBands": ["1", "", "上行固定单子载波"],
                    },
                ),
                node(dac, "DAC"),
                node(driver, "Driver"),
                node(
                    laser,
                    "LaserCW",
                    {
                        "Power": ["13", "dBm", "发射光功率"],
                        "Linewidth": ["100", "kHz", "线宽"],
                    },
                ),
                node(mod, "Modulator"),
            ]
        )
        edges.extend(
            [
                edge(txdsp, dac, "left"),
                edge(dac, driver, "left"),
                edge(driver, mod, "left"),
                edge(laser, mod, "top"),
            ]
        )
        modulator_ids.append(mod)

    combiner = next_id
    fiber = next_id + 1
    oa = next_id + 2
    lo = next_id + 3
    icr = next_id + 4
    tia = next_id + 5
    adc = next_id + 6
    rxdsp = next_id + 7

    nodes.extend(
        [
            node(combiner, "Combiner"),
            node(fiber, "Fiber", {"Length": ["20", "km", "光纤长度"]}),
            node(oa, "OA", {"OutputPower": ["0", "dBm", "输出功率"]}),
            node(
                lo,
                "LO",
                {
                    "Power": ["13", "dBm", "本振光功率"],
                    "Linewidth": ["100", "kHz", "本振线宽"],
                    "FreqOffset": ["0.5", "GHz", "本振频偏"],
                    "Phase": ["0", "deg", "初始相位"],
                    "RIN": ["-150", "dB/Hz", "相对强度噪声"],
                },
            ),
            node(icr, "ICR"),
            node(tia, "TIA"),
            node(adc, "ADC"),
            node(
                rxdsp,
                "OLTRxDSP",
                {
                    "CD_Compensation": ["True", "", "色散补偿"],
                    "Adaptive_EQ": ["True", "", "自适应均衡"],
                    "TargetONU": [str(target_onu), "", "上行目标 ONU 时隙"],
                },
            ),
        ]
    )

    for idx, mod in enumerate(modulator_ids, start=1):
        edges.append(edge(mod, combiner, f"in{idx}"))
    edges.extend(
        [
            edge(combiner, fiber, "left"),
            edge(fiber, oa, "left"),
            edge(oa, icr, "left"),
            edge(lo, icr, "top"),
            edge(icr, tia, "left"),
            edge(tia, adc, "left"),
            edge(adc, rxdsp, "left"),
        ]
    )

    return {"nodes": nodes, "edges": edges}


def summarize_outputs(
    outputs: dict[int, dict[str, Any]], topology: dict[str, Any]
) -> dict[str, Any]:
    names = {int(n["id"]): n["name"] for n in topology["nodes"]}
    rows: list[dict[str, Any]] = []
    for node_id, node_outputs in sorted(outputs.items()):
        workspace = (
            node_outputs.get("default")
            or node_outputs.get("right")
            or node_outputs.get("bottom")
            or {}
        )
        if isinstance(workspace, dict) and ("BER" in workspace or "SNR" in workspace):
            rows.append(
                {
                    "node_id": node_id,
                    "component": names.get(node_id, ""),
                    "SNR": workspace.get("SNR"),
                    "BER": workspace.get("BER"),
                    "Status": workspace.get("Status"),
                }
            )
    return {"rx_results": rows}


def main() -> int:
    parser = argparse.ArgumentParser(description="Run GUI uplink topology test cases")
    parser.add_argument(
        "--cases", nargs="+", type=int, default=[1, 2, 4], help="ONU counts to test"
    )
    parser.add_argument(
        "--target-onu", type=int, default=1, help="Target ONU slot to decode"
    )
    parser.add_argument(
        "--plan-only", action="store_true", help="Only print topology schedule"
    )
    parser.add_argument(
        "--dump-dir",
        type=Path,
        default=None,
        help="Optional directory to write topology JSONs",
    )
    args = parser.parse_args()

    if args.dump_dir:
        args.dump_dir.mkdir(parents=True, exist_ok=True)

    for num_onu in args.cases:
        target_onu = min(max(1, args.target_onu), num_onu)
        topology = build_uplink_topology(num_onu, target_onu)
        if args.dump_dir:
            path = args.dump_dir / f"uplink_{num_onu}onu.json"
            path.write_text(
                json.dumps(topology, ensure_ascii=False, indent=2), encoding="utf-8"
            )

        print(f"\n=== Uplink topology: {num_onu} ONU(s), target ONU {target_onu} ===")
        executor = TopologyExecutor(topology)
        for idx, level in enumerate(executor.topological_levels(), start=1):
            names = [executor.nodes[nid].name for nid in level]
            print(f"L{idx}: {list(zip(level, names))}")

        if args.plan_only:
            continue

        runner = MatlabTopologyRunner(
            MatlabEngineManager(), log=lambda msg, src="INFO": print(f"[{src}] {msg}")
        )
        outputs = runner.run(topology)
        print(
            json.dumps(
                summarize_outputs(outputs, topology),
                ensure_ascii=False,
                indent=2,
                default=str,
            )
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
