"""PyInstaller hook for MATLAB Engine for Python.

MATLAB Engine imports a Python-version-specific binary module dynamically, for
example ``matlabengineforpython3_10``.  It also reads small package data files
such as ``matlab/engine/_arch.txt`` at runtime.  PyInstaller cannot discover
these reliably from static imports, so we collect them explicitly here.
"""

from __future__ import annotations

import sys

from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs, collect_submodules

_suffix = f"{sys.version_info.major}_{sys.version_info.minor}"

hiddenimports = [
    f"matlabengineforpython{_suffix}",
]

# Keep this broad: MathWorks has changed MATLAB Engine's internal Python package
# layout between releases, while the package size is small compared with MATLAB.
hiddenimports += collect_submodules("matlab")

datas = collect_data_files("matlab", include_py_files=False)
binaries = collect_dynamic_libs("matlab")
