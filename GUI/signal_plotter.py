"""Standalone plotting helpers for optical/electrical simulation signals.

The functions here are intentionally independent from the PyQt GUI. They can be
used from scripts, from MATLAB topology outputs converted to Python objects, or
later embedded into a PyQt matplotlib canvas.
"""

from __future__ import annotations

import os
from pathlib import Path

import numpy as np

_MPL_CACHE = Path(__file__).resolve().parent / ".matplotlib_cache"
_MPL_CACHE.mkdir(exist_ok=True)
os.environ.setdefault("MPLCONFIGDIR", str(_MPL_CACHE))
os.environ.setdefault("XDG_CACHE_HOME", str(_MPL_CACHE))

from matplotlib import pyplot as plt


def _as_array(signal) -> np.ndarray:
    """Convert common Python/MATLAB-engine values to a numpy array."""
    if signal is None:
        return np.array([], dtype=float)
    arr = np.asarray(signal)
    if arr.dtype == object:
        arr = np.array(arr.tolist())
    return np.squeeze(arr)


def _as_channels(signal) -> np.ndarray:
    """Return signal as [samples, channels]."""
    arr = _as_array(signal)
    if arr.ndim == 0:
        arr = arr.reshape(1, 1)
    elif arr.ndim == 1:
        arr = arr.reshape(-1, 1)
    elif arr.shape[0] < arr.shape[-1]:
        # Keep MATLAB-style column vectors as samples-first when likely needed.
        arr = arr.T
    return arr


def _polarization_label(channel_index: int) -> str:
    """Return user-facing polarization label for dual-pol traces."""
    labels = ("X", "Y")
    if channel_index < len(labels):
        return labels[channel_index]
    return f"Ch{channel_index + 1}"


def _full_frame_preview_indices(data: np.ndarray, max_samples: int | None) -> np.ndarray:
    """Select preview samples across the whole frame, preserving burst peaks."""
    length = data.shape[0]
    if max_samples is None or length <= max_samples:
        return np.arange(length, dtype=int)

    edges = np.linspace(0, length, max_samples + 1, dtype=int)
    energy = np.max(np.abs(data), axis=1)
    indices: list[int] = []
    for start, end in zip(edges[:-1], edges[1:]):
        if end <= start:
            continue
        indices.append(start + int(np.argmax(energy[start:end])))
    return np.asarray(indices, dtype=int)


def _frequency_axis(n: int, fs: float | None) -> np.ndarray:
    if fs is None:
        fs = 1.0
    return np.fft.fftshift(np.fft.fftfreq(n, d=1.0 / fs))


def _db_power(x: np.ndarray, floor_db: float = -120.0) -> np.ndarray:
    power = np.abs(x) ** 2
    power = power / max(np.max(power), np.finfo(float).eps)
    return np.maximum(10 * np.log10(power + np.finfo(float).eps), floor_db)


def scalar_text(value) -> str:
    """Format scalar or small vector MATLAB/Python values for result tables."""
    arr = _as_array(value)
    if arr.size == 0:
        return "-"
    if arr.size == 1:
        val = arr.reshape(-1)[0]
        try:
            return f"{float(np.real(val)):.6g}"
        except Exception:
            return str(val)
    try:
        flat = arr.reshape(-1)
        shown = ", ".join(f"{float(np.real(v)):.6g}" for v in flat[:4])
        return shown + (" ..." if flat.size > 4 else "")
    except Exception:
        return str(value)


def float_or_default(value, default: float) -> float:
    """Return first numeric value or a default."""
    arr = _as_array(value)
    if arr.size:
        try:
            return float(np.real(arr.reshape(-1)[0]))
        except Exception:
            pass
    return default


def draw_spectrum(ax, signal, fs: float, title: str = "Electrical Spectrum") -> None:
    """Draw centered normalized electrical spectrum on an existing axes."""
    data = _as_channels(signal)
    n = data.shape[0]
    if n == 0:
        ax.set_title(title)
        ax.text(0.5, 0.5, "No signal available", ha="center", va="center", transform=ax.transAxes)
        ax.set_axis_off()
        return
    freq = _frequency_axis(n, fs)
    for ch in range(data.shape[1]):
        spectrum = np.fft.fftshift(np.fft.fft(data[:, ch]))
        ax.plot(freq / 1e9, _db_power(spectrum), linewidth=1.0, label=_polarization_label(ch))

    ax.set_title(title)
    ax.set_xlabel("Frequency (GHz)")
    ax.set_ylabel("Normalized Power (dB)")
    ax.set_ylim(-90, 5)
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best", fontsize=8)


