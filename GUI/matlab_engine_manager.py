"""Matlab Engine manager for Python."""

from __future__ import annotations

import sys
from pathlib import Path
import threading
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
                    "Unable to import matlab.engine. Please install MATLAB Engine for Python first."
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
        """Add the bundled MATLAB engine package path when MATLAB is installed locally."""
        candidates = [
            Path("/Applications/MATLAB_R2026a.app/extern/engines/python/dist"),
            Path("/Applications/MATLAB_R2025b.app/extern/engines/python/dist"),
            Path("/Applications/MATLAB_R2025a.app/extern/engines/python/dist"),
        ]
        for path in candidates:
            if path.exists():
                text = str(path)
                if text not in sys.path:
                    sys.path.insert(0, text)
                return

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
                self._engine.quit()
                self._engine = None

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
