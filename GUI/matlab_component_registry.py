"""Mapping between GUI component names and MATLAB PON functions."""

from __future__ import annotations

COMPONENT_TO_MATLAB_FUNCTION = {
    "olttxdsp": "OC_TxDSP_Module",
    "onutxdsp": "OC_TxDSP_Module_v4_up",
    "txdsp": "OC_TxDSP_Module",
    "dac": "OC_SimDAC_M8196A",
    "driver": "OC_Driver_Module",
    "lasercw": "OC_LaserCW_Module",
    "laser": "OC_LaserCW_Module",
    "lo": "OC_LO_Optical_Module",
    "modulator": "OC_Modulator_Module",
    "oa": "OC_EDFA_Module",
    "edfa": "OC_EDFA_Module",
    "voa": "OC_VOA_Module",
    "polrot": "OC_PolarizationEmulation_Module",
    "rotatepol": "OC_PolarizationEmulation_Module",
    "fiber": "OC_Fiber_Channel",
    "splitter": "OC_Splitter_Module",
    "combiner": "OC_Combiner_Module",
    "icr": "OC_CoherentReceiver_Module",
    "coherentreceiver": "OC_CoherentReceiver_Module",
    "tia": "OC_TIA_Module",
    "adc": "OC_ADC_Module",
    "onurxdsp": "OC_RxDSP_Module",
    "oltrxdsp": "OC_RxDSP_Module_up",
    "rxdsp": "OC_RxDSP_Module",
    "oanalyzer": "OC_PowerMeter_Module",
    "eanalyzer": "OC_PowerMeter_Module",
    "powermeter": "OC_PowerMeter_Module",
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