def draw_optical_spectrum(
    ax,
    optical_field,
    fs: float,
    center_frequency_hz: float | None = 193.1e12,
    title: str = "Optical Spectrum",
) -> None:
    """Draw optical spectrum on an existing axes."""
    data = _as_channels(optical_field)
    n = data.shape[0]
    if n == 0:
        ax.set_title(title)
        ax.text(0.5, 0.5, "No optical signal available", ha="center", va="center", transform=ax.transAxes)
        ax.set_axis_off()
        return
    freq_offset = _frequency_axis(n, fs)
    x = freq_offset if center_frequency_hz is None else center_frequency_hz + freq_offset
    x_label = "Frequency Offset (GHz)" if center_frequency_hz is None else "Optical Frequency (THz)"
    x_scale = 1e9 if center_frequency_hz is None else 1e12

    for ch in range(data.shape[1]):
        spectrum = np.fft.fftshift(np.fft.fft(data[:, ch]))
        ax.plot(x / x_scale, _db_power(spectrum), linewidth=1.0, label=_polarization_label(ch))

    ax.set_title(title)
    ax.set_xlabel(x_label)
    ax.set_ylabel("Normalized Optical Power (dB)")
    ax.set_ylim(-90, 5)
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best", fontsize=8)


def draw_constellation(
    ax,
    symbols,
    max_points: int = 12000,
    normalize: bool = True,
    title: str = "Constellation",
) -> None:
    """Draw I/Q constellation on an existing axes."""
    data = _as_channels(symbols)
    if data.shape[0] == 0:
        ax.set_title(title)
        ax.text(0.5, 0.5, "No signal available", ha="center", va="center", transform=ax.transAxes)
        ax.set_axis_off()
        return
    for ch in range(data.shape[1]):
        samples = data[:, ch].reshape(-1)
        if max_points and samples.size > max_points:
            samples = samples[:: max(1, samples.size // max_points)]
        if normalize and samples.size:
            rms = np.sqrt(np.mean(np.abs(samples) ** 2))
            if rms > 0:
                samples = samples / rms
        ax.scatter(
            np.real(samples),
            np.imag(samples),
            s=5,
            alpha=0.35,
            edgecolors="none",
            label=_polarization_label(ch),
        )

    ax.axhline(0, color="0.55", linewidth=0.8)
    ax.axvline(0, color="0.55", linewidth=0.8)
    ax.set_title(title)
    ax.set_xlabel("In-phase")
    ax.set_ylabel("Quadrature")
    ax.grid(True, alpha=0.25)
    ax.set_aspect("equal", adjustable="box")
    ax.legend(loc="best", fontsize=8)


def draw_time_waveform(
    ax,
    signal,
    fs: float | None = None,
    max_samples: int | None = 12000,
    sample_step: float = 1.0,
    title: str = "Time Domain Waveform",
) -> None:
    """Draw real/imaginary time-domain waveform on an existing axes.

    Long burst-mode frames are decimated across the whole frame instead of
    clipped at the head, so every burst remains visible in the preview.
    """
    data = _as_channels(signal)
    if data.shape[0] == 0:
        ax.set_title(title)
        ax.text(0.5, 0.5, "No signal available", ha="center", va="center", transform=ax.transAxes)
        ax.set_axis_off()
        return
    preview_indices = _full_frame_preview_indices(data, max_samples)
    data = data[preview_indices, :]

    effective_step = max(float(sample_step or 1.0), 1.0)
    x = preview_indices * effective_step if fs is None else preview_indices * effective_step / fs * 1e9
    x_label = "Sample" if fs is None else "Time (ns)"

    for ch in range(data.shape[1]):
        y = data[:, ch]
        pol_label = _polarization_label(ch)
        ax.plot(x, np.real(y), linewidth=1.0, label=f"{pol_label} real")
        if np.iscomplexobj(y):
            ax.plot(x, np.imag(y), linewidth=0.9, linestyle="--", label=f"{pol_label} imag")

    ax.set_title(title)
    ax.set_xlabel(x_label)
    ax.set_ylabel("Amplitude (a.u.)")
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best", fontsize=8)


def _finalize(fig, save_path: str | Path | None, show: bool):
    fig.tight_layout()
    if save_path:
        save_path = Path(save_path)
        save_path.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(save_path, dpi=180)
    if show:
        plt.show()
    return fig


def plot_time_waveform(
    signal,
    fs: float | None = None,
    max_samples: int | None = 12000,
    sample_step: float = 1.0,
    title: str = "Time Domain Waveform",
    save_path: str | Path | None = None,
    show: bool = False,
):
    """Plot real/imaginary time-domain waveforms, similar to MATLAB plot()."""
    data = _as_channels(signal)
    preview_indices = _full_frame_preview_indices(data, max_samples)
    data = data[preview_indices, :]

    effective_step = max(float(sample_step or 1.0), 1.0)
    x = preview_indices * effective_step if fs is None else preview_indices * effective_step / fs
    x_label = "Sample" if fs is None else "Time (s)"

    fig, ax = plt.subplots(figsize=(8.5, 3.8))
    for ch in range(data.shape[1]):
        y = data[:, ch]
        pol_label = _polarization_label(ch)
        ax.plot(x, np.real(y), linewidth=1.0, label=f"{pol_label} real")
        if np.iscomplexobj(y):
            ax.plot(x, np.imag(y), linewidth=0.9, linestyle="--", label=f"{pol_label} imag")

    ax.set_title(title)
    ax.set_xlabel(x_label)
    ax.set_ylabel("Amplitude")
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best", fontsize=8)
    return _finalize(fig, save_path, show)


def plot_spectrum(
    signal,
    fs: float,
    title: str = "Electrical Spectrum",
    save_path: str | Path | None = None,
    show: bool = False,
):
    """Plot centered normalized spectrum in dB, similar to MATLAB pwelch/fft views."""
    fig, ax = plt.subplots(figsize=(8.5, 3.8))
    draw_spectrum(ax, signal, fs, title=title)
    return _finalize(fig, save_path, show)


def plot_optical_spectrum(
    optical_field,
    fs: float,
    center_frequency_hz: float | None = 193.1e12,
    title: str = "Optical Spectrum",
    save_path: str | Path | None = None,
    show: bool = False,
):
    """Plot optical spectrum using frequency offset or absolute optical frequency."""
    fig, ax = plt.subplots(figsize=(8.5, 3.8))
    draw_optical_spectrum(ax, optical_field, fs, center_frequency_hz=center_frequency_hz, title=title)
    return _finalize(fig, save_path, show)


def plot_constellation(
    symbols,
    max_points: int = 12000,
    normalize: bool = True,
    title: str = "Constellation",
    save_path: str | Path | None = None,
    show: bool = False,
):
    """Plot I/Q constellation for complex symbols or waveform samples."""
    fig, ax = plt.subplots(figsize=(4.8, 4.8))
    draw_constellation(ax, symbols, max_points=max_points, normalize=normalize, title=title)
    return _finalize(fig, save_path, show)


def plot_eye_diagram(
    signal,
    samples_per_symbol: int,
    traces: int = 160,
    title: str = "Eye Diagram",
    save_path: str | Path | None = None,
    show: bool = False,
):
    """Plot a compact eye diagram for real-valued waveforms."""
    data = np.real(_as_array(signal).reshape(-1))
    span = 2 * samples_per_symbol
    count = min(traces, max(0, (data.size - span) // samples_per_symbol))
    x = np.arange(span) / samples_per_symbol

    fig, ax = plt.subplots(figsize=(6.2, 3.8))
    for k in range(count):
        start = k * samples_per_symbol
        ax.plot(x, data[start : start + span], color="#1f77b4", alpha=0.15, linewidth=0.8)

    ax.set_title(title)
    ax.set_xlabel("Symbol Period")
    ax.set_ylabel("Amplitude")
    ax.grid(True, alpha=0.25)
    return _finalize(fig, save_path, show)


def save_standard_signal_plots(
    signal,
    fs: float,
    output_dir: str | Path,
    name: str = "signal",
    optical: bool = False,
    constellation_source=None,
) -> list[Path]:
    """Save a standard plot set and return generated file paths."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    generated = [
        output_dir / f"{name}_time.png",
        output_dir / f"{name}_spectrum.png",
        output_dir / f"{name}_constellation.png",
    ]

    plot_time_waveform(signal, fs=fs, save_path=generated[0])
    if optical:
        plot_optical_spectrum(signal, fs=fs, save_path=generated[1])
    else:
        plot_spectrum(signal, fs=fs, save_path=generated[1])

    source = signal if constellation_source is None else constellation_source
    plot_constellation(source, save_path=generated[2])
    plt.close("all")
    return generated


def _demo_signal(fs: float = 64e9, n: int = 4096) -> np.ndarray:
    t = np.arange(n) / fs
    x = np.exp(1j * 2 * np.pi * 5e9 * t) + 0.25 * np.exp(1j * 2 * np.pi * 12e9 * t)
    y = 0.8 * np.exp(1j * (2 * np.pi * 7e9 * t + np.pi / 5))
    return np.column_stack([x, y])


if __name__ == "__main__":
    fs_demo = 64e9
    sig_demo = _demo_signal(fs_demo)
    out_dir = Path(__file__).resolve().parent / "plot_results"
    paths = save_standard_signal_plots(sig_demo, fs_demo, out_dir, name="demo_optical", optical=True)
    print("Generated plots:")
    for path in paths:
        print(path)
