"""lunaGUI plot window: per channel, time trace / Welch spectrum / histogram."""
from __future__ import annotations

import time

import numpy as np
import pyqtgraph as pg
from PyQt6.QtCore import QSettings, Qt
from PyQt6.QtWidgets import (QCheckBox, QComboBox, QDoubleSpinBox, QGraphicsTextItem,
                             QHBoxLayout, QLabel, QMainWindow, QPushButton, QSpinBox,
                             QToolBar, QVBoxLayout, QWidget)

from lunaclient.protocol import NCH

from .workers import PlotData, PlotWorker

NPERSEG = [64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384]
WINDOWS = {"Hann": "hann", "Blackman": "blackman", "Rectangular": "rect"}
OVERLAPS = {"0 %": 0.0, "50 %": 0.5, "75 %": 0.75}


def set_range(plot, axis: int, lo: float, hi: float, pad: float = 0.05, sticky: bool = True):
    """Set the x (0) or y (1) range only when needed.

    With sticky=True the range is kept while [lo, hi] fits inside it and spans
    at least 60 % of it, so that the axes (expensive to redraw) usually stay
    unchanged from one event to the next.
    """
    if not hi > lo:
        hi = lo + 1.0
    cur_lo, cur_hi = plot.vb.viewRange()[axis]
    span = cur_hi - cur_lo
    if sticky:
        if cur_lo <= lo and hi <= cur_hi and (hi - lo) >= 0.6 * span:
            return
    elif abs(cur_lo - lo) < 1e-9 * span and abs(cur_hi - hi) < 1e-9 * span:
        return
    m = (hi - lo) * pad
    if axis == 0:
        plot.setXRange(lo - m, hi + m, padding=0)
    else:
        plot.setYRange(lo - m, hi + m, padding=0)


def ch_pen(ch: int):
    return pg.mkPen(pg.intColor(ch, NCH, maxValue=230), width=1)


class ChannelPlots:
    """The three plots of one channel."""

    def __init__(self, ch: int):
        self.ch = ch
        pen = ch_pen(ch)
        thr_pen = pg.mkPen((220, 60, 60), width=1, style=Qt.PenStyle.DashLine)
        trg_pen = pg.mkPen((150, 150, 150), width=1, style=Qt.PenStyle.DotLine)

        self.time = pg.PlotItem()
        self.time.showGrid(x=True, y=True, alpha=0.25)
        self.time.setLabel("bottom", "t − t<sub>trig</sub>", units="s")
        self.time.setLabel("left", "code")
        self.tcurve = self.time.plot(pen=pen)
        self.thr_hi = pg.InfiniteLine(angle=0, pen=thr_pen)
        self.thr_lo = pg.InfiniteLine(angle=0, pen=thr_pen)
        self.trig_line = pg.InfiniteLine(pos=0, angle=90, pen=trg_pen)
        for it in (self.thr_hi, self.thr_lo, self.trig_line):
            self.time.addItem(it, ignoreBounds=True)

        self.fft = pg.PlotItem()
        self.fft.showGrid(x=True, y=True, alpha=0.25)
        self.fft.setLabel("bottom", "f", units="Hz")
        self.fft.setLabel("left", "dBFS")
        self.fcurve = self.fft.plot(pen=pen)

        self.hist = pg.PlotItem()
        self.hist.showGrid(x=True, y=True, alpha=0.25)
        self.hist.setLabel("bottom", "code")
        self.hist.setLabel("left", "count")
        self.hcurve = self.hist.plot(stepMode="center", fillLevel=0, pen=pen,
                                     brush=pg.mkBrush(pg.intColor(ch, NCH, alpha=80)))
        self.hthr_hi = pg.InfiniteLine(angle=90, pen=thr_pen)
        self.hthr_lo = pg.InfiniteLine(angle=90, pen=thr_pen)
        for it in (self.hthr_hi, self.hthr_lo):
            self.hist.addItem(it, ignoreBounds=True)

        # Keep each update to a single repaint of the grid:
        # - fixed axis sizes, and the stats text in a free QGraphicsTextItem
        #   rather than the PlotItem title (LabelItem.setText changes size
        #   hints and forces a re-layout of the whole grid);
        # - no pyqtgraph auto-range or auto-downsampling, both of which are
        #   evaluated lazily during the paint and schedule another one.
        #   _draw() sets the ranges itself, until the user zooms with the mouse.
        self.text = {}
        self.user_y = {}                     # id(plot) -> zoomed by the user
        for p in (self.time, self.fft, self.hist):
            p.disableAutoRange()
            p.hideButtons()
            self.user_y[id(p)] = False
            p.setTitle(" ", size="8pt")
            p.titleLabel.setFixedHeight(32)
            p.getAxis("left").setWidth(48)
            p.getAxis("bottom").setHeight(36)
            t = QGraphicsTextItem(p)
            t.setDefaultTextColor(pg.mkColor(pg.getConfigOption("foreground")))
            f = t.font()
            f.setPointSizeF(8)
            t.setFont(f)
            t.setPos(52, -2)
            self.text[id(p)] = t

    def set_text(self, plot, html: str):
        self.text[id(plot)].setHtml(html)

    def items(self):
        return (self.time, self.fft, self.hist)


