"""Offline tests for diagnostics, preflight, caching, checkpoint, and export."""

from __future__ import annotations

import json
import sys
import tempfile
import types
import unittest
import zipfile
from pathlib import Path

from matlab_engine_manager import MatlabEngineManager
from matlab_topology_runner import MatlabTopologyRunner
from measured_bandwidth_dialog import _preview_samples
from measurement_dataset import MeasurementDatasetCatalog
from simulation_artifacts import SweepCheckpoint, topology_signature, write_csv, write_xlsx
from simulation_preflight import run_preflight
from topology_display import build_component_display_names
from topology_executor import TopologyExecutor
from topology_executor import Node


class NewFeatureTests(unittest.TestCase):
    def test_compact_component_names_follow_per_type_order(self):
        names = build_component_display_names(
            [
                {"id": 4, "name": "ONURxDSP"},
                {"id": 2, "name": "ONURxDSP"},
                {"id": 3, "name": "LaserCW"},
            ],
            separator="",
        )
        self.assertEqual(names, {2: "ONURxDSP1", 3: "LaserCW1", 4: "ONURxDSP2"})

    def test_component_status_log_uses_numbered_display_name(self):
        messages = []
        runner = MatlabTopologyRunner(
            MatlabEngineManager(),
            log=lambda message, source: messages.append((message, source)),
        )
        runner._log_workspace_status(
            Node(node_id=7, name="ONURxDSP"),
            {"Status": "called"},
            "ONURxDSP2",
        )
        self.assertEqual(messages, [("组件 ONURxDSP2 已正确运行", "MATLAB")])

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

    def test_frozen_app_adds_detected_external_engine_path(self):
        manager = MatlabEngineManager()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            engine_path = root / "extern" / "engines" / "python" / "dist"
            (engine_path / "matlab" / "engine").mkdir(parents=True)
            manager._preferred_matlab_root = lambda: root
            had_frozen = hasattr(sys, "frozen")
            original_frozen = getattr(sys, "frozen", None)
            sys.frozen = True
            try:
                manager._configure_preferred_engine_import_path()
                self.assertEqual(Path(sys.path[0]), engine_path)
            finally:
                sys.path[:] = [item for item in sys.path if item != str(engine_path)]
                if had_frozen:
                    sys.frozen = original_frozen
                else:
                    del sys.frozen

    def test_complete_matlab_engine_import_is_preserved_on_path_reselection(self):
        module_names = ("matlab", "matlab.engine", "matlab.engine.future")
        originals = {name: sys.modules.get(name) for name in module_names}
        matlab_module = types.ModuleType("matlab")
        engine_module = types.ModuleType("matlab.engine")
        future_module = types.ModuleType("matlab.engine.future")
        engine_module.start_matlab = lambda: None
        engine_module.connect_matlab = lambda: None
        engine_module.TimeoutError = TimeoutError
        engine_module.CancelledError = RuntimeError
        sys.modules["matlab"] = matlab_module
        sys.modules["matlab.engine"] = engine_module
        sys.modules["matlab.engine.future"] = future_module
        try:
            MatlabEngineManager._clear_partial_matlab_imports()
            self.assertIs(sys.modules["matlab.engine"], engine_module)
            self.assertIs(sys.modules["matlab.engine.future"], future_module)
        finally:
            for name in module_names:
                if originals[name] is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = originals[name]

    def test_incomplete_matlab_engine_import_is_removed_before_retry(self):
        module_names = ("matlab", "matlab.engine", "matlab.engine.future")
        originals = {name: sys.modules.get(name) for name in module_names}
        for name in module_names:
            sys.modules[name] = types.ModuleType(name)
        try:
            MatlabEngineManager._clear_partial_matlab_imports()
            self.assertTrue(all(name not in sys.modules for name in module_names))
        finally:
            for name in module_names:
                if originals[name] is not None:
                    sys.modules[name] = originals[name]

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

    def test_measured_dataset_is_transactional_and_preflight_validates_it(self):
        rows = "frequency,response\n0,0\n1,-0.2\n2,-0.5\n3,-3.2\n"
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source_files = []
            for lane in ("XI", "XQ", "YI", "YQ"):
                path = root / f"{lane}.csv"
                path.write_text(rows, encoding="utf-8")
                source_files.append(path)
            catalog = MeasurementDatasetCatalog(root / "catalog")
            prepared = catalog.prepare_import(
                "receiver-test", "receiver", source_files, frequency_unit="GHz"
            )
            self.assertFalse(catalog.exists(prepared["id"]))
            catalog.commit(prepared)
            self.assertTrue(catalog.exists(prepared["id"]))
            topology = {
                "nodes": [
                    {
                        "id": 1,
                        "name": "ICR",
                        "model_config": {
                            "BandwidthModel": "Measured",
                            "BandwidthDataset": prepared["id"],
                        },
                    }
                ],
                "edges": [],
            }
            self.assertTrue(run_preflight(topology, dataset_catalog=catalog).ok)
            topology["nodes"][0]["model_config"]["BandwidthDataset"] = "missing"
            self.assertFalse(run_preflight(topology, dataset_catalog=catalog).ok)

    def test_topology_executor_keeps_model_config_separate_from_params(self):
        topology = {
            "nodes": [
                {
                    "id": 1,
                    "name": "Modulator",
                    "params": {"Bandwidth": ["35", "GHz", ""]},
                    "model_config": {
                        "BandwidthModel": "Measured",
                        "BandwidthDataset": "dataset-id",
                    },
                }
            ],
            "edges": [],
        }
        node = TopologyExecutor(topology).nodes[1]
        self.assertEqual(node.params["Bandwidth"][0], "35")
        self.assertEqual(node.model_config["BandwidthDataset"], "dataset-id")

    def test_startup_page_uses_colored_indeterminate_progress_bar(self):
        source = (Path(__file__).parent / "run_gui.py").read_text(encoding="utf-8")
        self.assertIn("QProgressBar", source)
        self.assertIn("setRange(0, 0)", source)
        self.assertIn("startupProgress", source)
        self.assertIn("qlineargradient", source)
        self.assertIn("status_label", source)

    def test_workspace_supports_plain_backspace_delete(self):
        source = (Path(__file__).parent / "workspace_panel.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("event.key() in (Qt.Key_Delete, Qt.Key_Backspace)", source)

    def test_measurement_preview_is_threaded_and_plot_is_bounded(self):
        source = (Path(__file__).parent / "measured_bandwidth_dialog.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("class MeasurementImportWorker(QThread)", source)
        self.assertIn("self._import_worker.start()", source)
        self.assertIn("setRange(0, 0)", source)
        frequency, magnitude = _preview_samples(range(10000), range(10000))
        self.assertEqual(len(frequency), 4000)
        self.assertEqual(len(magnitude), 4000)


if __name__ == "__main__":
    unittest.main()
