"""lunaGUI main window: connection, trigger and spectrometer configuration,
status, recording."""
from __future__ import annotations

import os
import time

from PyQt6.QtCore import QSettings, Qt, QTimer
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (QCheckBox, QComboBox, QDoubleSpinBox, QFileDialog, QFormLayout,
                             QGridLayout, QGroupBox, QHBoxLayout, QLabel, QLineEdit,
                             QMainWindow, QMessageBox, QPlainTextEdit, QPushButton, QSpinBox,
                             QVBoxLayout, QWidget)

from lunaclient.protocol import (CTRL_PORT, DATA_PORT, NCH, SPEC_NINPUT, SPEC_NSUB,
                                 SPEC_PORT, SPECTRUM_S, SUBBAND_HZ)

from .plotwin import PlotWindow
from .specwin import SpecWindow
from .workers import ControlWorker, DataReceiver, PlotWorker, Recorder, SpecReceiver

FS = 3.93216e9


def _num(s, default=0.0):
    try:
        return float(s)
    except (TypeError, ValueError):
        return default


def _fmt_rate(r: float) -> str:
    if r >= 1e6:
        return f"{r / 1e6:.2f} M"
    if r >= 1e4:
        return f"{r / 1e3:.1f} k"
    return f"{r:.1f}"


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("lunaGUI – ZCU111 transient trigger control")
        self.qs = QSettings("CSIRO", "lunaGUI")
        self.ctl: ControlWorker | None = None
        self.rx: DataReceiver | None = None
        self.recorder = Recorder()
        self.recorder.finished.connect(self._record_finished)
        self.plotter = PlotWorker()
        self.plotter.ready.connect(self._on_plot_data)
        self.plotwin: PlotWindow | None = None
        self.srx: SpecReceiver | None = None
        self.specwin: SpecWindow | None = None
        self.server_cfg: dict = {}
        self.server_spec: dict = {}          # spectrometer part of GET CONFIG
        self._prev_status: dict | None = None
        self._prev_rx = None            # (t, events, bytes, ch_trig, seq_gaps)

        central = QWidget()
        top = QHBoxLayout(central)
        left = QVBoxLayout()
        right = QVBoxLayout()
        top.addLayout(left, 3)
        top.addLayout(right, 2)
        self.setCentralWidget(central)

        left.addWidget(self._build_connection())
        left.addWidget(self._build_trigger())
        left.addWidget(self._build_run())
        left.addWidget(self._build_spec())
        left.addStretch(1)
        right.addWidget(self._build_status())
        right.addWidget(self._build_record())
        right.addWidget(self._build_plot())
        right.addWidget(self._build_log(), 1)

        self._set_connected_ui(False)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._tick)
        self.timer.start(1000)
        geo = self.qs.value("main/geometry")
        if geo is not None:
            self.restoreGeometry(geo)

    # ============================================================ building
    def _build_connection(self):
        g = QGroupBox("Server")
        h = QHBoxLayout(g)
        self.host = QLineEdit(os.environ.get("LUNA_HOST") or self.qs.value("conn/host", "192.168.2.10"))
        self.ctrl_port = QSpinBox()
        self.ctrl_port.setRange(1, 65535)
        self.ctrl_port.setValue(int(self.qs.value("conn/ctrl_port", CTRL_PORT)))
        self.data_port = QSpinBox()
        self.data_port.setRange(1, 65535)
        self.data_port.setValue(int(self.qs.value("conn/data_port", DATA_PORT)))
        self.spec_port = QSpinBox()
        self.spec_port.setRange(1, 65535)
        self.spec_port.setValue(int(self.qs.value("conn/spec_port", SPEC_PORT)))
        self.btn_connect = QPushButton("Connect")
        self.btn_connect.clicked.connect(self._toggle_connect)
        self.conn_led = QLabel("●")
        for w in (QLabel("Host"), self.host, QLabel("ctrl"), self.ctrl_port,
                  QLabel("data"), self.data_port, QLabel("spectra"), self.spec_port,
                  self.btn_connect, self.conn_led):
            h.addWidget(w)
        return g

    def _build_trigger(self):
        g = QGroupBox("Trigger configuration")
        v = QVBoxLayout(g)
        grid = QGridLayout()
        heads = ["Ch", "In trigger", "Threshold\n(16-bit units)", "= ADC\ncodes",
                 "Hits/s\n(server)", "Triggers/s\n(this ch.)", "Noise peak\n|x| codes"]
        tips = ["", "Channel takes part in triggering (SET MASK)",
                "SET THRESH: |x| > threshold is a hit. 16-bit units = 12-bit code × 16",
                "Threshold in 12-bit ADC codes", "GET RATES: clock cycles (16 samples) per "
                "second with at least one hit on this channel",
                "Rate of received events whose trigger mask includes this channel",
                "GET PEAKS: largest |x| since the previous poll"]
        for col, (t, tip) in enumerate(zip(heads, tips)):
            lab = QLabel(f"<b>{t.replace(chr(10), '<br>')}</b>")
            lab.setAlignment(Qt.AlignmentFlag.AlignCenter)
            lab.setToolTip(tip)
            grid.addWidget(lab, 0, col)
        self.mask_cb, self.thr_spin, self.thr_code = [], [], []
        self.lab_hits, self.lab_trig, self.lab_peak = [], [], []
        mono = QFont("monospace")
        mono.setStyleHint(QFont.StyleHint.Monospace)
        for c in range(NCH):
            r = c + 1
            grid.addWidget(QLabel(f"<b>{c}</b>"), r, 0, Qt.AlignmentFlag.AlignCenter)
            cb = QCheckBox()
            cb.setChecked(True)
            grid.addWidget(cb, r, 1, Qt.AlignmentFlag.AlignCenter)
            sp = QSpinBox()
            sp.setRange(0, 32767)
            sp.setSingleStep(16)
            sp.setKeyboardTracking(False)
            code = QLabel()
            code.setFont(mono)
            sp.valueChanged.connect(lambda val, lab=code: lab.setText(f"{val / 16:.1f}"))
            sp.valueChanged.connect(self._mark_dirty)
            cb.toggled.connect(self._mark_dirty)
            grid.addWidget(sp, r, 2)
            grid.addWidget(code, r, 3, Qt.AlignmentFlag.AlignRight)
            labs = []
            for col in (4, 5, 6):
                lab = QLabel("–")
                lab.setFont(mono)
                lab.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
                lab.setMinimumWidth(70)
                grid.addWidget(lab, r, col)
                labs.append(lab)
            self.mask_cb.append(cb)
            self.thr_spin.append(sp)
            self.thr_code.append(code)
            self.lab_hits.append(labs[0])
            self.lab_trig.append(labs[1])
            self.lab_peak.append(labs[2])
            code.setText("0.0")
        v.addLayout(grid)

        h = QHBoxLayout()
        self.thr_all = QSpinBox()
        self.thr_all.setRange(0, 32767)
        self.thr_all.setSingleStep(16)
        self.thr_all.setValue(8000)
        b = QPushButton("Set all thresholds")
        b.clicked.connect(lambda: [s.setValue(self.thr_all.value()) for s in self.thr_spin])
        bp = QPushButton("From noise peaks ×")
        bp.setToolTip("Set each threshold to the factor × the channel's last noise peak")
        self.peak_factor = QDoubleSpinBox()
        self.peak_factor.setRange(1.0, 20.0)
        self.peak_factor.setSingleStep(0.5)
        self.peak_factor.setValue(3.0)
        bp.clicked.connect(self._thresh_from_peaks)
        ball = QPushButton("All in trigger")
        ball.clicked.connect(lambda: [cb.setChecked(True) for cb in self.mask_cb])
        bnone = QPushButton("None")
        bnone.clicked.connect(lambda: [cb.setChecked(False) for cb in self.mask_cb])
        for w in (self.thr_all, b, bp, self.peak_factor, ball, bnone):
            h.addWidget(w)
        h.addStretch(1)
        v.addLayout(h)

        f = QGridLayout()
        self.mode = QComboBox()
        self.mode.addItems(["COINC", "ANTI"])
        self.mode.setToolTip("Coincidence (N of the enabled channels within the window) or "
                             "anti-coincidence (one channel alone)")
        self.coinc_n = QSpinBox()
        self.coinc_n.setRange(1, 8)
        self.window = QSpinBox()
        self.window.setRange(1, 255)
        self.window.setSuffix(" samples")
        self.window_ns = QLabel()
        self.length = QSpinBox()
        self.length.setRange(4096, 16384)
        self.length.setSingleStep(32)
        self.length.setSuffix(" samples")
        self.length.setToolTip("Capture length per channel (multiple of 32). Changing it "
                               "discards events not yet read out.")
        self.length_us = QLabel()
        self.window.valueChanged.connect(lambda v: self.window_ns.setText(f"= {v / FS * 1e9:.2f} ns"))
        self.length.valueChanged.connect(lambda v: self.length_us.setText(
            f"= {v / FS * 1e6:.3f} µs, {v * NCH * 2 // 1024} KiB/event"))
        for w in (self.mode, self.coinc_n, self.window, self.length):
            sig = w.currentIndexChanged if isinstance(w, QComboBox) else w.valueChanged
            sig.connect(self._mark_dirty)
        self.mode.currentTextChanged.connect(lambda m: self.coinc_n.setEnabled(m == "COINC"))
        f.addWidget(QLabel("Mode"), 0, 0)
        f.addWidget(self.mode, 0, 1)
        f.addWidget(QLabel("N (coinc.)"), 0, 2)
        f.addWidget(self.coinc_n, 0, 3)
        f.addWidget(QLabel("Window"), 1, 0)
        f.addWidget(self.window, 1, 1)
        f.addWidget(self.window_ns, 1, 2, 1, 2)
        f.addWidget(QLabel("Buffer length"), 2, 0)
        f.addWidget(self.length, 2, 1)
        f.addWidget(self.length_us, 2, 2, 1, 2)
        f.setColumnStretch(4, 1)
        v.addLayout(f)
        self.window.setValue(64)
        self.length.setValue(16384)
        self.coinc_n.setValue(1)

        h = QHBoxLayout()
        self.btn_apply = QPushButton("Apply")
        self.btn_apply.setToolTip("Send the changed settings to the server")
        self.btn_apply.clicked.connect(self._apply_config)
        self.btn_reload = QPushButton("Reload from server")
        self.btn_reload.clicked.connect(lambda: self.ctl and self.ctl.send(refresh_config=True))
        self.btn_save = QPushButton("Save on server (SD)")
        self.btn_save.clicked.connect(lambda: self.ctl and self.ctl.send("SAVE"))
        self.dirty_lab = QLabel("")
        for w in (self.btn_apply, self.btn_reload, self.btn_save, self.dirty_lab):
            h.addWidget(w)
        h.addStretch(1)
        v.addLayout(h)
        return g

    def _build_run(self):
        g = QGroupBox("Run control")
        h = QHBoxLayout(g)
        self.btn_arm = QPushButton("Arm")
        self.btn_arm.clicked.connect(lambda: self.ctl.send("ARM", refresh_config=True))
        self.btn_disarm = QPushButton("Disarm")
        self.btn_disarm.clicked.connect(lambda: self.ctl.send("DISARM", refresh_config=True))
        self.btn_soft = QPushButton("SOFTTRIG – capture now")
        self.btn_soft.setToolTip("Force one capture on all channels now (SOFTTRIG), "
                                 "armed or not")
        self.btn_soft.clicked.connect(lambda: self.ctl.send("SOFTTRIG"))
        self.btn_resync = QPushButton("Resync (MTS)")
        self.btn_resync.clicked.connect(lambda: self.ctl.send("RESYNC"))
        self.armed_lab = QLabel("armed: ?")
        for w in (self.btn_arm, self.btn_disarm, self.btn_soft, self.btn_resync, self.armed_lab):
            h.addWidget(w)
        h.addStretch(1)
        h.addWidget(QLabel("Poll every"))
        self.poll = QDoubleSpinBox()
        self.poll.setRange(0.2, 30)
        self.poll.setSuffix(" s")
        self.poll.setValue(float(self.qs.value("conn/poll", 1.0)))
        self.poll.valueChanged.connect(self._poll_changed)
        h.addWidget(self.poll)
        self.poll_peaks = QCheckBox("peaks")
        self.poll_peaks.setChecked(True)
        self.poll_peaks.setToolTip("Also poll GET PEAKS (resets the server's peak hold)")
        self.poll_peaks.toggled.connect(self._poll_changed)
        h.addWidget(self.poll_peaks)
        self.run_buttons = [self.btn_arm, self.btn_disarm, self.btn_soft, self.btn_resync,
                            self.btn_apply, self.btn_reload, self.btn_save]
        return g

    def _build_spec(self):
        g = QGroupBox("Spectrometer (one ADC → 16-channel PFB → 4096-channel DFB)")
        v = QVBoxLayout(g)
        f = QGridLayout()
        self.spec_en = QCheckBox("Enabled")
        self.spec_input = QComboBox()
        for c in range(SPEC_NINPUT):
            self.spec_input.addItem(f"ADC {c}", c)
        self.spec_input.setToolTip("ADC channel feeding the spectrometer (SET SPEC_INPUT)")
        self.spec_sub = QSpinBox()
        self.spec_sub.setRange(0, SPEC_NSUB - 1)
        self.spec_sub.setToolTip("Coarse channel: centre = k × 122.88 MHz, 122.88 MHz wide\n"
                                 "(0 and 16 are the real DC and Nyquist channels)")
        self.spec_sub_lab = QLabel()
        self.spec_tint = QDoubleSpinBox()
        self.spec_tint.setDecimals(4)
        self.spec_tint.setRange(SPECTRUM_S, 100000.0)
        self.spec_tint.setSuffix(" s")
        self.spec_tint.setKeyboardTracking(False)
        self.spec_tint.setToolTip("Integration time, rounded to whole spectra of 33.33 µs.\n"
                                  "Below ~50 ms some integrations are lost.")
        self.spec_tint_lab = QLabel()
        self.spec_sub.valueChanged.connect(lambda k: self.spec_sub_lab.setText(
            f"centre {k * SUBBAND_HZ / 1e6:.2f} MHz"))
        self.spec_tint.valueChanged.connect(lambda t: self.spec_tint_lab.setText(
            f"= {self._spec_nspec()} spectra"))
        for w in (self.spec_en, self.spec_input, self.spec_sub, self.spec_tint):
            sig = (w.toggled if isinstance(w, QCheckBox) else
                   w.currentIndexChanged if isinstance(w, QComboBox) else w.valueChanged)
            sig.connect(self._mark_spec_dirty)
        f.addWidget(self.spec_en, 0, 0)
        f.addWidget(QLabel("Input"), 0, 1)
        f.addWidget(self.spec_input, 0, 2)
        f.addWidget(QLabel("Subband"), 1, 0)
        f.addWidget(self.spec_sub, 1, 1)
        f.addWidget(self.spec_sub_lab, 1, 2)
        f.addWidget(QLabel("Integration"), 2, 0)
        f.addWidget(self.spec_tint, 2, 1)
        f.addWidget(self.spec_tint_lab, 2, 2)
        f.setColumnStretch(3, 1)
        v.addLayout(f)
        self.spec_sub.setValue(12)
        self.spec_tint.setValue(6.0)

        h = QHBoxLayout()
        self.btn_spec_apply = QPushButton("Apply")
        self.btn_spec_apply.setToolTip("Send the changed spectrometer settings (each change "
                                       "restarts the integration)")
        self.btn_spec_apply.clicked.connect(self._apply_spec)
        self.btn_spec_restart = QPushButton("Restart integration")
        self.btn_spec_restart.clicked.connect(
            lambda: self.ctl and self.ctl.send("SPEC RESTART"))
        self.btn_spec_rec = QPushButton("Record spectra")
        self.btn_spec_rec.setCheckable(True)
        self.btn_spec_rec.setToolTip("One .npz per integration (luna-spec format) in\n"
                                     "<recording dir>/<prefix>spec_<date>_<time>/")
        self.btn_spec_rec.clicked.connect(self._toggle_spec_record)
        self.spec_dirty_lab = QLabel("")
        for w in (self.btn_spec_apply, self.btn_spec_restart, self.btn_spec_rec,
                  self.spec_dirty_lab):
            h.addWidget(w)
        h.addStretch(1)
        v.addLayout(h)
        self.spec_status = QLabel("–")
        self.spec_status.setWordWrap(True)
        self.spec_status.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        v.addWidget(self.spec_status)
        self.run_buttons += [self.btn_spec_apply, self.btn_spec_restart, self.btn_spec_rec]
        return g

    def _build_status(self):
        g = QGroupBox("Status")
        f = QFormLayout(g)
        self.st = {}
        rows = [("trig_rate", "Trigger rate (FPGA)"), ("lost_rate", "Lost triggers"),
                ("rx_rate", "Events received"), ("rx_bw", "Data rate"),
                ("gaps", "Events missed (seq gaps)"), ("events", "Server events / sent / dropped"),
                ("banks", "Banks full / capturing"), ("clients", "Data clients"),
                ("sysref", "SYSREF"), ("rfdc", "RFDC"), ("sample", "Sample counter")]
        for key, label in rows:
            lab = QLabel("–")
            lab.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
            lab.setWordWrap(True)
            self.st[key] = lab
            f.addRow(label, lab)
        h = QHBoxLayout()
        self.raw_cmd = QLineEdit()
        self.raw_cmd.setPlaceholderText("raw command, e.g. HELP")
        self.raw_cmd.returnPressed.connect(self._send_raw)
        h.addWidget(self.raw_cmd)
        b = QPushButton("Send")
        b.clicked.connect(self._send_raw)
        h.addWidget(b)
        self.run_buttons.append(b)
        f.addRow("Command", h)
        return g

    def _build_record(self):
        g = QGroupBox("Recording (.npz, luna-client format)")
        f = QFormLayout(g)
        h = QHBoxLayout()
        self.rec_dir = QLineEdit(self.qs.value("rec/dir", os.path.abspath("data")))
        b = QPushButton("…")
        b.clicked.connect(self._choose_dir)
        h.addWidget(self.rec_dir)
        h.addWidget(b)
        f.addRow("Directory", h)
        self.rec_prefix = QLineEdit(self.qs.value("rec/prefix", "run_"))
        f.addRow("Run prefix", self.rec_prefix)
        self.rec_max = QSpinBox()
        self.rec_max.setRange(0, 100_000_000)
        self.rec_max.setSpecialValueText("unlimited")
        self.rec_max.setValue(int(self.qs.value("rec/max", 0)))
        f.addRow("Stop after events", self.rec_max)
        self.btn_rec = QPushButton("Start recording")
        self.btn_rec.setCheckable(True)
        self.btn_rec.clicked.connect(self._toggle_record)
        f.addRow(self.btn_rec)
        self.rec_lab = QLabel("not recording")
        self.rec_lab.setWordWrap(True)
        self.rec_lab.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        f.addRow(self.rec_lab)
        return g

    def _build_plot(self):
        g = QGroupBox("Plots")
        h = QHBoxLayout(g)
        b = QPushButton("Open plot window")
        b.clicked.connect(self._open_plots)
        h.addWidget(b)
        b = QPushButton("Open spectrum window")
        b.clicked.connect(self._open_spectrum)
        h.addWidget(b)
        h.addStretch(1)
        return g

    def _build_log(self):
        g = QGroupBox("Log")
        v = QVBoxLayout(g)
        self.log_w = QPlainTextEdit()
        self.log_w.setReadOnly(True)
        self.log_w.setMaximumBlockCount(2000)
        v.addWidget(self.log_w)
        return g

    # ============================================================== helpers
    def log(self, msg: str):
        self.log_w.appendPlainText(time.strftime("%H:%M:%S  ") + msg)

    def _set_connected_ui(self, on: bool):
        for b in self.run_buttons:
            b.setEnabled(on)
        self.btn_connect.setText("Disconnect" if on else "Connect")
        self.conn_led.setStyleSheet(f"color: {'#20b020' if on else '#a0a0a0'}; font-size: 16pt")
        for w in (self.host, self.ctrl_port, self.data_port, self.spec_port):
            w.setEnabled(not on)

    def _mark_dirty(self, *_):
        if self.server_cfg:
            self.dirty_lab.setText(
                '<span style="color:#d08000">changed – press Apply</span>'
                if self._config_diff() else "")

    def _widgets_config(self) -> dict:
        return {"thresh": [s.value() for s in self.thr_spin],
                "mask": sum(1 << c for c, cb in enumerate(self.mask_cb) if cb.isChecked()),
                "mode": self.mode.currentText(), "n": self.coinc_n.value(),
                "window": self.window.value(), "len": self.length.value()}

    def _config_diff(self) -> list[str]:
        cfg, w = self.server_cfg, self._widgets_config()
        cmds = []
        st = cfg.get("thresh", [None] * NCH)
        if len(set(w["thresh"])) == 1 and any(a != b for a, b in zip(w["thresh"], st)):
            cmds.append(f"SET THRESH ALL {w['thresh'][0]}")
        else:
            cmds += [f"SET THRESH {c} {v}" for c, (v, old) in enumerate(zip(w["thresh"], st))
                     if v != old]
        if w["mask"] != cfg.get("mask"):
            cmds.append(f"SET MASK 0x{w['mask']:02X}")
        if w["mode"] != cfg.get("mode"):
            cmds.append(f"SET MODE {w['mode']}")
        if w["n"] != cfg.get("n"):
            cmds.append(f"SET N {w['n']}")
        if w["window"] != cfg.get("window"):
            cmds.append(f"SET WINDOW {w['window']}")
        if w["len"] != cfg.get("len"):
            cmds.append(f"SET LEN {w['len']}")
        return cmds

    # ------------------------------------------------------- spectrometer
    def _spec_nspec(self) -> int:
        return max(1, int(round(self.spec_tint.value() / SPECTRUM_S)))

    def _spec_widgets(self) -> dict:
        return {"enable": self.spec_en.isChecked(), "input": self.spec_input.currentData(),
                "subband": self.spec_sub.value(), "nspec": self._spec_nspec()}

    def _spec_diff(self) -> list[str]:
        cfg, w = self.server_spec, self._spec_widgets()
        cmds = []
        if w["input"] != cfg.get("input"):
            cmds.append(f"SET SPEC_INPUT {w['input']}")
        if w["subband"] != cfg.get("subband"):
            cmds.append(f"SET SPEC_SUBBAND {w['subband']}")
        if w["nspec"] != cfg.get("nspec"):
            cmds.append(f"SET SPEC_NSPEC {w['nspec']}")
        if w["enable"] != cfg.get("enable"):
            cmds.append("SPEC ON" if w["enable"] else "SPEC OFF")
        return cmds

    def _mark_spec_dirty(self, *_):
        if self.server_spec:
            self.spec_dirty_lab.setText(
                '<span style="color:#d08000">changed – press Apply</span>'
                if self._spec_diff() else "")

    def _apply_spec(self):
        if not self.ctl:
            return
        cmds = self._spec_diff()
        if not cmds:
            self.log("spectrometer: nothing changed")
            return
        self.ctl.send(*cmds, refresh_config=True)

    def _toggle_spec_record(self, checked: bool):
        if not checked:
            if self.srx is not None:
                self.srx.stop_record()
                self.log(f"spectrum recording stopped: {self.srx.written} integrations")
            self.btn_spec_rec.setText("Record spectra")
            self.btn_spec_rec.setStyleSheet("")
            return
        if self.srx is None:
            self.btn_spec_rec.setChecked(False)
            return
        try:
            d = self.srx.start_record(self.rec_dir.text(), self.rec_prefix.text(),
                                      skip_first=True)
        except OSError as e:
            self.btn_spec_rec.setChecked(False)
            QMessageBox.warning(self, "Recording", f"Cannot create the directory:\n{e}")
            return
        self.btn_spec_rec.setText("Stop recording spectra")
        self.btn_spec_rec.setStyleSheet("background-color: #c03030; color: white")
        self.log(f"recording spectra to {d} (skipping 'first after restart')")

    def _spec_rec_error(self, msg: str):
        self.btn_spec_rec.setChecked(False)
        self._toggle_spec_record(False)
        self.log(msg)

    def _open_spectrum(self):
        if self.specwin is None:
            self.specwin = SpecWindow(self.qs)
        self.specwin.show()
        self.specwin.raise_()
        self.specwin.activateWindow()

    def _on_spectrum(self, s):
        if self.specwin is not None:
            self.specwin.on_spectrum(s)

    # ============================================================ actions
    def _toggle_connect(self):
        if self.ctl is not None or self.rx is not None:
            self._disconnect()
            return
        host = self.host.text().strip()
        self.qs.setValue("conn/host", host)
        self.qs.setValue("conn/ctrl_port", self.ctrl_port.value())
        self.qs.setValue("conn/data_port", self.data_port.value())
        self.qs.setValue("conn/spec_port", self.spec_port.value())
        self._prev_status = None
        self._prev_rx = None
        self.ctl = ControlWorker(host, self.ctrl_port.value(), self.poll.value(),
                                 self.poll_peaks.isChecked())
        ctl = self.ctl
        self.ctl.connected.connect(lambda ok, m: self._link_status(ctl, ok, m))
        self.ctl.reply.connect(lambda c, r: self.log(f"> {c}\n  {r}"))
        self.ctl.error.connect(self._ctl_error)
        self.ctl.config.connect(self._on_config)
        self.ctl.status.connect(self._on_status)
        self.ctl.start()
        self.rx = DataReceiver(host, self.data_port.value(), self.recorder, self.plotter)
        rx = self.rx
        self.rx.connected.connect(lambda ok, m: self._link_status(rx, ok, m))
        self.rx.start()
        # the spectrum port is optional (older servers have none): log only
        self.srx = SpecReceiver(host, self.spec_port.value())
        self.srx.connected.connect(lambda ok, m: self.log(m))
        self.srx.spectrum.connect(self._on_spectrum)
        self.srx.rec_error.connect(self._spec_rec_error)
        self.srx.start()
        self._set_connected_ui(True)
        self.log(f"connecting to {host} …")

    def _disconnect(self):
        if self.recorder.active:
            self.recorder.stop()
        ctl, rx, srx = self.ctl, self.rx, self.srx
        self.ctl = self.rx = self.srx = None
        if ctl:
            ctl.stop()
        if rx:
            rx.stop()
        if srx:
            srx.stop()
        if self.btn_spec_rec.isChecked():
            self.btn_spec_rec.setChecked(False)
            self.btn_spec_rec.setText("Record spectra")
            self.btn_spec_rec.setStyleSheet("")
        self._set_connected_ui(False)
        self.server_cfg = {}
        self.server_spec = {}
        self.dirty_lab.setText("")
        self.spec_dirty_lab.setText("")

    def _link_status(self, worker, ok: bool, msg: str):
        self.log(msg)
        if not ok and worker is not None and worker in (self.ctl, self.rx):
            self._disconnect()

    def _ctl_error(self, cmd: str, err: str):
        self.log(f"> {cmd}\n  {err}")
        self.statusBar().showMessage(f"{cmd}: {err}", 8000)

    def _apply_config(self):
        if not self.ctl:
            return
        cmds = self._config_diff()
        if any(c.startswith("SET LEN") for c in cmds):
            r = QMessageBox.question(self, "Change buffer length",
                                     "Changing the capture length discards captured events "
                                     "that have not been read out. Continue?")
            if r != QMessageBox.StandardButton.Yes:
                return
        if not cmds:
            self.log("nothing changed")
            return
        self.ctl.send(*cmds, refresh_config=True)

    def _thresh_from_peaks(self):
        pk = getattr(self, "_last_peaks", None)
        if not pk:
            QMessageBox.information(self, "No peaks", "No GET PEAKS data yet (connect, and "
                                    "enable peak polling).")
            return
        for c, p in enumerate(pk[:NCH]):
            self.thr_spin[c].setValue(min(32767, int(round(p * self.peak_factor.value()))))

    def _send_raw(self):
        t = self.raw_cmd.text().strip()
        if t and self.ctl:
            self.ctl.send(t)
            self.raw_cmd.clear()

    def _poll_changed(self, *_):
        self.qs.setValue("conn/poll", self.poll.value())
        if self.ctl:
            self.ctl.poll_s = self.poll.value()
            self.ctl.poll_peaks = self.poll_peaks.isChecked()

    def _choose_dir(self):
        d = QFileDialog.getExistingDirectory(self, "Recording directory", self.rec_dir.text())
        if d:
            self.rec_dir.setText(d)

    def _toggle_record(self, checked: bool):
        if checked:
            try:
                d = self.recorder.start(self.rec_dir.text(), self.rec_prefix.text(),
                                        self.rec_max.value())
            except OSError as e:
                self.btn_rec.setChecked(False)
                QMessageBox.warning(self, "Recording", f"Cannot create the run directory:\n{e}")
                return
            self.qs.setValue("rec/dir", self.rec_dir.text())
            self.qs.setValue("rec/prefix", self.rec_prefix.text())
            self.qs.setValue("rec/max", self.rec_max.value())
            self.btn_rec.setText("Stop recording")
            self.btn_rec.setStyleSheet("background-color: #c03030; color: white")
            self.log(f"recording to {d}")
        else:
            self.recorder.stop()

    def _record_finished(self, msg: str):
        self.btn_rec.setChecked(False)
        self.btn_rec.setText("Start recording")
        self.btn_rec.setStyleSheet("")
        self.log(msg)
        self.rec_lab.setText(msg)

    def _open_plots(self):
        if self.plotwin is None:
            self.plotwin = PlotWindow(self.plotter, self.qs)
        self.plotwin.show()
        self.plotwin.raise_()
        self.plotwin.activateWindow()

    def _on_plot_data(self, d):
        if self.plotwin is not None:
            self.plotwin.on_data(d)          # calls gui_done() when drawn
        else:
            self.plotter.gui_done()

    # ============================================================ updates
    def _on_config(self, kv: dict):
        try:
            cfg = {"thresh": [int(x) for x in kv["thresh"].split(",")],
                   "mask": int(kv["mask"], 16), "mode": kv["mode"].upper(),
                   "n": int(kv["n"]), "window": int(kv["window"]), "len": int(kv["len"]),
                   "armed": kv.get("armed") == "1"}
        except (KeyError, ValueError) as e:
            self.log(f"could not parse GET CONFIG: {e} {kv}")
            return
        self.server_cfg = cfg
        for c in range(NCH):
            self.thr_spin[c].setValue(cfg["thresh"][c])
            self.mask_cb[c].setChecked(bool((cfg["mask"] >> c) & 1))
        self.mode.setCurrentText(cfg["mode"])
        self.coinc_n.setValue(cfg["n"])
        self.window.setValue(cfg["window"])
        self.length.setValue(cfg["len"])
        self._show_armed(cfg["armed"])
        self.dirty_lab.setText("")
        if "spec_nspec" in kv:                    # server with the spectrometer
            try:
                sc = {"enable": kv.get("spec_enable") == "1",
                      "input": int(kv.get("spec_input", "0")),
                      "subband": int(kv["spec_subband"]), "nspec": int(kv["spec_nspec"])}
            except (KeyError, ValueError) as e:
                self.log(f"could not parse spectrometer config: {e}")
                return
            self.server_spec = sc
            self.spec_en.setChecked(sc["enable"])
            self.spec_input.setCurrentIndex(sc["input"])
            self.spec_sub.setValue(sc["subband"])
            self.spec_tint.setValue(sc["nspec"] * SPECTRUM_S)
            self.spec_dirty_lab.setText("")

    def _show_armed(self, armed: bool):
        self.armed_lab.setText("<b style='color:#20a020'>ARMED</b>" if armed
                               else "<b style='color:#c03030'>DISARMED</b>")

    def _on_status(self, st: dict):
        prev, self._prev_status = self._prev_status, st
        self._show_armed(st.get("armed") == "1")
        rates = st.get("_rates", [])
        for c in range(NCH):
            self.lab_hits[c].setText(_fmt_rate(rates[c]) if c < len(rates) else "–")
        pk = st.get("_peaks")
        if pk:
            self._last_peaks = pk
            for c in range(NCH):
                self.lab_peak[c].setText(f"{pk[c] / 16:.0f}" if c < len(pk) else "–")
        else:
            for lab in self.lab_peak:
                lab.setText("–")
        if prev is not None:
            dt = st["_t"] - prev["_t"]
            if dt > 0:
                tr = (_num(st.get("triggers")) - _num(prev.get("triggers"))) / dt
                lr = (_num(st.get("lost")) - _num(prev.get("lost"))) / dt
                self.st["trig_rate"].setText(f"<b>{_fmt_rate(max(tr, 0))}/s</b>")
                self.st["lost_rate"].setText(f"{_fmt_rate(max(lr, 0))}/s "
                                             f"(total {st.get('lost', '?')})")
                ds = _num(st.get("sysref")) - _num(prev.get("sysref"))
                self.st["sysref"].setText(f"{st.get('sysref')}  ({ds / dt / 1e6:.3f} MHz)")
        else:
            self.st["sysref"].setText(st.get("sysref", "–"))
        self.st["events"].setText(f"{st.get('events')} / {st.get('sent')} / {st.get('dropped')}")
        self.st["banks"].setText(f"{st.get('banks_full')} / {st.get('capturing')}")
        self.st["clients"].setText(st.get("clients", "–"))
        self.st["sample"].setText(st.get("sample", "–"))
        sp = st.get("_spec")
        if sp:
            if sp.get("present") != "1":
                self.spec_status.setText("no spectrometer in this bitstream")
            else:
                c = self.srx.c if self.srx is not None else None
                rec = (f" &nbsp; recording: {self.srx.written} saved"
                       if self.srx is not None and self.srx.rec_dir else "")
                self.spec_status.setText(
                    f"{'<b>running</b>' if sp.get('enabled') == '1' else 'disabled'} &nbsp; "
                    f"ADC {sp.get('input', '0')}, subband {sp.get('subband')} "
                    f"({sp.get('centre_mhz')} MHz), {float(sp.get('tint', 0)):.4g} s &nbsp; "
                    f"integrations {sp.get('integrations')} &nbsp; lost {sp.get('lost')} &nbsp; "
                    f"restarts {sp.get('restarts')} &nbsp; spectrum clients {sp.get('clients')}"
                    + (f" &nbsp; received {c.received}, missed {c.seq_gaps}" if c else "")
                    + rec)
        known = {"armed", "mode", "n", "window", "mask", "len", "banks_full", "capturing",
                 "triggers", "lost", "events", "clients", "sent", "dropped", "sample", "sysref",
                 "spec", "spectra"}
        self.st["rfdc"].setText(" ".join(f"{k}={v}" for k, v in st.items()
                                         if k not in known and not k.startswith("_")))

    def _tick(self):
        """1 s: client-side rates from the receiver counters, recording status."""
        rx = self.rx
        if rx is not None:
            c = rx.c
            now = time.monotonic()
            cur = (now, c.events, c.bytes, list(c.ch_trig))
            if self._prev_rx is not None:
                t0, e0, b0, ch0 = self._prev_rx
                dt = now - t0
                if dt > 0:
                    self.st["rx_rate"].setText(f"{_fmt_rate((c.events - e0) / dt)}/s "
                                               f"(total {c.events})"
                                               + ("  [SIMULATED]" if c.simulated else ""))
                    self.st["rx_bw"].setText(f"{(c.bytes - b0) / dt / 1e6:.1f} MB/s")
                    for ch in range(NCH):
                        self.lab_trig[ch].setText(_fmt_rate((c.ch_trig[ch] - ch0[ch]) / dt))
            self._prev_rx = cur
            self.st["gaps"].setText(f"{c.seq_gaps}  (server dropped for us: {c.last_dropped}, "
                                    f"FPGA lost: {c.last_lost})")
        r = self.recorder
        if r.active:
            self.rec_lab.setText(f"recording to {r.run_dir}\n{r.written} events, "
                                 f"{r.bytes / 1e6:.1f} MB written, queue {r.queued}"
                                 + (f", {r.overflow} NOT SAVED (disk too slow)" if r.overflow else ""))

    def closeEvent(self, e):
        self.qs.setValue("main/geometry", self.saveGeometry())
        self._disconnect()
        self.plotter.stop()
        if self.plotwin is not None:
            self.plotwin.close()
        if self.specwin is not None:
            self.specwin.close()
        super().closeEvent(e)
