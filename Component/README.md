# MATLAB Component Library

This folder contains the MATLAB functions used by the Python GUI simulation runner.

## Runtime entry point

The GUI calls `GUI_RunWorkspaceComponent.m` for every topology node. Component
names are mapped to MATLAB functions in `GUI/matlab_component_registry.py`.

## External MATLAB file component

The GUI includes a `MatlabFile` component for calling user-provided `.m` files.
Set `MatlabFile` to the external file path, or set `FunctionName` directly if
the function is already on the MATLAB path.

Legacy function signature:

```matlab
function out = my_custom_component(ws, Params, guiParams, context)
```

You can also put a call expression in `FunctionName`:

```matlab
[out_a, out_b]=your_function(arg_a, arg_b)
```

This is a template: replace `your_function` with the exact function name in
the selected `.m` file, replace `arg_a`/`arg_b` with parameters or upstream
workspace fields, and replace `out_a`/`out_b` with the output names you want to
pass downstream. Arguments are resolved from inherited upstream `Params`, GUI
parameters, then upstream workspace fields. Named outputs become workspace
fields for downstream components, and the arguments resolved from parameters are
stored in `ExternalCallParams` and merged back into `Params`.

## Kept structure

- Component module files: GUI-facing optical component adapters and simulation modules.
- Helper files: shared DSP/filter/math helpers used by `OC` modules, such as
  `MZMDD`, `Optical90Hybrid`, `PDPIN`, `Model_TIA_Bessel5_v3`, and
  `SimADC_UXR0804A`.

Standalone demos, old non-`OC` component copies, generated images, and one-path
examples were removed because the GUI does not call them.
