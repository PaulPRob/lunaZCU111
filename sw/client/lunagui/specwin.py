"""lunaGUI spectrum window: live spectrometer integrations (TCP 5002).

The power of each integration is shown as the mean power per 33.33 us
spectrum (power / n_spectra), against absolute frequency (subband centre +
fine-channel offset), with an optional running average over integrations,
max hold, and a waterfall of the most recent integrations.  The average,
max hold and waterfall restart when the ADC input, subband or integration
length changes.
"""
from __future__ import annotations

import time

import numpy as np
import pyqtgraph as pg
from PyQt6.QtCore import QSettings, Qt, QTimer
from PyQt6.QtWidgets import (QCheckBox, QComboBox, QHBoxLayout, QLabel, QMainWindow,
                             QPushButton, QSpinBox, QToolBar, QVBoxLayout, QWidget)

from lunaclient.protocol import Spectrum

from .plotwin import set_range


class SpecWindow(QMainWindow):
    REDRAW_HZ = 10
    WF_DECIM = 4                              # waterfall: 4096 -> 1024 columns (max)

    def __init__(self, settings: QSettings, parent=None):
        super().__init__(parent)
        self.setWindowTitle("lunaGUI – spectrometer")
        self.qs = settings
        self.resize(1400, 900)
        self._key = None                      # (input, subband, n_spectra)
        self._freq_mhz = None
        self._sum = None
        self._navg = 0
        self._hist: list[np.ndarray] = []     # recent mean spectra (for averaging)
        self._max = None
        self._wf: list[np.ndarray] = []       # waterfall rows (dB), newest last
        self._last: Spectrum | None = None
        self._dirty = False
        self._user_x = self._user_y = False

        pg.setConfigOptions(antialias=False)
        self._build_toolbar()
        central = QWidget()
        lay = QVBoxLayout(central)
        lay.setContentsMargins(4, 4, 4, 4)
        self.info = QLabel("waiting for spectra …")
        self.info.setTextFormat(Qt.TextFormat.RichText)
        lay.addWidget(self.info)
        self.glw = pg.GraphicsLayoutWidget()
        lay.addWidget(self.glw, 1)
        self.setCentralWidget(central)

        self.plot = self.glw.addPlot(row=0, col=0)
        self.plot.showGrid(x=True, y=True, alpha=0.25)
        self.plot.setLabel("bottom", "frequency", units="Hz")
        self.plot.disableAutoRange()
        self.plot.hideButtons()
        self.curve = self.plot.plot(pen=pg.mkPen((60, 140, 230), width=1))
        self.maxcurve = self.plot.plot(pen=pg.mkPen((220, 120, 40), width=1))
        self.plot.vb.sigRangeChangedManually.connect(self._user_zoom)

        self.wfplot = self.glw.addPlot(row=1, col=0)
        self.wfplot.setLabel("bottom", "frequency", units="Hz")
        self.wfplot.setLabel("left", "integrations ago")
        self.wfplot.setXLink(self.plot)
        self.wfplot.hideButtons()
        self.wfimg = pg.ImageItem(axisOrder="row-major")
        self.wfimg.setColorMap(pg.colormap.get("viridis"))
        self.wfplot.addItem(self.wfimg)
        self.glw.ci.layout.setRowStretchFactor(0, 3)
        self.glw.ci.layout.setRowStretchFactor(1, 2)

        self._apply_settings()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._redraw)
        self.timer.start(int(1000 / self.REDRAW_HZ))

    # ------------------------------------------------------------------ UI
    def _build_toolbar(self):
        q = self.qs
        tb = QToolBar("Spectrum settings")
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

        self.units = add("Units", QComboBox())
        self.units.addItems(["dB", "linear"])
        self.units.setCurrentText(str(q.value("spec/units", "dB")))
        self.units.currentIndexChanged.connect(self._apply_settings)
        self.avg = add("Average", QSpinBox())
        self.avg.setRange(1, 10000)
        self.avg.setSuffix(" integrations")
        self.avg.setToolTip("Running mean over the most recent integrations (1 = none)")
        self.avg.setValue(int(q.value("spec/avg", 1)))
        self.avg.valueChanged.connect(self._apply_settings)
        self.maxhold = add("", QCheckBox("Max hold"))
        self.maxhold.setChecked(q.value("spec/maxhold", "false") == "true")
        self.maxhold.toggled.connect(self._apply_settings)
        self.skip_first = add("", QCheckBox("Skip 'first after restart'"))
        self.skip_first.setToolTip("Ignore the first integration after a change (it is clean,\n"
                                   "but may be the first of a new setting)")
        self.skip_first.setChecked(q.value("spec/skip_first", "false") == "true")
        self.skip_first.toggled.connect(self._apply_settings)
        tb.addSeparator()
        self.wf_rows = add("Waterfall", QSpinBox())
        self.wf_rows.setRange(0, 2000)
        self.wf_rows.setSpecialValueText("off")
        self.wf_rows.setSuffix(" rows")
        self.wf_rows.setValue(int(q.value("spec/wf_rows", 200)))
        self.wf_rows.valueChanged.connect(self._apply_settings)
        tb.addSeparator()
        clr = QPushButton("Clear")
        clr.setToolTip("Restart the average, max hold and waterfall")
        clr.clicked.connect(self._clear)
        add("", clr)
        rz = QPushButton("Reset zoom")
        rz.clicked.connect(self._reset_zoom)
        add("", rz)

    def _apply_settings(self, *_):
        q = self.qs
        q.setValue("spec/units", self.units.currentText())
        q.setValue("spec/avg", self.avg.value())
        q.setValue("spec/maxhold", "true" if self.maxhold.isChecked() else "false")
        q.setValue("spec/skip_first", "true" if self.skip_first.isChecked() else "false")
        q.setValue("spec/wf_rows", self.wf_rows.value())
        db = self.units.currentText() == "dB"
        self.plot.setLabel("left", "power per spectrum" + (" (dB)" if db else ""))
        self.maxcurve.setVisible(self.maxhold.isChecked())
        self.wfplot.setVisible(self.wf_rows.value() > 0)
        if len(self._hist) > self.avg.value():
            self._hist = self._hist[-self.avg.value():]
        if self.sender() is self.units:
            self._user_y = False
        self._dirty = True

    def _user_zoom(self, mask):
        if mask[0]:
            self._user_x = True
        if mask[1]:
            self._user_y = True

    def _reset_zoom(self):
        self._user_x = self._user_y = False
        self.plot.vb.setRange(xRange=(0, 1e-12), yRange=(0, 1e-12), padding=0)
        self._dirty = True

    def _clear(self):
        self._hist, self._wf, self._max = [], [], None
        self._dirty = True

    # ---------------------------------------------------------------- data
    def on_spectrum(self, s: Spectrum):
        if self.skip_first.isChecked() and s.first:
            return
        key = (s.adc_input, s.subband, s.n_spectra)
        if key != self._key:                 # new setting: start again
            self._key = key
            self._clear()
            self._user_x = False
        f, p = s.ordered()                   # Hz, mean power per spectrum
        self._freq_mhz = f / 1e6
        self._hist.append(p)
        if len(self._hist) > self.avg.value():
            del self._hist[0]
        self._max = p.copy() if self._max is None else np.maximum(self._max, p)
        if self.wf_rows.value() > 0:
            # 4096 channels are wider than the screen: keep the maximum of each
            # group of WF_DECIM so that narrow lines stay visible
            pd = p.reshape(-1, self.WF_DECIM).max(axis=1)
            self._wf.append(10 * np.log10(np.maximum(pd, 1e-3)))
            if len(self._wf) > self.wf_rows.value():
                del self._wf[: len(self._wf) - self.wf_rows.value()]
        self._last = s
        self._dirty = True

    def _redraw(self):
        if not self._dirty or self._last is None or not self.isVisible():
            return
        self._dirty = False
        s = self._last
        f_hz = self._freq_mhz * 1e6
        mean = np.mean(self._hist, axis=0)
        db = self.units.currentText() == "dB"

        def conv(x):
            return 10 * np.log10(np.maximum(x, 1e-3)) if db else x

        y = conv(mean)
        self.curve.setData(f_hz, y)
        ys = [y]
        if self.maxhold.isChecked() and self._max is not None:
            ym = conv(self._max)
            self.maxcurve.setData(f_hz, ym)
            ys.append(ym)
        if not self._user_x:
            set_range(self.plot, 0, f_hz[0], f_hz[-1], pad=0, sticky=False)
        if not self._user_y:
            lo = min(float(np.min(v)) for v in ys)
            hi = max(float(np.max(v)) for v in ys)
            if db:
                set_range(self.plot, 1, lo - 3, hi + 3)
            else:
                set_range(self.plot, 1, 0, hi)
        if self._wf:
            img = np.array(self._wf[::-1])   # newest at the top (row 0)
            self.wfimg.setImage(img, autoLevels=False,
                                levels=(float(np.percentile(img, 1)), float(img.max())))
            df = f_hz[1] - f_hz[0]
            self.wfimg.setRect(f_hz[0] - df / 2, 0, f_hz[-1] - f_hz[0] + df, img.shape[0])
            self.wfplot.setYRange(0, img.shape[0], padding=0)
            self.wfplot.vb.invertY(True)
        k = int(np.argmax(mean))
        ts = time.strftime("%H:%M:%S", time.localtime(s.host_time_ns / 1e9))
        self.info.setText(
            f"<b>ADC {s.adc_input}</b> &nbsp; subband <b>{s.subband}</b> "
            f"({s.centre_hz / 1e6:.2f} MHz ± 61.44 MHz) &nbsp; seq <b>{s.seq}</b> &nbsp; "
            f"t<sub>int</sub> {s.tint_s:.3f} s ({s.n_spectra} spectra) &nbsp; {ts} &nbsp; "
            f"average {len(self._hist)} &nbsp; peak {self._freq_mhz[k]:.4f} MHz "
            f"({10 * np.log10(max(mean[k], 1e-3)):.1f} dB) &nbsp; "
            f"lost {s.lost} &nbsp; dropped {s.dropped}"
            + (" &nbsp; <i>first after restart</i>" if s.first else "")
            + (' &nbsp; <span style="color:#d08000"><b>[SIMULATED]</b></span>'
               if s.simulated else ""))
