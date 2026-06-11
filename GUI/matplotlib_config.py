"""Matplotlib runtime configuration shared by GUI plotting modules."""

from __future__ import annotations

import os
from pathlib import Path

MPL_CACHE = Path(__file__).resolve().parent / ".matplotlib_cache"


def configure_matplotlib_cache() -> None:
    """Ensure Matplotlib cache files are written inside the GUI folder."""
    MPL_CACHE.mkdir(exist_ok=True)
    os.environ.setdefault("MPLCONFIGDIR", str(MPL_CACHE))
    os.environ.setdefault("XDG_CACHE_HOME", str(MPL_CACHE))
