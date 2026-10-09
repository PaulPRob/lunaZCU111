"""lunaAnalyser main window: step through recorded events, plotted as in lunaGUI.

For each channel: the time trace with ±threshold and trigger-time markers,
the Welch spectrum (dBFS) and the histogram of the 12-bit codes. The analysis
(lunagui.dsp) and the per-channel plots (lunagui.plotwin.ChannelPlots) are
lunaGUI's own, so the plots look and scale the same.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pyqtgraph as pg
from PyQt6.QtCore import QFileSystemWatcher, QSettings, Qt, QTimer
from PyQt6.QtGui import QKeySequence, QPainter, QPixmap, QShortcut
from PyQt6.QtWidgets import (QAbstractItemView, QApplication, QCheckBox, QComboBox,
                             QDockWidget, QDoubleSpinBox, QFileDialog, QHBoxLayout,
                             QHeaderView, QLabel, QListWidget, QMainWindow, QPushButton,
                             QSpinBox, QTableWidget, QTableWidgetItem, QToolBar, QVBoxLayout,
                             QWidget)

from lunaclient.protocol import NCH, Event
from lunagui import dsp
from lunagui.plotwin import NPERSEG, OVERLAPS, WINDOWS, ChannelPlots, set_range

from .loader import find_events, load_event
from .markers import KIND_NAMES, KINDS, Markers

HELP = ("Ctrl+click: M1, Shift+click: M2, drag a marker to move it · mouse wheel / right-drag: "
        "zoom, left-drag: pan · ←/→ previous/next file, PgUp/PgDn ±10, Home/End, Space: play")
TABLE_HEAD = ["Plot", "Ch", "M1 x", "M1 value", "M2 x", "M2 value", "Δx (M2−M1)", "Δvalue",
              "1/Δx"]


@dataclass
class Analysis:
    evt: Event
    path: Path
    codes: np.ndarray              # int16 (8, L), 12-bit codes
    t_s: np.ndarray                # time relative to the trigger
    f_hz: np.ndarray
    spec_db: np.ndarray            # (8, nfreq) dBFS
    hist_edges: np.ndarray
    hist_counts: np.ndarray        # (8, nbins)
    stats: list
    thresh_codes: np.ndarray       # (8,) threshold in codes


def analyse(evt: Event, path: Path, nperseg: int, overlap: float, window: str,
            hist_bin: int) -> Analysis:
    codes = evt.adc_codes()
    f, spec = dsp.welch_dbfs(codes, evt.sample_rate_hz, nperseg, overlap, window)
    edges, counts = dsp.histograms(codes, hist_bin)
    return Analysis(evt=evt, path=path, codes=codes, t_s=evt.time_axis_ns() * 1e-9, f_hz=f,
                    spec_db=spec, hist_edges=edges, hist_counts=counts,
                    stats=dsp.channel_stats(codes),
                    thresh_codes=np.asarray(evt.thresholds, dtype=float) / 16.0)


def _bool(v) -> bool:
    return v in (True, "true", "1", 1)


class AnalyserWindow(QMainWindow):
    def __init__(self, directory: str | None = None, recursive: bool | None = None,
                 start: int | None = None):
        super().__init__()
        self.setWindowTitle("lunaAnalyser")
        self.qs = QSettings("lunaAnalyser", "lunaAnalyser")
        self.resize(1600, 1000)
        self.dir: Path | None = None
        self.files: list[Path] = []
        self.idx = -1
        self._evt: Event | None = None
        self._path: Path | None = None
        self._data: Analysis | None = None
        self.user_x = {k: False for k in KINDS}

        pg.setConfigOptions(antialias=False)
        self._build_file_toolbar()
        self.addToolBarBreak()
        self._build_plot_toolbar()

        central = QWidget()
        lay = QVBoxLayout(central)
        lay.setContentsMargins(4, 4, 4, 4)
        self.info = QLabel("Open a directory of event files (Ctrl+O)")
        self.info.setTextFormat(Qt.TextFormat.RichText)
        self.info.setWordWrap(True)
        lay.addWidget(self.info)
        self.glw = pg.GraphicsLayoutWidget()
        lay.addWidget(self.glw, 1)
        self.setCentralWidget(central)

        self.chplots = [ChannelPlots(c) for c in range(NCH)]
        for cp in self.chplots:
            # unlike the live view, keep every sample when zoomed in
            cp.tcurve.setClipToView(True)
            cp.tcurve.setDownsampling(auto=True, method="peak")
        for cp in self.chplots[1:]:      # shared x axes: zooming one channel zooms them all
            cp.time.setXLink(self.chplots[0].time)
            cp.fft.setXLink(self.chplots[0].fft)
            cp.hist.setXLink(self.chplots[0].hist)
        for cp in self.chplots:
            for kind, p in zip(KINDS, cp.items()):
                p.vb.sigRangeChangedManually.connect(
                    lambda mask, kind=kind, cp=cp, p=p: self._user_zoom(kind, cp, p, mask))
        self.markers = Markers(self.chplots, self._value_at)
        self.markers.changed.connect(self._update_marker_table)
        self.glw.scene().sigMouseClicked.connect(self._scene_click)

        self._build_file_dock()
        self._build_marker_dock()

        self.play_timer = QTimer(self)
        self.play_timer.timeout.connect(self._play_step)
        self.watcher = QFileSystemWatcher(self)
        self.watcher.directoryChanged.connect(lambda _: self.rescan_timer.start())
        self.rescan_timer = QTimer(self)
        self.rescan_timer.setSingleShot(True)
        self.rescan_timer.setInterval(500)
        self.rescan_timer.timeout.connect(self.rescan)

        for key, fn in (("Right", lambda: self.goto(self.idx + 1)),
                        ("Left", lambda: self.goto(self.idx - 1)),
                        ("PgDown", lambda: self.goto(self.idx + 10)),
                        ("PgUp", lambda: self.goto(self.idx - 10)),
                        ("Home", lambda: self.goto(0)),
                        ("End", lambda: self.goto(len(self.files) - 1)),
                        ("Space", self.play.toggle),
                        ("Ctrl+O", self._choose_dir),
                        ("Ctrl+S", self._export_png)):
            QShortcut(QKeySequence(key), self).activated.connect(fn)

        g = self.qs.value("geometry")
        if g is not None:
            self.restoreGeometry(g)
        st = self.qs.value("state")
        if st is not None:
            self.restoreState(st)
        self._apply_settings()
        self._relayout()
        self.statusBar().showMessage(HELP)

        if recursive is not None:
            self.subdirs.setChecked(recursive)
        if directory is None:
            last = self.qs.value("dir", "")
            directory = last if last and Path(last).is_dir() else None
        if directory is not None:
            self.open_dir(directory, start)

    # ------------------------------------------------------------------ UI
    @staticmethod
    def _adder(tb: QToolBar):
        def add(label, w):
            box = QWidget()
            hl = QHBoxLayout(box)
            hl.setContentsMargins(4, 0, 4, 0)
            if label:
                hl.addWidget(QLabel(label))
            hl.addWidget(w)
            tb.addWidget(box)
            return w
        return add

    def _build_file_toolbar(self):
        q = self.qs
        tb = QToolBar("Files")
        tb.setObjectName("files_toolbar")
        tb.setMovable(False)
        self.addToolBar(tb)
        add = self._adder(tb)

        b = add("", QPushButton("Open directory…"))
        b.setToolTip("Choose the directory of event files (Ctrl+O)")
        b.clicked.connect(self._choose_dir)
        self.subdirs = add("", QCheckBox("Subdirectories"))
        self.subdirs.setToolTip("Also list the files in all subdirectories, e.g. several runs")
        self.subdirs.setChecked(_bool(q.value("subdirs", "false")))
        self.subdirs.toggled.connect(self._subdirs_toggled)
        b = add("", QPushButton("Rescan"))
        b.setToolTip("Read the directory again (also done automatically when files appear)")
        b.clicked.connect(self.rescan)
        tb.addSeparator()

        for text, tip, step in (("|◀", "First file (Home)", "first"),
                                ("◀", "Previous file (←)", -1)):
            b = add("", QPushButton(text))
            b.setToolTip(tip)
            b.setFixedWidth(36)
            b.clicked.connect(lambda _, s=step: self.goto(0 if s == "first" else self.idx + s))
        self.index = add("", QSpinBox())
        self.index.setRange(0, 0)
        self.index.setKeyboardTracking(False)
        self.index.setMinimumWidth(80)
        self.index.valueChanged.connect(lambda v: self.goto(v - 1))
        self.count_lbl = add("", QLabel("/ 0"))
        for text, tip, step in (("▶", "Next file (→)", 1), ("▶|", "Last file (End)", "last")):
            b = add("", QPushButton(text))
            b.setToolTip(tip)
            b.setFixedWidth(36)
            b.clicked.connect(lambda _, s=step: self.goto(len(self.files) - 1 if s == "last"
                                                          else self.idx + s))
        self.play = add("", QPushButton("Play"))
        self.play.setCheckable(True)
        self.play.setToolTip("Step through the files automatically (Space)")
        self.play.toggled.connect(self._play_toggled)
        self.play_s = add("every", QDoubleSpinBox())
        self.play_s.setRange(0.05, 60.0)
        self.play_s.setSingleStep(0.25)
        self.play_s.setSuffix(" s")
        self.play_s.setValue(float(q.value("play_s", 1.0)))
        self.play_s.valueChanged.connect(self._play_interval)
        tb.addSeparator()

        b = add("", QPushButton("Export PNG…"))
        b.setToolTip("Save the event header and plots as shown to a PNG file (Ctrl+S)")
        b.clicked.connect(self._export_png)
        self.export_table = add("", QCheckBox("with marker table"))
        self.export_table.setToolTip("Add the marker table below the plots in the PNG")
        self.export_table.setChecked(_bool(q.value("export_table", "true")))
        self.export_table.toggled.connect(
            lambda on: self.qs.setValue("export_table", "true" if on else "false"))

    def _build_plot_toolbar(self):
        q = self.qs
        tb = QToolBar("Plot settings")
        tb.setObjectName("plot_toolbar")
        tb.setMovable(False)
        self.addToolBar(tb)
        add = self._adder(tb)

        self.ch_boxes = []
        chw = QWidget()
        hl = QHBoxLayout(chw)
        hl.setContentsMargins(4, 0, 4, 0)
        hl.addWidget(QLabel("Show:"))
        shown = int(q.value("shown", 0xFF))
        for c in range(NCH):
            cb = QCheckBox(str(c))
            cb.setChecked(bool((shown >> c) & 1))
            cb.toggled.connect(self._relayout)
            self.ch_boxes.append(cb)
            hl.addWidget(cb)
        for text, on in (("All", True), ("None", False)):
            b = QPushButton(text)
            b.setFixedWidth(44)
            b.clicked.connect(lambda _, on=on: self._show_all(on))
            hl.addWidget(b)
        tb.addWidget(chw)

        self.cols = add("Columns", QSpinBox())
        self.cols.setRange(1, 8)
        self.cols.setValue(int(q.value("cols", 4)))
        self.cols.valueChanged.connect(self._relayout)
        tb.addSeparator()

        self.nperseg = add("Welch segment", QComboBox())
        for n in NPERSEG:
            self.nperseg.addItem(str(n), n)
        self.nperseg.setToolTip("Welch segment length. Shorter = smoother spectrum, coarser\n"
                                "resolution. ≥ capture length = single periodogram.")
        self.nperseg.setCurrentText(str(q.value("nperseg", 1024)))
        self.nperseg.currentIndexChanged.connect(self._apply_settings)
        self.overlap = add("overlap", QComboBox())
        self.overlap.addItems(OVERLAPS)
        self.overlap.setCurrentText(str(q.value("overlap", "50 %")))
        self.overlap.currentIndexChanged.connect(self._apply_settings)
        self.window = add("window", QComboBox())
        self.window.addItems(WINDOWS)
        self.window.setCurrentText(str(q.value("window", "Hann")))
        self.window.currentIndexChanged.connect(self._apply_settings)
        tb.addSeparator()

        self.hbin = add("Hist bin", QSpinBox())
        self.hbin.setRange(1, 64)
        self.hbin.setSuffix(" codes")
        self.hbin.setValue(int(q.value("hist_bin", 1)))
        self.hbin.valueChanged.connect(self._apply_settings)
        self.hlog = add("", QCheckBox("log"))
        self.hlog.setChecked(_bool(q.value("hist_log", "false")))
        self.hlog.toggled.connect(self._apply_settings)
        self.fullscale = add("", QCheckBox("Time: full scale"))
        self.fullscale.setToolTip("Fix the time-plot y axis to ±2048 codes")
        self.fullscale.setChecked(_bool(q.value("fullscale", "false")))
        self.fullscale.toggled.connect(self._apply_settings)
        tb.addSeparator()
        rz = add("", QPushButton("Reset zoom"))
        rz.setToolTip("Follow the data again after zooming/panning with the mouse")
        rz.clicked.connect(self._reset_zoom)

    def _build_file_dock(self):
        self.file_list = QListWidget()
        self.file_list.currentRowChanged.connect(self.goto)
        dock = QDockWidget("Files", self)
        dock.setObjectName("files_dock")
        dock.setWidget(self.file_list)
        self.addDockWidget(Qt.DockWidgetArea.LeftDockWidgetArea, dock)

    def _build_marker_dock(self):
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(4, 4, 4, 4)
        bar = QHBoxLayout()
        bar.addWidget(QLabel("Ref ch"))
        self.ref_ch = QComboBox()
        self.ref_ch.addItems([str(c) for c in range(NCH)])
        self.ref_ch.setToolTip("Channel used by the peak buttons")
        bar.addWidget(self.ref_ch)
        for text, tip, fn in (
                ("Time peak → M1", "Put time marker M1 on the largest |code| of the ref channel",
                 lambda: self._peak_marker("time")),
                ("Spectrum peak → M1", "Put spectrum marker M1 on the spectral peak (excluding DC)"
                 " of the ref channel", lambda: self._peak_marker("fft")),
                ("Clear markers", "Remove all markers", self.markers.clear),
                ("Copy table", "Copy the marker table to the clipboard (tab separated)",
                 self._copy_markers)):
            b = QPushButton(text)
            b.setToolTip(tip)
            b.clicked.connect(fn)
            bar.addWidget(b)
        bar.addStretch(1)
        lay.addLayout(bar)
        self.mtable = self._new_table()
        lay.addWidget(self.mtable)
        dock = QDockWidget("Markers", self)
        dock.setObjectName("marker_dock")
        dock.setWidget(w)
        self.addDockWidget(Qt.DockWidgetArea.BottomDockWidgetArea, dock)

    @staticmethod
    def _new_table() -> QTableWidget:
        t = QTableWidget(0, len(TABLE_HEAD))
        t.setHorizontalHeaderLabels(TABLE_HEAD)
        t.verticalHeader().setVisible(False)
        t.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        t.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        return t

    @staticmethod
    def _fill_table(t: QTableWidget, rows: list[list[str]]):
        t.setRowCount(len(rows))
        for r, row in enumerate(rows):
            for c, text in enumerate(row):
                it = QTableWidgetItem(text)
                if c >= 2:
                    it.setTextAlignment(Qt.AlignmentFlag.AlignRight
                                        | Qt.AlignmentFlag.AlignVCenter)
                t.setItem(r, c, it)

    def _show_all(self, on: bool):
        for cb in self.ch_boxes:
            cb.blockSignals(True)
            cb.setChecked(on)
            cb.blockSignals(False)
        self._relayout()

    def _relayout(self):
        self.glw.clear()
        shown = self._shown()
        ncol = max(1, min(self.cols.value(), len(shown) or 1))
        for i, c in enumerate(shown):
            row, col = divmod(i, ncol)
            for k, item in enumerate(self.chplots[c].items()):
                self.glw.addItem(item, row=row * 3 + k, col=col)
        self.qs.setValue("shown", sum(1 << c for c in shown))
        self.qs.setValue("cols", self.cols.value())
        self._draw()
        self._update_marker_table()

    def _shown(self) -> list[int]:
        return [c for c in range(NCH) if self.ch_boxes[c].isChecked()]

    def _apply_settings(self):
        hist_log = self.hlog.isChecked()
        for cp in self.chplots:
            cp.hist.setLogMode(y=hist_log)
        q = self.qs
        q.setValue("nperseg", self.nperseg.currentData())
        q.setValue("overlap", self.overlap.currentText())
        q.setValue("window", self.window.currentText())
        q.setValue("hist_bin", self.hbin.value())
        q.setValue("hist_log", "true" if hist_log else "false")
        q.setValue("fullscale", "true" if self.fullscale.isChecked() else "false")
        if self.sender() is self.hlog:     # the y range changes scale (lin <-> log10)
            for cp in self.chplots:
                cp.user_y[id(cp.hist)] = False
        self._reanalyse()

    # ---------------------------------------------------------- zoom/markers
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
        self._draw()

    def _scene_click(self, ev):
        if ev.button() != Qt.MouseButton.LeftButton:
            return
        mods = ev.modifiers()
        if mods & Qt.KeyboardModifier.ControlModifier:
            m = 0
        elif mods & Qt.KeyboardModifier.ShiftModifier:
            m = 1
        else:
            return
        pos = ev.scenePos()
        for c in self._shown():
            for kind, p in zip(KINDS, self.chplots[c].items()):
                if p.vb.sceneBoundingRect().contains(pos):
                    self.markers.set(kind, m, p.vb.mapSceneToView(pos).x())
                    ev.accept()
                    return

    def _value_at(self, kind: str, ch: int, x: float):
        """(x of the nearest sample/bin, value, y of the dot) for one channel."""
        d = self._data
        if d is None:
            return None
        if kind == "time":
            fs, off = d.evt.sample_rate_hz, d.evt.trig_offset
            i = int(np.clip(round(x * fs + off), 0, d.codes.shape[1] - 1))
            v = float(d.codes[ch, i])
            return float(d.t_s[i]), v, v
        if kind == "fft":
            f = d.f_hz
            i = int(np.clip(round(x / f[1]), 0, f.size - 1)) if f.size > 1 else 0
            v = float(d.spec_db[ch, i])
            return float(f[i]), v, v
        e = d.hist_edges
        i = int(np.clip(np.searchsorted(e, x, side="right") - 1, 0, e.size - 2))
        n = float(d.hist_counts[ch, i])
        return 0.5 * (e[i] + e[i + 1]), n, (max(n, 0.5) if self.hlog.isChecked() else n)

    def _peak_marker(self, kind: str):
        d = self._data
        if d is None:
            return
        c = self.ref_ch.currentIndex()
        if kind == "time":
            self.markers.set("time", 0, float(d.t_s[d.stats[c].peak_idx]))
        else:
            spec = d.spec_db[c]
            k = int(np.argmax(spec[1:])) + 1 if spec.size > 1 else 0
            self.markers.set("fft", 0, float(d.f_hz[k]))

    @staticmethod
    def _fmt(kind: str, what: str, v: float) -> str:
        if kind == "time":
            return {"x": f"{v * 1e9:+.3f} ns", "y": f"{v:+.0f}",
                    "dx": f"{v * 1e9:+.3f} ns", "dy": f"{v:+.0f}"}[what]
        if kind == "fft":
            return {"x": f"{v / 1e6:.3f} MHz", "y": f"{v:.2f} dBFS",
                    "dx": f"{v / 1e6:+.3f} MHz", "dy": f"{v:+.2f} dB"}[what]
        return {"x": f"{v:+.1f}", "y": f"{v:.0f}", "dx": f"{v:+.1f}", "dy": f"{v:+.0f}"}[what]

    def _marker_rows(self) -> list[list[str]]:
        rows = []
        for kind in KINDS:
            if not self.markers.active(kind):
                continue
            for c in self._shown():
                m1, m2 = self.markers.readout(kind, c)
                row = [KIND_NAMES[kind], str(c)]
                for mv in (m1, m2):
                    row += ([self._fmt(kind, "x", mv[0]), self._fmt(kind, "y", mv[1])]
                            if mv else ["", ""])
                if m1 and m2:
                    dx, dy = m2[0] - m1[0], m2[1] - m1[1]
                    inv = ""
                    if kind == "time" and dx != 0:
                        inv = f"{1e-6 / abs(dx):.3f} MHz"
                    elif kind == "fft" and dx != 0:
                        inv = f"{1e9 / abs(dx):.3f} ns"
                    row += [self._fmt(kind, "dx", dx), self._fmt(kind, "dy", dy), inv]
                else:
                    row += ["", "", ""]
                rows.append(row)
        return rows

    def _update_marker_table(self):
        self._fill_table(self.mtable, self._marker_rows())

    def _copy_markers(self):
        lines = ["\t".join(TABLE_HEAD)] + ["\t".join(r) for r in self._marker_rows()]
        if self._path is not None:
            lines.insert(0, str(self._path))
        QApplication.clipboard().setText("\n".join(lines) + "\n")
        self.statusBar().showMessage("marker table copied", 3000)

    # ---------------------------------------------------------- files
    def _choose_dir(self):
        start = str(self.dir) if self.dir else self.qs.value("dir", "")
        d = QFileDialog.getExistingDirectory(self, "Directory of event files", start)
        if d:
            self.open_dir(d)

    def _subdirs_toggled(self, on: bool):
        self.qs.setValue("subdirs", "true" if on else "false")
        if self.dir is not None:
            self.open_dir(self.dir, keep=self._path)

    def open_dir(self, directory, start: int | None = None, keep: Path | None = None):
        """List the event files of a directory and show one.

        start: 1-based file number (negative: from the end); default the first.
        keep:  show this file if it is in the new list.
        """
        d = Path(directory).expanduser().resolve()
        if not d.is_dir():
            self.statusBar().showMessage(f"not a directory: {d}", 10000)
            return
        self.dir = d
        self.qs.setValue("dir", str(d))
        self.setWindowTitle(f"lunaAnalyser – {d}")
        self.play.setChecked(False)
        self._watch()
        self.files = find_events(d, self.subdirs.isChecked())
        self._fill_list()
        if not self.files:
            self.idx = -1
            self._evt = self._data = self._path = None
            self._clear_plots()
            self.info.setText(f"no event files (*.npz) in {d}"
                              + ("" if self.subdirs.isChecked() else
                                 " – tick <i>Subdirectories</i> to include its subdirectories"))
            return
        i = 0
        if keep is not None and keep in self.files:
            i = self.files.index(keep)
        elif start:
            i = start - 1 if start > 0 else len(self.files) + start
        self.idx = -1
        self.goto(i)

    def _watch(self):
        old = self.watcher.directories()
        if old:
            self.watcher.removePaths(old)
        if self.dir is None:
            return
        dirs = [str(self.dir)]
        if self.subdirs.isChecked():
            dirs += [str(p) for p in self.dir.rglob("*") if p.is_dir()]
        self.watcher.addPaths(dirs)

    def rescan(self):
        """Re-read the directory, staying on the current file."""
        if self.dir is None:
            return
        if not self.dir.is_dir():
            self.statusBar().showMessage(f"directory has gone: {self.dir}", 10000)
            return
        if self.subdirs.isChecked():
            self._watch()                    # new run directories
        files = find_events(self.dir, self.subdirs.isChecked())
        if files == self.files:
            return
        self.files = files
        self._fill_list()
        if self._path is not None and self._path in files:
            self.idx = files.index(self._path)
            self._sync_index()
            self._show_info()
        elif files:
            i, self.idx = min(max(self.idx, 0), len(files) - 1), -1
            self.goto(i)
        else:
            self.open_dir(self.dir)

    def _fill_list(self):
        self.file_list.blockSignals(True)
        self.file_list.clear()
        rel = self.dir if self.dir else Path(".")
        self.file_list.addItems([str(p.relative_to(rel)) for p in self.files])
        self.file_list.blockSignals(False)
        self.count_lbl.setText(f"/ {len(self.files)}")
        self.index.blockSignals(True)
        self.index.setRange(1 if self.files else 0, len(self.files))
        self.index.blockSignals(False)

    def _sync_index(self):
        for w in (self.file_list, self.index):
            w.blockSignals(True)
        self.file_list.setCurrentRow(self.idx)
        self.index.setValue(self.idx + 1)
        for w in (self.file_list, self.index):
            w.blockSignals(False)

    def goto(self, i: int):
        if not self.files:
            return
        i = int(np.clip(i, 0, len(self.files) - 1))
        if i == self.idx:
            self._sync_index()
            return
        self.idx = i
        self._sync_index()
        path = self.files[i]
        try:
            evt = load_event(path)
        except Exception as e:               # damaged, partly written or foreign file
            self._evt, self._path, self._data = None, path, None
            self._clear_plots()
            self.info.setText(f"<b>{i + 1}/{len(self.files)}</b> &nbsp; {path.name} &nbsp; "
                              f'<span style="color:#e04040">cannot read: {e}</span>')
            return
        self._evt, self._path = evt, path
        self._reanalyse()

    def _play_toggled(self, on: bool):
        self.play.setText("Pause" if on else "Play")
        if on:
            if self.idx >= len(self.files) - 1:
                self.goto(0)
            self.play_timer.start(int(self.play_s.value() * 1000))
        else:
            self.play_timer.stop()

    def _play_interval(self, v: float):
        self.qs.setValue("play_s", v)
        if self.play_timer.isActive():
            self.play_timer.setInterval(int(v * 1000))

    def _play_step(self):
        if self.idx >= len(self.files) - 1:
            self.play.setChecked(False)
        else:
            self.goto(self.idx + 1)

    # ---------------------------------------------------------- drawing
    def _reanalyse(self):
        if self._evt is None:
            return
        self._data = analyse(self._evt, self._path, self.nperseg.currentData(),
                             OVERLAPS[self.overlap.currentText()],
                             WINDOWS[self.window.currentText()], self.hbin.value())
        self._draw()
        self.markers.refresh()
        self._update_marker_table()

    def _clear_plots(self):
        for cp in self.chplots:
            for curve in (cp.tcurve, cp.fcurve, cp.hcurve):
                curve.setData([], [])
            for p in cp.items():
                cp.set_text(p, "")
        self.markers.refresh()
        self._update_marker_table()

    def _draw(self):
        d = self._data
        if d is None:
            return
        evt = d.evt
        log_h = self.hlog.isChecked()
        hx = [np.inf, -np.inf]                 # common histogram x range
        for c in self._shown():
            cp = self.chplots[c]
            st = d.stats[c]
            thr = d.thresh_codes[c]
            trig = (evt.trig_mask >> c) & 1
            cp.tcurve.setData(d.t_s, d.codes[c])
            cp.thr_hi.setValue(thr)
            cp.thr_lo.setValue(-thr)
            if not cp.user_y[id(cp.time)]:
                if self.fullscale.isChecked():
                    set_range(cp.time, 1, -2048, 2048, pad=0, sticky=False)
                else:   # include the threshold lines: shows the noise margin
                    ym = max(abs(st.vmin), abs(st.vmax), thr, 1)
                    set_range(cp.time, 1, -ym, ym, sticky=False)
            if not self.user_x["time"]:
                set_range(cp.time, 0, d.t_s[0], d.t_s[-1], pad=0, sticky=False)
            tag = ' <span style="color:#e04040">● TRIG</span>' if trig else ""
            pk_t = d.t_s[st.peak_idx] * 1e9
            cp.set_text(cp.time,
                f"<b>CH{c}</b>{tag} &nbsp; thr ±{thr:.0f}<br>"
                f"mean {st.mean:+.2f} &nbsp; rms {st.rms:.2f} &nbsp; "
                f"peak {st.peak} @ {pk_t:+.1f} ns")

            spec = d.spec_db[c]
            cp.fcurve.setData(d.f_hz, spec)
            if not cp.user_y[id(cp.fft)]:
                set_range(cp.fft, 1, float(spec[1:].min()) - 2, float(spec.max()) + 2,
                          sticky=False)
            if not self.user_x["fft"]:
                set_range(cp.fft, 0, 0, d.f_hz[-1], pad=0, sticky=False)
            k = int(np.argmax(spec[1:])) + 1 if spec.size > 1 else 0
            cp.set_text(cp.fft, f"peak {d.f_hz[k] / 1e6:.1f} MHz, {spec[k]:.1f} dBFS"
                                f" &nbsp; (Welch seg {self.nperseg.currentData()})")

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
                    set_range(cp.hist, 1, np.log10(0.5), np.log10(max(y.max(), 1)), pad=0.03,
                              sticky=False)
                else:
                    set_range(cp.hist, 1, 0, float(y.max()), pad=0.03, sticky=False)
            cp.hthr_hi.setValue(thr)
            cp.hthr_lo.setValue(-thr)
            cp.set_text(cp.hist, f"min {st.vmin} &nbsp; max {st.vmax} &nbsp; "
                                 f"mean {st.mean:+.2f} &nbsp; rms {st.rms:.2f}")

        if not self.user_x["hist"] and np.isfinite(hx[0]):
            # symmetric about 0: ±(largest |code| over the shown channels)
            m = max(abs(hx[0]), abs(hx[1]), 1)
            set_range(self.chplots[0].hist, 0, -m, m, pad=0.02, sticky=False)
        self._show_info()

    def _show_info(self):
        d = self._data
        if d is None:
            return
        evt = d.evt
        t = evt.host_time_ns
        ts = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t / 1e9))
        mode = ("anti" if evt.mode else f"coinc N={evt.coinc_n}") + f", window {evt.window}"
        if evt.veto_channel is not None:
            mode += f", veto ch{evt.veto_channel}"
        name = (d.path.relative_to(self.dir) if self.dir and d.path.is_relative_to(self.dir)
                else d.path.name)
        self.info.setText(
            f"<b>{self.idx + 1}/{len(self.files)}</b> &nbsp; {name} &nbsp;|&nbsp; "
            f"<b>seq {evt.seq}</b> &nbsp; src <b>{evt.trig_src}</b> &nbsp; "
            f"mask 0x{evt.trig_mask:02x} {evt.trig_channels} &nbsp; ({mode}) &nbsp; "
            f"L {evt.n_samples} &nbsp; trig_offset {evt.trig_offset} &nbsp; "
            f"t<sub>trig</sub> {evt.trig_time_s:.9f} s &nbsp; "
            f"{ts}.{t % 10**9 // 10**6:03d} &nbsp; lost {evt.lost}")

    def _export_png(self):
        if self._data is None:
            self.statusBar().showMessage("nothing to export", 5000)
            return
        start = Path(self.qs.value("export_dir", "") or self.dir or ".")
        fn, _ = QFileDialog.getSaveFileName(self, "Export PNG",
                                            str(start / (self._data.path.stem + ".png")),
                                            "PNG image (*.png)")
        if not fn:
            return
        if not fn.lower().endswith(".png"):
            fn += ".png"
        self.save_png(fn)

    def save_png(self, fn: str) -> bool:
        """Save the event header and the plots, as shown, to a PNG file.

        With "with marker table" ticked and markers set, the marker table is
        added below.
        """
        pix = self.centralWidget().grab()
        rows = self._marker_rows() if self.export_table.isChecked() else []
        if rows:
            # an off-screen copy of the table, tall enough for every row
            t = self._new_table()
            self._fill_table(t, rows)
            t.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
            t.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
            t.resize(pix.deviceIndependentSize().toSize().width(),
                     t.horizontalHeader().sizeHint().height() + t.verticalHeader().length()
                     + 2 * t.frameWidth())
            tpix = t.grab()
            dpr = pix.devicePixelRatio()
            out = QPixmap(pix.width(), pix.height() + round(tpix.height() * dpr))
            out.setDevicePixelRatio(dpr)
            out.fill(self.palette().window().color())
            p = QPainter(out)
            p.drawPixmap(0, 0, pix)
            p.drawPixmap(0, round(pix.height() / dpr), tpix)
            p.end()
            pix = out
        ok = pix.save(fn, "PNG")
        if ok:
            self.qs.setValue("export_dir", str(Path(fn).parent))
        self.statusBar().showMessage(f"saved {fn}" if ok else f"could not write {fn}", 8000)
        return ok

    def closeEvent(self, e):
        self.play_timer.stop()
        self.qs.setValue("geometry", self.saveGeometry())
        self.qs.setValue("state", self.saveState())
        super().closeEvent(e)
