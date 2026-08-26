$ErrorActionPreference = "Stop"

# Run this script from the GUI folder with the packaging virtual environment active.
# Example:
#   cd C:\Users\xingy\Desktop\Optical_System\GUI
#   .\.venv\Scripts\Activate.ps1
#   .\build_windows.ps1

python -c "from matlab_engine_manager import MatlabEngineManager; manager = MatlabEngineManager(); manager._configure_engine_python_path(); import matlab.engine; print('MATLAB Engine OK:', manager.preferred_matlab_root)"

$PythonPrefix = python -c "import sys; print(sys.prefix)"
$PyInstallerArgs = @(
  "--noconfirm",
  "--clean",
  "--noupx",
  "--windowed",
  "--name", "OpticalSystemGUI",
  "--paths", ".",
  "--hidden-import", "pyexpat",
  "--hidden-import", "xml.parsers.expat",
  "--exclude-module", "matlab",
  "--hidden-import", "matplotlib.backends.backend_qt5agg",
  "--hidden-import", "measurement_dataset",
  "--hidden-import", "measured_bandwidth_dialog",
  "--add-data", "..\Component;Component",
  "--add-data", "icon;icon"
)

$FfiDll = Join-Path $PythonPrefix "Library\bin\ffi.dll"
if (Test-Path -LiteralPath $FfiDll) {
  $PyInstallerArgs += @("--add-binary", "$FfiDll;.")
}

$PyInstallerArgs += "run_gui.py"
pyinstaller @PyInstallerArgs
