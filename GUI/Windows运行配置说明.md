# Windows 新电脑运行配置说明

本文档用于说明在一台新的 Windows 电脑上运行“多维复用超高速光接入端到端系统仿真平台”所需的环境配置、首次启动流程和常见问题处理。

## 1. 适用对象

本说明分为两类使用场景：

- 普通用户：只运行已经打包好的 `OpticalSystemGUI.exe`。
- 开发/打包用户：需要在新电脑上重新安装 Python 环境并重新打包 exe。

如果只是把软件发给别人使用，通常只需要阅读第 2 到第 6 节。

## 2. 运行前需要安装的软件

### 2.1 MATLAB

目标电脑必须安装 MATLAB。

建议版本：

- MATLAB R2024b 或与打包时一致/接近的版本。
- 如果电脑上安装了多个 MATLAB 版本，首次启动软件时请选择希望使用的版本目录。

常见 MATLAB 安装路径示例：

```text
C:\Program Files\MATLAB\R2024b
```

注意：本软件通过 MATLAB Engine 调用 MATLAB，因此目标电脑必须有可用的 MATLAB 授权。

### 2.2 MATLAB Engine for Python

如果使用的是已经打包好的 exe，通常不需要用户手动安装 Python，但建议目标电脑上的 MATLAB 版本与打包时使用的 MATLAB Engine 版本保持一致。

如果 exe 启动时报 `Unable to import matlab.engine`，说明打包时没有正确包含 MATLAB Engine，或者打包环境中的 MATLAB Engine 与 Python 版本不匹配。这种情况需要由开发者重新打包，普通用户通常无法只靠选择 MATLAB 路径解决。

## 3. 应发送给用户的文件

发布给普通用户时，请发送整个打包输出文件夹，而不是只发送单个 exe。

例如发送：

```text
dist\OpticalSystemGUI\
```

该文件夹内通常包括：

```text
OpticalSystemGUI.exe
_internal\
PON\
icon\
```

不要只发送：

```text
OpticalSystemGUI.exe
```

否则可能缺少 Python 运行库、PyQt、Matplotlib、MATLAB Engine 组件、图标或 MATLAB 仿真代码。

不需要发送：

```text
build\
```

`build` 文件夹只是 PyInstaller 的临时构建目录，不是运行软件所需内容。

## 4. 首次启动流程

1. 将 `dist\OpticalSystemGUI` 文件夹复制到目标电脑任意目录。

2. 双击运行：

```text
OpticalSystemGUI.exe
```

3. 如果软件提示选择 MATLAB 路径，请选择 MATLAB 根目录，例如：

```text
C:\Program Files\MATLAB\R2024b
```

4. 软件会记住该路径。下次启动时通常不需要再次选择。

5. 如果需要更换 MATLAB 版本，可以在软件中使用连接/断开 MATLAB 引擎相关按钮，或重新选择 MATLAB 安装路径。

## 5. MATLAB 路径应该选择哪里

请选择 MATLAB 根目录，而不是 MATLAB 的 `bin` 目录。

正确示例：

```text
C:\Program Files\MATLAB\R2024b
```

不建议选择：

```text
C:\Program Files\MATLAB\R2024b\bin
C:\Program Files\MATLAB\R2024b\bin\win64
```

软件也可以识别 MATLAB Engine 的 Python 目录，但普通用户优先选择 MATLAB 根目录即可：

```text
C:\Program Files\MATLAB\R2024b\extern\engines\python
```

## 6. 普通用户常见问题

### 6.1 提示 Unable to import matlab.engine

典型报错：

```text
Unable to import matlab.engine. 请先安装与当前 Python 版本兼容的 MATLAB Engine for Python。
```

可能原因：

- exe 打包时没有正确收集 MATLAB Engine。
- 打包环境中的 MATLAB Engine 没有正确安装。
- MATLAB Engine 与打包使用的 Python 版本不匹配。

处理方式：

- 普通用户：请联系开发者重新打包。
- 开发者：请参考第 7 节重新安装 MATLAB Engine 并重新打包。

### 6.2 提示 No module named 'matlabengineforpython3_10'

典型报错：

```text
No module named 'matlabengineforpython3_10'
```

