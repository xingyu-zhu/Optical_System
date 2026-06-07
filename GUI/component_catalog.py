"""Shared component catalog and icon resolver."""

from __future__ import annotations

import re
from pathlib import Path

LOCAL_ICON_DIR = Path(__file__).resolve().parent / "icon"
LEGACY_ICON_DIR = Path(__file__).resolve().parent.parent / "GUI_old" / "icon"
ICON_DIRS = [LOCAL_ICON_DIR, LEGACY_ICON_DIR]

COMPONENT_GROUPS = {
    "发端与光源": [
        ("OLTTxDSP", "Tx_DSP.png"),
        ("ONUTxDSP", "Tx_DSP.png"),
        ("DAC", "DAC.jpg"),
        ("Driver", "Driver.jpg"),
        ("LaserCW", "laser.png"),
        ("LO", "LO.png"),
        ("Modulator", "modulator.jpg"),
    ],
    "链路与无源": [
        ("Fiber", "fiber.jpg"),
        ("Splitter", "splitter.jpg"),
        ("Combiner", "combiner.jpg"),
        ("VOA", "VOA.jpg"),
        ("Pol_Rot", "RotatePol.jpg"),
        ("OA", "OA.jpg"),
    ],
    "收端与分析": [
        ("ICR", "ICR.png"),
        ("TIA", "TIA.jpg"),
        ("ADC", "ADC.jpg"),
        ("ONURxDSP", "Rx_DSP.png"),
        ("OLTRxDSP", "Rx_DSP.png"),
        ("O-Analyzer", "Analyzer.png"),
        ("E-Analyzer", "Analyzer.png"),
        ("PowerMeter", "OPM.jpg"),
    ],
}

KEYWORD_ICON = [
    ("txdsp", "Tx_DSP.png"),
    ("rxdsp", "Rx_DSP.png"),
    ("dac", "DAC.jpg"),
    ("driver", "Driver.jpg"),
    ("laser", "laser.png"),
    ("lo", "LO.png"),
    ("modulator", "modulator.jpg"),
    ("fiber", "fiber.jpg"),
    ("splitter", "splitter.jpg"),
    ("combiner", "combiner.jpg"),
    ("voa", "VOA.jpg"),
    ("pol", "RotatePol.jpg"),
    ("rotate", "RotatePol.jpg"),
    ("oa", "OA.jpg"),
    ("icr", "ICR.png"),
    ("tia", "TIA.jpg"),
    ("adc", "ADC.jpg"),
    ("analyzer", "Analyzer.png"),
    ("powermeter", "OPM.jpg"),
    ("opm", "OPM.jpg"),
]


def _first_existing(icon_name: str) -> str:
    for d in ICON_DIRS:
        p = d / icon_name
        if p.exists():
            return str(p)
    return ""


_NAME_TO_ICON = {
    name.lower(): _first_existing(icon_name)
    for groups in COMPONENT_GROUPS.values()
    for name, icon_name in groups
}


def _normalize(name: str) -> str:
    s = name.strip().lower()
    s = s.replace("-", "").replace("_", "")
    s = re.sub(r"\d+$", "", s)
    return s


def resolve_icon_path(component_name: str, fallback: str = "") -> str:
    if fallback and Path(fallback).exists():
        return fallback

    key = component_name.lower()
    if key in _NAME_TO_ICON and _NAME_TO_ICON[key]:
        return _NAME_TO_ICON[key]

    norm = _normalize(component_name)

    for name_key, path in _NAME_TO_ICON.items():
        if not path:
            continue
        if _normalize(name_key) == norm:
            return path

    for keyword, icon_name in KEYWORD_ICON:
        if keyword in norm:
            path = _first_existing(icon_name)
            if path:
                return path

    return fallback
