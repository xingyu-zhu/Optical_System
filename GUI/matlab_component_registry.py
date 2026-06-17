"""Mapping between GUI component names and MATLAB component functions."""

from __future__ import annotations

COMPONENT_TO_MATLAB_FUNCTION = {
    "olttxdsp": "TxDSP_Module",
    "onutxdsp": "TxDSP_Module_v4_up",
    "txdsp": "TxDSP_Module",
    "dac": "SimDAC_M8196A",
    "driver": "Driver_Module",
    "lasercw": "LaserCW_Module",
    "laser": "LaserCW_Module",
    "lo": "LO_Optical_Module",
    "modulator": "Modulator_Module",
    "oa": "EDFA_Module",
    "edfa": "EDFA_Module",
    "voa": "VOA_Module",
    "polrot": "PolarizationEmulation_Module",
    "rotatepol": "PolarizationEmulation_Module",
    "fiber": "Fiber_Channel",
    "splitter": "Splitter_Module",
    "combiner": "Combiner_Module",
    "icr": "CoherentReceiver_Module",
    "coherentreceiver": "CoherentReceiver_Module",
    "tia": "TIA_Module",
    "adc": "ADC_Module",
    "onurxdsp": "RxDSP_Module",
    "oltrxdsp": "RxDSP_Module_up",
    "rxdsp": "RxDSP_Module",
    "oanalyzer": "PowerMeter_Module",
    "eanalyzer": "PowerMeter_Module",
    "powermeter": "PowerMeter_Module",
    "externalmatlab": "ExternalMatlabFile",
    "matlabfile": "ExternalMatlabFile",
}


def normalize_component_name(name: str) -> str:
    return "".join(ch.lower() for ch in name if ch.isalnum())


def matlab_function_for_component(name: str) -> str:
    normalized = normalize_component_name(name)
    if normalized in COMPONENT_TO_MATLAB_FUNCTION:
        return COMPONENT_TO_MATLAB_FUNCTION[normalized]

    for key, function_name in COMPONENT_TO_MATLAB_FUNCTION.items():
        if key in normalized:
            return function_name

    return ""


def component_type_for_component(name: str) -> str:
    """Return the registry component type used for per-type instance indexing."""
    normalized = normalize_component_name(name)
    if normalized in COMPONENT_TO_MATLAB_FUNCTION:
        return normalized

    for key in COMPONENT_TO_MATLAB_FUNCTION:
        if key in normalized:
            return key

    return normalized or "component"