原因：PyInstaller 没有把 MATLAB Engine 的 Python 版本相关二进制模块打包进去。

处理方式：开发者需要使用项目中的 `build_windows.ps1` 重新打包。

### 6.3 提示找不到 _arch.txt

典型报错：

```text
No such file or directory: ...\_internal\matlab\engine\_arch.txt
```

原因：PyInstaller 没有把 MATLAB Engine 的数据文件打包进去。

处理方式：开发者需要使用项目中的 PyInstaller hook 重新打包。

### 6.4 提示 MATLAB 无法启动或授权失败

可能原因：

- MATLAB 没有安装完整。
- MATLAB 授权不可用。
- 当前 Windows 用户没有权限访问 MATLAB 安装目录。
- MATLAB 首次启动需要完成登录或授权激活。

建议先在目标电脑上单独打开 MATLAB，确认 MATLAB 本身可以正常启动。

## 7. 开发者重新打包流程

以下步骤用于开发者在 Windows 电脑上重新打包 exe。

### 7.1 进入 GUI 项目目录

```powershell
cd C:\Users\xingy\Desktop\Optical_System\GUI
```

### 7.2 创建并启用虚拟环境

如果系统中已经有普通 Python 3.10：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
```

如果 PowerShell 禁止激活脚本，可以临时允许当前窗口执行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\.venv\Scripts\Activate.ps1
```

### 7.3 安装 Python 依赖

```powershell
pip install pyinstaller pyqt5 numpy matplotlib
```

如果项目后续添加了新的依赖，也需要同步安装。

### 7.4 安装 MATLAB Engine for Python

以 MATLAB R2024b 为例：

```powershell
cd "C:\Program Files\MATLAB\R2024b\extern\engines\python"
C:\Users\xingy\Desktop\Optical_System\GUI\.venv\Scripts\python.exe -m pip install .
```

安装后检查：

```powershell
cd C:\Users\xingy\Desktop\Optical_System\GUI
python -c "import matlab.engine; print('MATLAB Engine OK')"
```

如果这里不能输出 `MATLAB Engine OK`，不要继续打包。需要先解决 MATLAB Engine 安装问题。

### 7.5 重新打包

在 GUI 项目目录下运行：

```powershell
cd C:\Users\xingy\Desktop\Optical_System\GUI
.\build_windows.ps1
```

打包完成后，运行文件位于：

```text
dist\OpticalSystemGUI\OpticalSystemGUI.exe
```

发布时发送整个文件夹：

```text
dist\OpticalSystemGUI\
```

## 8. 打包后检查清单

重新打包后，建议检查以下文件是否存在：

```text
dist\OpticalSystemGUI\OpticalSystemGUI.exe
dist\OpticalSystemGUI\_internal\matlab\engine\_arch.txt
dist\OpticalSystemGUI\_internal\matlabengineforpython3_10.pyd
dist\OpticalSystemGUI\PON\
dist\OpticalSystemGUI\icon\
```

如果缺少 `_arch.txt` 或 `matlabengineforpython3_10.pyd`，说明 MATLAB Engine 没有被正确打包。

## 9. 推荐发布流程

1. 在开发电脑上确认 GUI 源码可以正常运行。

2. 确认 MATLAB Engine 在当前 `.venv` 中可导入：

```powershell
python -c "import matlab.engine; print('MATLAB Engine OK')"
```

3. 使用 `build_windows.ps1` 打包。

4. 在本机先运行 `dist\OpticalSystemGUI\OpticalSystemGUI.exe` 测试。

5. 将整个 `dist\OpticalSystemGUI` 文件夹压缩成 zip。

6. 发送 zip 给用户。

7. 用户解压后运行 `OpticalSystemGUI.exe`。

8. 首次启动时选择 MATLAB 安装目录。

## 10. 备注

- MATLAB 本身不建议也不应直接打包进 exe。
- 目标电脑仍需要安装 MATLAB，并拥有可用授权。
- 如果目标电脑没有 MATLAB，本软件无法执行 MATLAB 联合仿真。
- 如果只需要查看 GUI 而不运行仿真，可以后续考虑增加“无 MATLAB 模式”，但当前版本仍以 MATLAB Engine 可用为前提。
