"""Per-event analysis for the plot window: statistics, Welch spectrum, histogram.

Everything here works on 12-bit ADC codes, i.e. the raw MSB-justified int16
samples shifted right by 4 (Event.adc_codes()).
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

FULL_SCALE = 2048.0          # 12-bit code full scale (peak)
_windows: dict = {}


def _window(kind: str, n: int) -> np.ndarray:
    key = (kind, n)
    w = _windows.get(key)
    if w is None:
        if kind == "hann":
            w = np.hanning(n)
        elif kind == "blackman":
            w = np.blackman(n)
        else:
            w = np.ones(n)
        _windows[key] = w = w.astype(np.float64)
    return w


def welch_dbfs(x: np.ndarray, fs: float, nperseg: int, overlap: float = 0.5,
               window: str = "hann") -> tuple[np.ndarray, np.ndarray]:
    """Welch-averaged power spectrum of each row of x (codes), in dBFS.

    x has shape (nch, n). Scaling: a full-scale sine reads 0 dBFS at its bin
    (power-spectrum scaling, not density), whatever the segment length.
    nperseg >= n gives a single windowed periodogram (no smoothing).
    Returns (freq_hz, spec_db) with spec_db of shape (nch, nperseg//2 + 1).
    """
    n = x.shape[-1]
    nperseg = int(min(max(nperseg, 16), n))
    step = max(1, int(round(nperseg * (1.0 - overlap))))
    nseg = 1 + (n - nperseg) // step
    w = _window(window, nperseg)
    # (nch, nseg, nperseg) strided view, no copy
    idx = np.arange(nseg)[:, None] * step + np.arange(nperseg)[None, :]
    seg = x[:, idx].astype(np.float32)
    seg -= seg.mean(axis=-1, keepdims=True)
    seg *= w.astype(np.float32)
    X = np.fft.rfft(seg, axis=-1)
    p = (X.real ** 2 + X.imag ** 2).mean(axis=1)            # (nch, nfreq)
    p *= 2.0 / (w.sum() ** 2)                               # one-sided, tone power
    p[:, 0] *= 0.5
    if nperseg % 2 == 0:
        p[:, -1] *= 0.5
    p /= FULL_SCALE ** 2 / 2.0                              # full-scale sine power
    f = np.fft.rfftfreq(nperseg, 1.0 / fs)
    return f, 10.0 * np.log10(np.maximum(p, 1e-30))


@dataclass
class ChannelStats:
    mean: float
    rms: float              # AC rms (about the mean)
    peak: int               # max |x|
    peak_idx: int
    vmin: int
    vmax: int


def channel_stats(codes: np.ndarray) -> list[ChannelStats]:
    out = []
    xf = codes.astype(np.float64)
    means = xf.mean(axis=1)
    rms = xf.std(axis=1)
    absx = np.abs(codes.astype(np.int32))
    pk_idx = absx.argmax(axis=1)
    mins = codes.min(axis=1)
    maxs = codes.max(axis=1)
    for c in range(codes.shape[0]):
        out.append(ChannelStats(mean=float(means[c]), rms=float(rms[c]),
                                peak=int(absx[c, pk_idx[c]]), peak_idx=int(pk_idx[c]),
                                vmin=int(mins[c]), vmax=int(maxs[c])))
    return out


def histograms(codes: np.ndarray, binsize: int = 1) -> tuple[np.ndarray, np.ndarray]:
    """Histogram of each channel over the full 12-bit range.

    Returns (edges, counts): edges of length nbins+1 (codes), counts (nch, nbins).
    """
    binsize = max(1, int(binsize))
    nb = 4096 // binsize
    v = (codes.astype(np.int32) + 2048) // binsize
    nch = codes.shape[0]
    flat = (v + (np.arange(nch)[:, None] * nb)).ravel()
    counts = np.bincount(flat, minlength=nch * nb).reshape(nch, nb)
    edges = np.arange(nb + 1) * binsize - 2048
    return edges, counts
