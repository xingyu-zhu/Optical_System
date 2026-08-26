"""Thread-safe MATLAB Engine discovery and lifecycle management."""

from __future__ import annotations

import importlib.util
import json
import os
import platform
import re
import sys
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Optional


class MatlabEngineManager:
    """Manage one MATLAB Engine session and protect active simulations."""

    def __init__(self) -> None:
        self._engine = None
        self._lock = threading.RLock()
        self._condition = threading.Condition(self._lock)
        self._manual_matlab_root: Path | None = None
        self._active_leases = 0
        self._stopping = False
        self._owns_engine = False
        self._configured_engine_id: int | None = None
        self._dll_directory_handles: list[Any] = []
        self._dll_directory_paths: set[str] = set()
        self._last_error = ""

    @property
    def engine(self):
        return self._engine

    @property
    def preferred_matlab_root(self) -> Path | None:
        return self._preferred_matlab_root()

    @property
    def owns_engine(self) -> bool:
        return self._owns_engine

    def is_running(self) -> bool:
        return self._engine is not None

    def is_busy(self) -> bool:
        with self._lock:
            return self._active_leases > 0

    def start(self, connect_existing: bool = False, shared_name: Optional[str] = None):
        """Start MATLAB or connect to a shared session."""
        with self._condition:
            while self._stopping:
                self._condition.wait()
            if self._engine is not None:
                self._configure_project_paths()
                return self._engine
            self._configure_engine_python_path()
            try:
                import matlab.engine
            except Exception as first_exc:
                self._clear_partial_matlab_imports()
                self._configure_engine_python_path()
                try:
                    import matlab.engine
                except Exception as exc:
                    self._last_error = self._engine_import_error_message(exc, first_exc)
                    raise RuntimeError(self._last_error) from exc

            if connect_existing:
                try:
                    names = matlab.engine.find_matlab()
                    selected = shared_name if shared_name in names else None
                    if selected is None and not shared_name and names:
                        selected = names[0]
                    if selected:
                        self._engine = matlab.engine.connect_matlab(selected)
                        self._owns_engine = False
                        return self._finalize_started_engine()
                except Exception as exc:
                    self._last_error = f"连接共享 MATLAB 会话失败: {exc}"
                    if shared_name:
                        raise RuntimeError(self._last_error) from exc

            self._engine = matlab.engine.start_matlab()
            self._owns_engine = True
            return self._finalize_started_engine()

    @contextmanager
    def session(self) -> Iterator[Any]:
        """Lease the engine so disconnect/shutdown waits for active work."""
        with self._condition:
            engine = self.start()
            self._active_leases += 1
        try:
            yield engine
        finally:
            with self._condition:
                self._active_leases = max(0, self._active_leases - 1)
                self._condition.notify_all()

    def stop(self, wait: bool = True, timeout: float = 30.0) -> None:
        """Release the current engine; shared sessions are never quit."""
        with self._condition:
            if self._engine is None:
                return
            if self._active_leases and not wait:
                raise RuntimeError("MATLAB 正在执行仿真，当前不能断开连接。")
            self._stopping = True
            deadline = time.monotonic() + max(0.0, timeout)
            while self._active_leases:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    self._stopping = False
                    self._condition.notify_all()
                    raise TimeoutError("等待 MATLAB 仿真结束超时，未断开引擎。")
                self._condition.wait(min(0.25, remaining))
            engine, owns = self._engine, self._owns_engine
            self._engine = None
            self._owns_engine = False
            self._configured_engine_id = None
        try:
            if owns:
                engine.quit()
        finally:
            with self._condition:
                self._stopping = False
                self._condition.notify_all()

    def cleanup_workspace(self) -> None:
        if not self.is_running():
            return
        with self.session() as eng:
            try:
                eng.eval("clear GUI_RunWorkspaceComponent; close all force; drawnow;", nargout=0)
            except Exception:
                pass

    def diagnostics(self) -> dict[str, Any]:
        if not self.is_running():
            self._configure_engine_python_path()
        roots = self._matlab_root_candidates()
        paths = self._matlab_engine_path_candidates_for_roots(roots)
        info: dict[str, Any] = {
            "platform": platform.platform(),
            "python": sys.executable,
            "python_version": sys.version.split()[0],
            "frozen": bool(getattr(sys, "frozen", False)),
            "preferred_root": str(self._preferred_matlab_root() or ""),
            "detected_roots": [str(path) for path in roots],
            "engine_paths": [str(path) for path in paths if path.exists()],
            "engine_running": self.is_running(),
            "engine_owned": self._owns_engine,
            "engine_busy": self.is_busy(),
            "last_error": self._last_error,
        }
        try:
            info["engine_importable"] = importlib.util.find_spec("matlab.engine") is not None
        except Exception:
            info["engine_importable"] = False
        if self.is_running():
            with self.session() as eng:
                try:
                    info["runtime_root"] = str(eng.matlabroot(nargout=1))
                    info["runtime_version"] = str(eng.version(nargout=1))
                except Exception as exc:
                    info["runtime_error"] = str(exc)
        return info

    def _configure_engine_python_path(self) -> None:
        roots = self._matlab_root_candidates()
        self._configure_preferred_engine_import_path()
        self._configure_windows_runtime_paths(roots)
        self._configure_direct_engine_import_path_for_development(roots)

    def _configure_preferred_engine_import_path(self) -> None:
        if getattr(sys, "frozen", False):
            return
        root = self._preferred_matlab_root()
        if root is None:
            return
        for path in self._matlab_engine_path_candidates_for_roots([root]):
            if path.exists() and self._engine_python_path_is_usable(path):
                text = str(path)
                sys.path[:] = [item for item in sys.path if item != text]
                sys.path.insert(0, text)
                self._clear_partial_matlab_imports()
                return

    def _configure_direct_engine_import_path_for_development(self, roots: list[Path]) -> None:
        if os.environ.get("OPTICAL_GUI_ALLOW_DIRECT_MATLAB_ENGINE_IMPORT") != "1":
            return
        if getattr(sys, "frozen", False):
            return
        try:
            if importlib.util.find_spec("matlab.engine") is not None:
                return
        except (ImportError, AttributeError, ValueError):
            pass
        for path in self._matlab_engine_path_candidates_for_roots(roots):
            if path.exists() and self._engine_python_path_is_usable(path):
                if str(path) not in sys.path:
                    sys.path.insert(0, str(path))
                return

    def _matlab_engine_path_candidates(self) -> list[Path]:
        return self._matlab_engine_path_candidates_for_roots(self._matlab_root_candidates())

    @staticmethod
    def _matlab_engine_path_candidates_for_roots(roots: list[Path]) -> list[Path]:
        paths: list[Path] = []
        for root in roots:
            engine_dir = root / "extern" / "engines" / "python"
            paths.extend([engine_dir / "dist", engine_dir])
        return MatlabEngineManager._unique_paths(paths)

    @staticmethod
    def _clear_partial_matlab_imports() -> None:
        for name in list(sys.modules):
            if name == "matlab" or name.startswith("matlab."):
                sys.modules.pop(name, None)

    @staticmethod
    def _engine_python_path_is_usable(path: Path) -> bool:
        engine_pkg = path / "matlab" / "engine"
        if not engine_pkg.exists():
            return False
        arch_file = engine_pkg / "_arch.txt"
        if arch_file.exists():
            try:
                arch_file.read_text(encoding="utf-8")
            except Exception:
                return False
        return True

    def _matlab_root_candidates(self) -> list[Path]:
        preferred: list[Path] = []
        if self._manual_matlab_root is not None:
            preferred.append(self._manual_matlab_root)
        configured = self._configured_matlab_root()
        if configured is not None:
            preferred.append(configured)
        for name in ("MATLABROOT", "MATLAB_ROOT"):
            if os.environ.get(name):
                preferred.append(Path(os.environ[name]))
        return self._unique_matlab_roots(preferred + self._default_matlab_roots())

    def _preferred_matlab_root(self) -> Path | None:
        if self._manual_matlab_root is not None:
            return self._manual_matlab_root
        configured = self._configured_matlab_root()
        if configured is not None:
            return configured
        for name in ("MATLABROOT", "MATLAB_ROOT"):
            value = os.environ.get(name)
            if value:
                root = self._normalize_matlab_root(Path(value))
                if root is not None:
                    return root
        roots = self._default_matlab_roots()
        return roots[0] if roots else None

    def _default_matlab_roots(self) -> list[Path]:
        roots: list[Path] = []
        system = platform.system().lower()
        if system == "darwin":
            roots.extend(Path("/Applications").glob("MATLAB_R*.app"))
        elif system == "windows":
            bases = [Path(r"C:\Program Files"), Path(r"C:\Program Files (x86)")]
            for name in ("ProgramFiles", "ProgramFiles(x86)"):
                if os.environ.get(name):
                    bases.append(Path(os.environ[name]))
            for base in self._unique_paths(bases):
                matlab_dir = base / "MATLAB"
                if matlab_dir.exists():
                    roots.extend(matlab_dir.glob("R*"))
        else:
            for base in (Path("/usr/local/MATLAB"), Path("/opt/MATLAB")):
                if base.exists():
                    roots.extend(base.glob("R*"))
        return self._sort_matlab_roots([root for root in roots if self._looks_like_matlab_root(root)])

    def set_matlab_root(self, selected_path: str | Path, persist: bool = True) -> Path:
        with self._lock:
            root = self._normalize_matlab_root(Path(selected_path))
            if root is None:
                raise ValueError("所选目录不是有效的 MATLAB 安装目录或 Engine Python 目录。")
            if self._engine is not None:
                self.stop()
            self._manual_matlab_root = root
            if persist:
                self._save_configured_matlab_root(root)
            self._clear_partial_matlab_imports()
            self._configure_engine_python_path()
            return root

    def _normalize_matlab_root(self, path: Path) -> Path | None:
        try:
            path = path.expanduser().resolve()
        except Exception:
            path = Path(path)
        candidates = [path]
        parts = [part.lower() for part in path.parts]
        if len(parts) >= 4 and parts[-4:] == ["extern", "engines", "python", "dist"]:
            candidates.append(path.parents[3])
        elif len(parts) >= 3 and parts[-3:] == ["extern", "engines", "python"]:
            candidates.append(path.parents[2])
        return next((item for item in candidates if self._looks_like_matlab_root(item)), None)

    @staticmethod
    def _looks_like_matlab_root(path: Path) -> bool:
        return (path / "extern" / "engines" / "python").exists()

    def _configured_matlab_root(self) -> Path | None:
        path = self._config_path()
        try:
            exists = path.is_file()
        except OSError:
            return None
        if not exists:
            return None
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return self._normalize_matlab_root(Path(data["matlab_root"]))
        except Exception:
            return None

    def _save_configured_matlab_root(self, root: Path) -> None:
        path = self._config_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps({"matlab_root": str(root)}, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(path)

    @staticmethod
    def _config_path() -> Path:
        system = platform.system().lower()
        if system == "windows":
            base = os.environ.get("APPDATA")
            root = Path(base) if base else Path.home() / "AppData" / "Roaming"
        elif system == "darwin":
            root = Path.home() / "Library" / "Application Support"
        else:
            root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        return root / "OpticalSystemGUI" / "matlab_engine.json"

    @staticmethod
    def _release_key(path: Path) -> tuple[int, int, str]:
        match = re.search(r"R(\d{4})([ab])", path.name, re.IGNORECASE)
        if not match:
            return (0, 0, path.name.lower())
        return (int(match.group(1)), int(match.group(2).lower() == "b"), path.name.lower())

    @classmethod
    def _sort_matlab_roots(cls, roots: list[Path]) -> list[Path]:
        return sorted(cls._unique_matlab_roots(roots), key=cls._release_key, reverse=True)

    @staticmethod
    def _unique_matlab_roots(roots: list[Path]) -> list[Path]:
        unique: list[Path] = []
        seen: set[str] = set()
        for root in roots:
            try:
                root = Path(root).expanduser().resolve()
            except Exception:
                root = Path(root)
            key = os.path.normcase(str(root))
            if key not in seen:
                seen.add(key)
                unique.append(root)
        return unique

    @staticmethod
    def _unique_paths(paths: list[Path]) -> list[Path]:
        result: list[Path] = []
        seen: set[str] = set()
        for path in paths:
            key = os.path.normcase(str(path))
            if key not in seen:
                seen.add(key)
                result.append(path)
        return result

    def _configure_windows_runtime_paths(self, roots: list[Path]) -> None:
        if platform.system().lower() != "windows":
            return
        runtime_dirs: list[Path] = []
        for root in roots:
            runtime_dirs.extend([root / "bin" / "win64", root / "extern" / "bin" / "win64", root / "runtime" / "win64"])
        path_parts = os.environ.get("PATH", "").split(os.pathsep)
        for directory in runtime_dirs:
            if not directory.exists():
                continue
            text = str(directory)
            key = os.path.normcase(text)
            if hasattr(os, "add_dll_directory") and key not in self._dll_directory_paths:
                try:
                    self._dll_directory_handles.append(os.add_dll_directory(text))
                    self._dll_directory_paths.add(key)
                except Exception:
                    pass
            if text not in path_parts:
                path_parts.insert(0, text)
        os.environ["PATH"] = os.pathsep.join(path_parts)

    def _engine_import_error_message(self, error: Exception, first_error: Exception) -> str:
        roots = self._matlab_root_candidates()
        paths = [str(path) for path in self._matlab_engine_path_candidates() if path.exists()]
        frozen_note = "\n当前为打包程序；请在打包 Python 环境安装匹配版本的 MATLAB Engine 后重新打包。" if getattr(sys, "frozen", False) else ""
        return (
            "无法导入 matlab.engine。\n"
            f"当前 Python: {sys.executable}\n检测到的 MATLAB: {', '.join(map(str, roots)) or '无'}\n"
            f"检测到的 Engine 路径: {', '.join(paths) or '无'}\n"
            "安装命令: cd <MATLABROOT>/extern/engines/python && python -m pip install ."
            f"{frozen_note}\n首次错误: {first_error}\n重试错误: {error}"
        )

    def _finalize_started_engine(self):
        try:
            self._validate_selected_matlab_root()
            self._configure_project_paths()
            self._last_error = ""
            return self._engine
        except Exception as exc:
            engine, owns = self._engine, self._owns_engine
            self._engine = None
            self._owns_engine = False
            self._configured_engine_id = None
            self._last_error = str(exc)
            if owns and engine is not None:
                try:
                    engine.quit()
                except Exception:
                    pass
            raise

    def _validate_selected_matlab_root(self) -> None:
        if self._engine is None:
            return
        expected = self._preferred_matlab_root()
        if expected is None:
            return
        try:
            actual_text = self._engine.matlabroot(nargout=1)
        except Exception:
            return
        if self._normalize_path_for_compare(Path(str(actual_text))) != self._normalize_path_for_compare(expected):
            raise RuntimeError(
                "MATLAB Engine 版本与选定安装目录不一致。\n"
                f"选定: {expected}\n实际: {actual_text}\n"
                "请从选定版本的 extern/engines/python 重新安装 MATLAB Engine。"
            )

    @staticmethod
    def _normalize_path_for_compare(path: Path) -> str:
        try:
            return os.path.normcase(str(path.expanduser().resolve()))
        except Exception:
            return os.path.normcase(str(path))

    def _configure_project_paths(self) -> None:
        if self._engine is None or self._configured_engine_id == id(self._engine):
            return
        component_dir = self._resolve_component_dir()
        if not component_dir.exists():
            return
        try:
            self._engine.addpath(self._engine.genpath(str(component_dir)), nargout=0)
            self._engine.eval("set(0, 'DefaultFigureVisible', 'off');", nargout=0)
            self._configured_engine_id = id(self._engine)
        except Exception as exc:
            self._last_error = f"配置 Component 路径失败: {exc}"

    @staticmethod
    def _resolve_component_dir() -> Path:
        module_dir = Path(__file__).resolve().parent
        candidates = [module_dir.parent / "Component", module_dir / "Component"]
        if getattr(sys, "frozen", False):
            executable_dir = Path(sys.executable).resolve().parent
            candidates.extend([executable_dir / "Component", Path(getattr(sys, "_MEIPASS", executable_dir)) / "Component"])
        return next((path for path in candidates if path.exists()), candidates[0])

    def eval(self, command: str, nargout: int = 0, **kwargs: Any) -> Any:
        with self.session() as eng:
            return eng.eval(command, nargout=nargout, **kwargs)

    def feval(self, func_name: str, *args: Any, nargout: int = 1, **kwargs: Any) -> Any:
        with self.session() as eng:
            return eng.feval(func_name, *args, nargout=nargout, **kwargs)

    def put(self, var_name: str, value: Any) -> None:
        with self.session() as eng:
            eng.workspace[var_name] = value

    def get(self, var_name: str) -> Any:
        with self.session() as eng:
            return eng.workspace[var_name]

    def __enter__(self) -> "MatlabEngineManager":
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.stop()
