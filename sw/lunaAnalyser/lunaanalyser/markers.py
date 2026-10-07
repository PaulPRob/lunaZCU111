"""Markers M1 and M2 for each kind of plot (time, spectrum, histogram).

A marker is a vertical line at the same x in every channel's plot of that
kind, like the linked x axes. Where the line meets a channel's trace there is
a dot at the nearest sample / frequency bin / histogram bin. Lines can be
dragged; the window places them with Ctrl+click (M1) and Shift+click (M2).
"""
from __future__ import annotations

from typing import Callable, Optional, Tuple

import pyqtgraph as pg
from PyQt6.QtCore import QObject, pyqtSignal

KINDS = ("time", "fft", "hist")
KIND_NAMES = {"time": "Time", "fft": "Spectrum", "hist": "Histogram"}
COLORS = ((255, 170, 0), (0, 190, 255))       # M1, M2

# (kind, channel, x) -> (x at the nearest sample/bin, value, dot y) or None
ValueAt = Callable[[str, int, float], Optional[Tuple[float, float, float]]]


class Markers(QObject):
    changed = pyqtSignal()

    def __init__(self, chplots, value_at: ValueAt):
        super().__init__()
        self.value_at = value_at
        self.nch = len(chplots)
        self.pos = {k: [None, None] for k in KINDS}       # x of M1, M2 (None = off)
        self.lines = {k: ([], []) for k in KINDS}         # [m][ch]
        self.dots = {k: ([], []) for k in KINDS}
        self._busy = False
        for cp in chplots:
            for kind, plot in zip(KINDS, cp.items()):
                for m in (0, 1):
                    col = COLORS[m]
                    ln = pg.InfiniteLine(angle=90, movable=True, pen=pg.mkPen(col, width=1),
                                         hoverPen=pg.mkPen(col, width=3), label=f"M{m + 1}",
                                         labelOpts={"position": 0.92, "color": col})
                    ln.setVisible(False)
                    ln.sigPositionChanged.connect(
                        lambda line, kind=kind, m=m: self._dragged(kind, m, line.value()))
                    plot.addItem(ln, ignoreBounds=True)
                    dot = pg.PlotDataItem(pen=None, symbol="o", symbolSize=8,
                                          symbolPen=pg.mkPen(col, width=2), symbolBrush=None)
                    plot.addItem(dot, ignoreBounds=True)
                    self.lines[kind][m].append(ln)
                    self.dots[kind][m].append(dot)

    def _dragged(self, kind: str, m: int, x: float):
        if not self._busy:
            self.set(kind, m, x)

    def set(self, kind: str, m: int, x: float | None):
        """Place marker m (0 = M1, 1 = M2) of a kind of plot at x, or remove it (None)."""
        self.pos[kind][m] = x
        self._busy = True
        try:
            for ln in self.lines[kind][m]:
                if x is not None:
                    ln.setValue(x)
                ln.setVisible(x is not None)
        finally:
            self._busy = False
        self.refresh(kind)
        self.changed.emit()

    def clear(self):
        for k in KINDS:
            for m in (0, 1):
                self.set(k, m, None)

    def refresh(self, kind: str | None = None):
        """Move the dots onto the traces (after a marker move or new data)."""
        for k in (kind,) if kind else KINDS:
            for m in (0, 1):
                x = self.pos[k][m]
                for ch, dot in enumerate(self.dots[k][m]):
                    v = None if x is None else self.value_at(k, ch, x)
                    if v is None:
                        dot.setData([], [])
                    else:
                        dot.setData([v[0]], [v[2]])

    def readout(self, kind: str, ch: int):
        """[(x, value) or None for M1, M2] of one channel."""
        out = []
        for m in (0, 1):
            x = self.pos[kind][m]
            v = None if x is None else self.value_at(kind, ch, x)
            out.append(None if v is None else (v[0], v[1]))
        return out

    def active(self, kind: str) -> bool:
        return any(x is not None for x in self.pos[kind])
