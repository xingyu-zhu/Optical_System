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

ICON_ALIASES = {
    "coherentreceiver": "ICR.png",
    "edfa": "OA.jpg",
    "laser": "laser.png",
    "opm": "OPM.jpg",
    "polrot": "RotatePol.jpg",
    "rotatepol": "RotatePol.jpg",
    "rxdsp": "Rx_DSP.png",
    "txdsp": "Tx_DSP.png",
}

LEGACY_CONTAINS_ALIASES = {
    "rxdsp": "Rx_DSP.png",
    "txdsp": "Tx_DSP.png",
}


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
    key = component_name.lower()
    if key in _NAME_TO_ICON and _NAME_TO_ICON[key]:
        return _NAME_TO_ICON[key]

    norm = _normalize(component_name)

    for name_key, path in _NAME_TO_ICON.items():
        if not path:
            continue
        if _normalize(name_key) == norm:
            return path

    alias_icon = ICON_ALIASES.get(norm)
    if alias_icon:
        path = _first_existing(alias_icon)
        if path:
            return path

    for keyword, icon_name in LEGACY_CONTAINS_ALIASES.items():
        if keyword in norm:
            path = _first_existing(icon_name)
            if path:
                return path

    if fallback and Path(fallback).exists():
        return fallback

    return fallback
