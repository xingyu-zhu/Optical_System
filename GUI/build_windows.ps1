$ErrorActionPreference = "Stop"

# Run this script from the GUI folder with the packaging virtual environment active.
# Example:
#   cd C:\Users\xingy\Desktop\Optical_System\GUI
#   .\.venv\Scripts\Activate.ps1
#   .\build_windows.ps1

python -c "import matlab.engine; print('MATLAB Engine OK')"

pyinstaller `
  --noconfirm `
  --clean `
  --noupx `
  --windowed `
  --name OpticalSystemGUI `
  --paths "." `
  --additional-hooks-dir "pyinstaller_hooks" `
  --collect-data matlab `
  --collect-binaries matlab `
  --hidden-import pyexpat `
  --hidden-import xml.parsers.expat `
  --hidden-import matlab.engine `
  --hidden-import matlabengineforpython3_10 `
  --hidden-import matplotlib.backends.backend_qt5agg `
  --add-data "..\PON;PON" `
  --add-data "icon;icon" `
  run_gui.py
