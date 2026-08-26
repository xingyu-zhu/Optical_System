"""Offline tests for diagnostics, preflight, caching, checkpoint, and export."""

from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from matlab_engine_manager import MatlabEngineManager
from simulation_artifacts import SweepCheckpoint, topology_signature, write_csv, write_xlsx
from simulation_preflight import run_preflight
from topology_executor import TopologyExecutor


class NewFeatureTests(unittest.TestCase):
    def test_engine_lease_blocks_disconnect_and_shared_session_is_not_quit(self):
        class FakeEngine:
            def __init__(self):
                self.quit_calls = 0

            def quit(self):
                self.quit_calls += 1

        manager = MatlabEngineManager()
        engine = FakeEngine()
        manager._engine = engine
        manager._owns_engine = False
        with manager.session():
            with self.assertRaises(RuntimeError):
                manager.stop(wait=False)
        manager.stop()
        self.assertEqual(engine.quit_calls, 0)

    def test_failed_engine_validation_quits_owned_session(self):
        class FakeEngine:
            def __init__(self):
                self.quit_calls = 0

            def quit(self):
                self.quit_calls += 1

        manager = MatlabEngineManager()
        engine = FakeEngine()
        manager._engine = engine
        manager._owns_engine = True
        manager._validate_selected_matlab_root = lambda: (_ for _ in ()).throw(RuntimeError("mismatch"))
        with self.assertRaises(RuntimeError):
            manager._finalize_started_engine()
        self.assertEqual(engine.quit_calls, 1)
        self.assertFalse(manager.is_running())

    def test_release_sort_uses_release_semantics(self):
        roots = [Path("MATLAB_R2025b.app"), Path("R2026a"), Path("R2024b")]
        ordered = MatlabEngineManager._sort_matlab_roots(roots)
        self.assertEqual([path.name for path in ordered], ["R2026a", "MATLAB_R2025b.app", "R2024b"])

    def test_executor_reuses_cached_node_and_routes_output(self):
        topology = {
            "nodes": [{"id": 1, "name": "A"}, {"id": 2, "name": "B"}],
            "edges": [{"source_id": 1, "source_side": "right", "target_id": 2, "target_side": "left"}],
        }
        calls = []

        def runner(node, inputs):
            calls.append(node.node_id)
            return {"right": inputs.get("left", 0) + node.node_id}

        outputs = TopologyExecutor(topology).run(
            runner,
            cached_outputs={1: {"right": 10}},
            skip_nodes={1},
        )
        self.assertEqual(calls, [2])
        self.assertEqual(outputs[2]["right"], 12)

    def test_preflight_rejects_cycle_and_bad_sweep(self):
        topology = {
            "nodes": [{"id": 1, "name": "LaserCW"}, {"id": 2, "name": "Fiber"}],
            "edges": [
                {"source_id": 1, "target_id": 2},
                {"source_id": 2, "target_id": 1},
            ],
            "parameter_sweeps": [{"enabled": True, "node_id": 1, "parameter": "Power", "start": 0, "stop": 1, "step": 0}],
        }
        self.assertFalse(run_preflight(topology).ok)

    def test_checkpoint_and_exports(self):
        topology = {"nodes": [{"id": 1, "name": "LaserCW"}], "edges": []}
        rows = [{"point_index": 1, "SNR": 20.5, "label": "测试"}]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            checkpoint = SweepCheckpoint(root / "scan.json", topology_signature(topology))
            checkpoint.save_rows(rows, total_points=2, completed_points=1)
            self.assertEqual(checkpoint.load_rows(), rows)
            data = json.loads(checkpoint.path.read_text(encoding="utf-8"))
            self.assertEqual(data["completed_points"], 1)
            write_csv(root / "result.csv", rows)
            write_xlsx(root / "result.xlsx", {"Sweep": rows})
            self.assertIn("测试", (root / "result.csv").read_text(encoding="utf-8-sig"))
            with zipfile.ZipFile(root / "result.xlsx") as archive:
                self.assertIn("xl/worksheets/sheet1.xml", archive.namelist())


if __name__ == "__main__":
    unittest.main()
