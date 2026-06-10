"""Matlab Engine manager for Python."""

from __future__ import annotations

import os
import platform
import sys
from pathlib import Path
import threading
import json
from typing import Any, Optional


class MatlabEngineManager:
    """Manage a single MATLAB Engine session in Python.

    Features:
    - Lazy start/reuse engine instance.
    - Thread-safe start/stop access.
    - Helper wrappers for eval/feval/workspace.
    - Context-manager support.
    """

    def __init__(self) -> None:
        self._engine = None
        self._lock = threading.RLock()
        self._manual_matlab_root: Path | None = None

    @property
    def engine(self):
        """Return current engine instance, or None if not started."""
        return self._engine

    def is_running(self) -> bool:
        """Check whether engine has been started."""
        return self._engine is not None

    def start(self, connect_existing: bool = False, shared_name: Optional[str] = None):
        """Start MATLAB Engine or connect to an existing shared session."""
        with self._lock:
            if self._engine is not None:
                self._configure_project_paths()
                return self._engine

            self._configure_engine_python_path()

            try:
                import matlab.engine
            except Exception as exc:
                raise RuntimeError(
                    self._engine_import_error_message(exc)
                ) from exc

            if connect_existing:
                try:
                    names = matlab.engine.find_matlab()
                    if shared_name:
                        if shared_name in names:
                            self._engine = matlab.engine.connect_matlab(shared_name)
                            self._configure_project_paths()
                            return self._engine
                    elif names:
                        self._engine = matlab.engine.connect_matlab(names[0])
                        self._configure_project_paths()
                        return self._engine
                except Exception:
                    pass

            self._engine = matlab.engine.start_matlab()
            self._configure_project_paths()
            return self._engine

    def _configure_engine_python_path(self) -> None:
        """Add MATLAB Engine package paths across macOS, Windows, and Linux.

        The preferred deployment path is still installing MATLAB Engine into the
        active Python environment. This fallback helps local/packaged runs find
        the engine when MATLAB is installed but the package is not on sys.path.
        """
        roots = self._matlab_root_candidates()
        self._configure_windows_runtime_paths(roots)
        candidates = self._matlab_engine_path_candidates_for_roots(roots)
        for path in candidates:
            if path.exists():
                text = str(path)
                if text not in sys.path:
                    sys.path.insert(0, text)
                return

    def _matlab_engine_path_candidates(self) -> list[Path]:
        return self._matlab_engine_path_candidates_for_roots(self._matlab_root_candidates())

    def _matlab_engine_path_candidates_for_roots(self, roots: list[Path]) -> list[Path]:
        paths: list[Path] = []
        for root in roots:
            engine_dir = root / "extern" / "engines" / "python"
            paths.extend(
                [
                    engine_dir / "dist",
                    engine_dir,
                ]
            )
        return self._unique_existing_or_possible_paths(paths)

    def _matlab_root_candidates(self) -> list[Path]:
        roots: list[Path] = []

        configured = self._configured_matlab_root()
        if configured is not None:
            roots.append(configured)

        if self._manual_matlab_root is not None:
            roots.append(self._manual_matlab_root)

        for env_name in ("MATLABROOT", "MATLAB_ROOT"):
            value = os.environ.get(env_name)
            if value:
                roots.append(Path(value))

        system = platform.system().lower()
        if system == "darwin":
            roots.extend(Path("/Applications").glob("MATLAB_R*.app"))
        elif system == "windows":
            program_dirs = [
                os.environ.get("ProgramFiles"),
                os.environ.get("ProgramFiles(x86)"),
            ]
            for base in program_dirs:
                if not base:
                    continue
                matlab_dir = Path(base) / "MATLAB"
                if matlab_dir.exists():
                    roots.extend(matlab_dir.glob("R*"))
        else:
            for base in (Path("/usr/local/MATLAB"), Path("/opt/MATLAB")):
                if base.exists():
                    roots.extend(base.glob("R*"))

        return self._sort_matlab_roots(roots)

    def set_matlab_root(self, selected_path: str | Path, persist: bool = True) -> Path:
        """Set a user-selected MATLAB root or Engine folder.

        Accepts any of:
        - MATLAB root, e.g. C:\\Program Files\\MATLAB\\R2026a
        - MATLAB.app root on macOS
        - extern/engines/python
        - extern/engines/python/dist
        """
        root = self._normalize_matlab_root(Path(selected_path))
        if root is None:
            raise ValueError(
                "所选目录不是有效的 MATLAB 安装目录或 MATLAB Engine Python 目录。"
            )
        self._manual_matlab_root = root
        if persist:
            self._save_configured_matlab_root(root)
        self._configure_engine_python_path()
        return root

    def _normalize_matlab_root(self, path: Path) -> Path | None:
        try:
            path = path.expanduser().resolve()
        except Exception:
            path = Path(path)

        candidates = [path]
        if path.name.lower() == "dist":
            candidates.append(path.parents[3] if len(path.parents) >= 4 else path)
        if path.name.lower() == "python" and path.parent.name.lower() == "engines":
            candidates.append(path.parents[2])

        for candidate in candidates:
            if self._looks_like_matlab_root(candidate):
                return candidate
        return None

    @staticmethod
    def _looks_like_matlab_root(path: Path) -> bool:
        engine_dir = path / "extern" / "engines" / "python"
        return engine_dir.exists() or (engine_dir / "dist").exists()

    def _configured_matlab_root(self) -> Path | None:
        config_path = self._config_path()
        if not config_path.exists():
            return None
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            value = data.get("matlab_root")
            if not value:
                return None
            root = self._normalize_matlab_root(Path(value))
            return root
        except Exception:
            return None

    def _save_configured_matlab_root(self, root: Path) -> None:
        config_path = self._config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump({"matlab_root": str(root)}, f, ensure_ascii=False, indent=2)

    @staticmethod
    def _config_path() -> Path:
        if platform.system().lower() == "windows":
            base = os.environ.get("APPDATA")
            root = Path(base) if base else Path.home() / "AppData" / "Roaming"
        elif platform.system().lower() == "darwin":
            root = Path.home() / "Library" / "Application Support"
        else:
            root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        return root / "OpticalSystemGUI" / "matlab_engine.json"

    @staticmethod
    def _sort_matlab_roots(roots: list[Path]) -> list[Path]:
        unique = []
        seen: set[str] = set()
        for root in roots:
            try:
                resolved = str(root.expanduser().resolve())
            except Exception:
                resolved = str(root)
            if resolved in seen:
                continue
            seen.add(resolved)
            unique.append(Path(resolved))
        return sorted(unique, key=lambda path: path.name, reverse=True)

    @staticmethod
    def _unique_existing_or_possible_paths(paths: list[Path]) -> list[Path]:
        unique = []
        seen: set[str] = set()
        for path in paths:
            text = str(path)
            if text in seen:
                continue
            seen.add(text)
            unique.append(path)
        return unique

    def _configure_windows_runtime_paths(self, roots: list[Path]) -> None:
        if platform.system().lower() != "windows":
            return

        runtime_dirs: list[Path] = []
        for root in roots:
            runtime_dirs.extend(
                [
                    root / "bin" / "win64",
                    root / "extern" / "bin" / "win64",
                    root / "runtime" / "win64",
                ]
            )

        path_parts = os.environ.get("PATH", "").split(os.pathsep)
        for runtime_dir in runtime_dirs:
            if not runtime_dir.exists():
                continue
            text = str(runtime_dir)
            if hasattr(os, "add_dll_directory"):
                try:
                    os.add_dll_directory(text)
                except Exception:
                    pass
            if text not in path_parts:
                path_parts.insert(0, text)
        os.environ["PATH"] = os.pathsep.join(path_parts)

    def _engine_import_error_message(self, original_error: Exception | None = None) -> str:
        roots = self._matlab_root_candidates()
        candidates = self._matlab_engine_path_candidates()
        existing = [str(path) for path in candidates if path.exists()]
        root_text = ", ".join(str(root) for root in roots) if roots else "未检测到 MATLAB 安装目录"
        path_text = ", ".join(existing) if existing else "未检测到可用的 MATLAB Engine Python 路径"
        detail = f"\n原始错误: {type(original_error).__name__}: {original_error}" if original_error else ""
        return (
            "Unable to import matlab.engine. 请先安装与当前 Python 版本兼容的 MATLAB Engine for Python。\n"
            f"检测到的 MATLAB 根目录: {root_text}\n"
            f"检测到的 Engine 路径: {path_text}\n"
            "安装方式示例: cd <MATLABROOT>/extern/engines/python && python -m pip install ."
            f"{detail}"
        )

    def _configure_project_paths(self) -> None:
        """Add the local PON component library and keep MATLAB plots headless."""
        if self._engine is None:
            return

        pon_dir = Path(__file__).resolve().parent / "PON"
        if not pon_dir.exists():
            return

        try:
            self._engine.addpath(self._engine.genpath(str(pon_dir)), nargout=0)
            self._engine.eval("set(0, 'DefaultFigureVisible', 'off');", nargout=0)
        except Exception:
            # Path setup should not prevent the engine from starting.
            pass

    def stop(self) -> None:
        """Stop current MATLAB Engine session if running."""
        with self._lock:
            if self._engine is not None:
                engine = self._engine
                self._engine = None
                engine.quit()

    def eval(self, command: str, nargout: int = 0, **kwargs: Any) -> Any:
        """Execute a MATLAB command string via eval."""
        with self._lock:
            eng = self.start()
            return eng.eval(command, nargout=nargout, **kwargs)

    def feval(self, func_name: str, *args: Any, nargout: int = 1, **kwargs: Any) -> Any:
        """Call a MATLAB function by name."""
        with self._lock:
            eng = self.start()
            return eng.feval(func_name, *args, nargout=nargout, **kwargs)

    def put(self, var_name: str, value: Any) -> None:
        """Put a Python value into MATLAB workspace."""
        with self._lock:
            eng = self.start()
            eng.workspace[var_name] = value

    def get(self, var_name: str) -> Any:
        """Get a variable from MATLAB workspace."""
        with self._lock:
            eng = self.start()
            return eng.workspace[var_name]

    def __enter__(self) -> "MatlabEngineManager":
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.stop()