class PlotWindow(QMainWindow):
    def __init__(self, worker: PlotWorker, settings: QSettings, parent=None):
        super().__init__(parent)
        self.setWindowTitle("lunaGUI – event plots")
        self.worker = worker
        self.qs = settings
        self.resize(1600, 1000)
        self._shown_rate_t = time.monotonic()
        self._shown_count = 0
        self._shown_rate = 0.0
        self._last: PlotData | None = None
        self.user_x = {"time": False, "fft": False, "hist": False}

        pg.setConfigOptions(antialias=False)
        self._build_toolbar()

        central = QWidget()
        lay = QVBoxLayout(central)
        lay.setContentsMargins(4, 4, 4, 4)
        self.info = QLabel("waiting for events …")
        self.info.setTextFormat(Qt.TextFormat.RichText)
        lay.addWidget(self.info)
        self.glw = pg.GraphicsLayoutWidget()
        lay.addWidget(self.glw, 1)
        self.setCentralWidget(central)

        self.chplots = [ChannelPlots(c) for c in range(NCH)]
        # shared axes: zooming one channel zooms them all
        for cp in self.chplots[1:]:
            cp.time.setXLink(self.chplots[0].time)
            cp.fft.setXLink(self.chplots[0].fft)
            cp.hist.setXLink(self.chplots[0].hist)
        # mouse zoom/pan: stop following the data on that axis until "Reset zoom"
        for cp in self.chplots:
            for kind, p in zip(("time", "fft", "hist"), cp.items()):
                p.vb.sigRangeChangedManually.connect(
                    lambda mask, kind=kind, cp=cp, p=p: self._user_zoom(kind, cp, p, mask))
        self._apply_settings()
        self._relayout()

    # ------------------------------------------------------------------ UI
    def _build_toolbar(self):
        q = self.qs
        tb = QToolBar("Plot settings")
        tb.setMovable(False)
        self.addToolBar(tb)

        def add(label, w):
            box = QWidget()
            hl = QHBoxLayout(box)
            hl.setContentsMargins(4, 0, 4, 0)
            if label:
                hl.addWidget(QLabel(label))
            hl.addWidget(w)
            tb.addWidget(box)
            return w

        self.ch_boxes = []
        chw = QWidget()
        hl = QHBoxLayout(chw)
        hl.setContentsMargins(4, 0, 4, 0)
        hl.addWidget(QLabel("Show:"))
        shown = int(q.value("plot/shown", 0xFF))
        for c in range(NCH):
            cb = QCheckBox(str(c))
            cb.setChecked(bool((shown >> c) & 1))
            cb.toggled.connect(self._relayout)
            self.ch_boxes.append(cb)
            hl.addWidget(cb)
        tb.addWidget(chw)

        self.cols = add("Columns", QSpinBox())
        self.cols.setRange(1, 8)
        self.cols.setValue(int(q.value("plot/cols", 4)))
        self.cols.valueChanged.connect(self._relayout)
        tb.addSeparator()

        self.rate = add("Max plots/s", QDoubleSpinBox())
        self.rate.setRange(0.1, 30.0)
        self.rate.setSingleStep(0.5)
        self.rate.setValue(float(q.value("plot/max_rate", 5.0)))
        self.rate.setToolTip("Upper limit on events plotted per second. Below this trigger\n"
                             "rate every event is plotted; above it only the newest.")
        self.rate.valueChanged.connect(self._apply_settings)
        self.pause = add("", QCheckBox("Pause"))
        self.pause.toggled.connect(self._apply_settings)
        tb.addSeparator()

        self.nperseg = add("Welch segment", QComboBox())
        for n in NPERSEG:
            self.nperseg.addItem(str(n), n)
        self.nperseg.setToolTip("Welch segment length. Shorter = smoother spectrum, coarser\n"
                                "resolution. ≥ capture length = single periodogram.")
        self.nperseg.setCurrentText(str(q.value("plot/nperseg", 1024)))
        self.nperseg.currentIndexChanged.connect(self._apply_settings)
        self.overlap = add("overlap", QComboBox())
        self.overlap.addItems(OVERLAPS)
        self.overlap.setCurrentText(str(q.value("plot/overlap", "50 %")))
        self.overlap.currentIndexChanged.connect(self._apply_settings)
        self.window = add("window", QComboBox())
        self.window.addItems(WINDOWS)
        self.window.setCurrentText(str(q.value("plot/window", "Hann")))
        self.window.currentIndexChanged.connect(self._apply_settings)
        tb.addSeparator()

        self.hbin = add("Hist bin", QSpinBox())
        self.hbin.setRange(1, 64)
        self.hbin.setSuffix(" codes")
        self.hbin.setValue(int(q.value("plot/hist_bin", 1)))
        self.hbin.valueChanged.connect(self._apply_settings)
        self.hlog = add("", QCheckBox("log"))
        self.hlog.setChecked(q.value("plot/hist_log", "false") == "true")
        self.hlog.toggled.connect(self._apply_settings)
        self.fullscale = add("", QCheckBox("Time: full scale"))
        self.fullscale.setToolTip("Fix the time-plot y axis to ±2048 codes")
        self.fullscale.setChecked(q.value("plot/fullscale", "false") == "true")
        self.fullscale.toggled.connect(self._apply_settings)
        tb.addSeparator()
        rz = QPushButton("Reset zoom")
        rz.setToolTip("Follow the data again after zooming/panning with the mouse")
        rz.clicked.connect(self._reset_zoom)
        add("", rz)

    def _user_zoom(self, kind, cp, plot, mask):
        if mask[0]:
            self.user_x[kind] = True
        if mask[1]:
            cp.user_y[id(plot)] = True

    def _reset_zoom(self):
        for k in self.user_x:
            self.user_x[k] = False
        for cp in self.chplots:
            for k in cp.user_y:
                cp.user_y[k] = False
            for p in cp.items():             # forces set_range() to re-fit
                p.vb.setRange(xRange=(0, 1e-12), yRange=(0, 1e-12), padding=0)
        self._redraw()

    def _redraw(self):
        if self._last is not None and self.isVisible():
            self._draw(self._last)

    def _apply_settings(self):
        s = self.worker.settings
        s.max_rate = self.rate.value()
        s.paused = self.pause.isChecked()
        new = (self.nperseg.currentData(), OVERLAPS[self.overlap.currentText()],
               WINDOWS[self.window.currentText()], self.hbin.value())
        changed = new != (s.nperseg, s.overlap, s.window, s.hist_bin)
        s.nperseg, s.overlap, s.window, s.hist_bin = new
        for cp in getattr(self, "chplots", []):
            cp.hist.setLogMode(y=self.hlog.isChecked())
        q = self.qs
        q.setValue("plot/max_rate", s.max_rate)
        q.setValue("plot/nperseg", s.nperseg)
        q.setValue("plot/overlap", self.overlap.currentText())
        q.setValue("plot/window", self.window.currentText())
        q.setValue("plot/hist_bin", s.hist_bin)
        q.setValue("plot/hist_log", "true" if self.hlog.isChecked() else "false")
        q.setValue("plot/fullscale", "true" if self.fullscale.isChecked() else "false")
        if changed or self.sender() is self.hlog:
            self.worker.replot()
        elif self.sender() is self.fullscale:
            self._redraw()

    def _relayout(self):
        self.glw.clear()
        shown = [c for c in range(NCH) if self.ch_boxes[c].isChecked()]
        ncol = max(1, min(self.cols.value(), len(shown) or 1))
        for i, c in enumerate(shown):
            row, col = divmod(i, ncol)
            for k, item in enumerate(self.chplots[c].items()):
                self.glw.addItem(item, row=row * 3 + k, col=col)
        self.qs.setValue("plot/shown", sum(1 << c for c in shown))
        self.qs.setValue("plot/cols", self.cols.value())

    # ------------------------------------------------------------- drawing
    def on_data(self, d: PlotData):
        try:
            if self.isVisible():
                self._draw(d)
        finally:
            self.worker.gui_done()

    def _draw(self, d: PlotData):
        evt = d.evt
        self._last = d
        log_h = self.hlog.isChecked()
        t_s = d.t_ns * 1e-9               # SI units: pyqtgraph picks the prefix
        f_hz = d.freq_mhz * 1e6
        ds = max(1, d.codes.shape[1] // 2048)  # ≥ 1024 peak pairs per trace
        hx = [np.inf, -np.inf]                 # common histogram x range
        for c, cp in enumerate(self.chplots):
            if not self.ch_boxes[c].isChecked():
                continue
            st = d.stats[c]
            thr = d.thresh_codes[c]
            trig = (evt.trig_mask >> c) & 1
            cp.tcurve.setDownsampling(ds=ds, auto=False, method="peak")
            cp.tcurve.setData(t_s, d.codes[c])
            cp.thr_hi.setValue(thr)
            cp.thr_lo.setValue(-thr)
            if not cp.user_y[id(cp.time)]:
                if self.fullscale.isChecked():
                    set_range(cp.time, 1, -2048, 2048, pad=0, sticky=False)
                else:   # include the threshold lines: shows the noise margin
                    ym = max(abs(st.vmin), abs(st.vmax), thr, 1)
                    set_range(cp.time, 1, -ym, ym)
            if not self.user_x["time"]:
                set_range(cp.time, 0, t_s[0], t_s[-1], pad=0, sticky=False)
            tag = ' <span style="color:#e04040">● TRIG</span>' if trig else ""
            pk_t = d.t_ns[st.peak_idx]
            cp.set_text(cp.time,
                f"<b>CH{c}</b>{tag} &nbsp; thr ±{thr:.0f}<br>"
                f"mean {st.mean:+.2f} &nbsp; rms {st.rms:.2f} &nbsp; "
                f"peak {st.peak} @ {pk_t:+.1f} ns")

            spec = d.spec_db[c]
            cp.fcurve.setData(f_hz, spec)
            if not cp.user_y[id(cp.fft)]:
                set_range(cp.fft, 1, float(spec[1:].min()) - 2, float(spec.max()) + 2)
            if not self.user_x["fft"]:
                set_range(cp.fft, 0, 0, f_hz[-1], pad=0, sticky=False)
            k = int(np.argmax(spec[1:])) + 1 if spec.size > 1 else 0
            cp.set_text(cp.fft, f"peak {d.freq_mhz[k]:.1f} MHz, {spec[k]:.1f} dBFS"
                                f" &nbsp; (Welch seg {self.worker.settings.nperseg})")

            counts = d.hist_counts[c]
            nz = np.nonzero(counts)[0]
            lo, hi = (nz[0], nz[-1] + 1) if nz.size else (0, counts.size)
            lo, hi = max(0, lo - 2), min(counts.size, hi + 2)
            y = counts[lo:hi].astype(float)
            if log_h:
                y = np.maximum(y, 0.5)
            cp.hcurve.setData(d.hist_edges[lo:hi + 1], y)
            hx[0], hx[1] = min(hx[0], d.hist_edges[lo]), max(hx[1], d.hist_edges[hi])
            if not cp.user_y[id(cp.hist)]:
                if log_h:
                    set_range(cp.hist, 1, np.log10(0.5), np.log10(max(y.max(), 1)), pad=0.03)
                else:
                    set_range(cp.hist, 1, 0, float(y.max()), pad=0.03)
            cp.hthr_hi.setValue(thr)
            cp.hthr_lo.setValue(-thr)
            cp.set_text(cp.hist, f"min {st.vmin} &nbsp; max {st.vmax} &nbsp; "
                                 f"mean {st.mean:+.2f} &nbsp; rms {st.rms:.2f}")

        if not self.user_x["hist"] and np.isfinite(hx[0]):
            # symmetric about 0: ±(largest |code| over the shown channels)
            m = max(abs(hx[0]), abs(hx[1]), 1)
            vlo, vhi = self.chplots[0].hist.vb.viewRange()[0]
            centred = abs(vlo + vhi) <= 1e-6 * (vhi - vlo)
            set_range(self.chplots[0].hist, 0, -m, m, pad=0.02, sticky=centred)

        # plotted rate
        self._shown_count += 1
        now = time.monotonic()
        if now - self._shown_rate_t >= 1.0:
            self._shown_rate = self._shown_count / (now - self._shown_rate_t)
            self._shown_count = 0
            self._shown_rate_t = now
        ts = time.strftime("%H:%M:%S", time.localtime(evt.host_time_ns / 1e9))
        self.info.setText(
            f"<b>seq {evt.seq}</b> &nbsp; src <b>{evt.trig_src}</b> &nbsp; "
            f"mask 0x{evt.trig_mask:02x} {evt.trig_channels} &nbsp; L {evt.n_samples} &nbsp; "
            f"trig_offset {evt.trig_offset} &nbsp; t<sub>trig</sub> {evt.trig_time_s:.9f} s "
            f"&nbsp; {ts}.{evt.host_time_ns % 10**9 // 10**6:03d} &nbsp; "
            f"lost {evt.lost} &nbsp; dropped {evt.dropped}"
            + (' &nbsp; <span style="color:#d08000"><b>[SIMULATED]</b></span>'
               if evt.simulated else "")
            + f" &nbsp;|&nbsp; plotting {self._shown_rate:.1f}/s, analysis {d.calc_ms:.0f} ms")

    def closeEvent(self, e):
        self.worker.settings.paused = True     # no analysis work while hidden
        super().closeEvent(e)

    def showEvent(self, e):
        self.worker.settings.paused = self.pause.isChecked()
        super().showEvent(e)
