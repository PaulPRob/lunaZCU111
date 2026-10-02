"""Background threads for lunaGUI.

ControlWorker  owns the control socket (TCP 5001): queued commands + periodic
               STATUS / GET RATES / GET PEAKS polling.
DataReceiver   reads events from the data port (TCP 5000), keeps counters,
               hands every event to the Recorder (when recording) and offers
               it to the PlotWorker.
Recorder       writes events to .npz files (luna-client format) on its own thread, so that slow
               disks never stall the receiver.
PlotWorker     rate-limited analysis for the plot window: at low trigger rates
               every event is analysed, at high rates only the newest event
               every 1/max_rate seconds, and never before the GUI has drawn the
               previous one.

Signals are emitted from plain Python threads; Qt delivers them to the GUI
thread as queued connections.
"""
from __future__ import annotations

import os
import queue
import socket
import threading
import time
from dataclasses import dataclass, field

import numpy as np
from PyQt6.QtCore import QObject, pyqtSignal

from lunaclient.cli import save_event
from lunaclient.control import Control, ControlError, _kv
from lunaclient.protocol import NCH, Event, EventStream

from . import dsp


# --------------------------------------------------------------------------
# control
# --------------------------------------------------------------------------
class ControlWorker(QObject):
    connected = pyqtSignal(bool, str)        # ok, message
    reply = pyqtSignal(str, str)             # command, reply line
    error = pyqtSignal(str, str)             # command, error text
    config = pyqtSignal(dict)                # parsed GET CONFIG
    status = pyqtSignal(dict)                # STATUS + rates + peaks + t

    def __init__(self, host: str, port: int, poll_s: float = 1.0, poll_peaks: bool = True):
        super().__init__()
        self.host, self.port = host, port
        self.poll_s = poll_s
        self.poll_peaks = poll_peaks
        self._q: queue.Queue = queue.Queue()
        self._stop = threading.Event()
        self._ctl: Control | None = None
        self._thread = threading.Thread(target=self._run, name="luna-control", daemon=True)

    def start(self):
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._q.put(None)
        if self._ctl is not None:
            try:
                self._ctl.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self._thread.join(timeout=3)

    def send(self, *commands: str, refresh_config: bool = False, quiet: bool = False):
        """Queue commands; optionally follow them with GET CONFIG."""
        self._q.put((list(commands), refresh_config, quiet))

    def _exec(self, cmd: str, quiet: bool = False) -> str | None:
        try:
            r = self._ctl.command(cmd)
        except ControlError as e:
            self.error.emit(cmd, str(e))
            return None
        if not quiet:
            self.reply.emit(cmd, r)
        return r

    def _poll(self):
        st = _kv(self._ctl.command("STATUS"))
        st["_t"] = time.monotonic()
        rr = _kv(self._ctl.command("GET RATES"))
        st["_rates"] = [float(x) for x in rr.get("rates", "").split(",") if x]
        st["_rate_interval"] = float(rr.get("interval", "0") or 0)
        if self.poll_peaks:
            pk = _kv(self._ctl.command("GET PEAKS"))
            st["_peaks"] = [int(x) for x in pk.get("peaks", "").split(",") if x]
        self.status.emit(st)

    def _run(self):
        try:
            self._ctl = Control(self.host, self.port, timeout=5.0)
            self._ctl.command("GET RATES")       # restart the hit-rate interval
            self.connected.emit(True, f"control connected to {self.host}:{self.port}")
            self.config.emit(_kv(self._ctl.command("GET CONFIG")))
        except (OSError, ControlError) as e:
            self.connected.emit(False, f"control connection failed: {e}")
            return
        next_poll = time.monotonic()
        try:
            while not self._stop.is_set():
                timeout = max(0.0, next_poll - time.monotonic())
                try:
                    item = self._q.get(timeout=timeout)
                except queue.Empty:
                    item = ()
                if self._stop.is_set():
                    break
                if item:
                    cmds, refresh, quiet = item
                    for c in cmds:
                        self._exec(c, quiet)
                    if refresh:
                        r = self._exec("GET CONFIG", quiet=True)
                        if r:
                            self.config.emit(_kv(r))
                if time.monotonic() >= next_poll:
                    self._poll()
                    next_poll = time.monotonic() + self.poll_s
        except (OSError, ConnectionError, ValueError) as e:
            if not self._stop.is_set():
                self.connected.emit(False, f"control connection lost: {e}")
                return
        finally:
            try:
                self._ctl.close()
            except OSError:
                pass
        self.connected.emit(False, "control disconnected")


# --------------------------------------------------------------------------
# recording
# --------------------------------------------------------------------------
class Recorder(QObject):
    """Writes one .npz per event into a run directory, on its own thread.

    The files are written by luna-client's own save_event(), so they are
    identical to those of `luna-client record` (raw int16 samples (8, L) plus
    the event metadata).
    """
    finished = pyqtSignal(str)               # message

    QUEUE_EVENTS = 1024                      # ~256 MiB at L = 16384

    def __init__(self):
        super().__init__()
        self._q: queue.Queue = queue.Queue(maxsize=self.QUEUE_EVENTS)
        self._thread: threading.Thread | None = None
        self.active = False
        self.run_dir = ""
        self.written = 0
        self.bytes = 0
        self.overflow = 0
        self._accepted = 0
        self.max_events = 0

    @property
    def queued(self) -> int:
        return self._q.qsize()

    def start(self, outdir: str, prefix: str, max_events: int) -> str:
        stamp = time.strftime("%Y%m%d_%H%M%S")
        self.run_dir = os.path.join(outdir, f"{prefix}{stamp}")
        os.makedirs(self.run_dir, exist_ok=True)
        self.written = self.bytes = self.overflow = self._accepted = 0
        self.max_events = max_events
        self._q = queue.Queue(maxsize=self.QUEUE_EVENTS)
        self.active = True
        self._thread = threading.Thread(target=self._run, name="luna-record", daemon=True)
        self._thread.start()
        return self.run_dir

    def put(self, evt: Event):
        """Called from the receiver thread."""
        if not self.active:
            return
        if self.max_events and self._accepted >= self.max_events:
            return
        try:
            self._q.put_nowait(evt)
            self._accepted += 1
            if self.max_events and self._accepted >= self.max_events:
                self._q.put(None)            # sentinel: stop after these
        except queue.Full:
            self.overflow += 1

    def stop(self):
        if self.active and self._thread is not None:
            self.active = False
            self._q.put(None)

    def _run(self):
        msg = ""
        try:
            while True:
                evt = self._q.get()
                if evt is None:
                    break
                save_event(evt, self.run_dir)
                self.written += 1
                self.bytes += evt.samples.nbytes
            msg = f"recording stopped: {self.written} events in {self.run_dir}"
        except OSError as e:
            msg = f"recording failed: {e}"
        if self.overflow:
            msg += f" ({self.overflow} events not saved: disk too slow)"
        self.active = False
        self.finished.emit(msg)

# --------------------------------------------------------------------------
# plotting
# --------------------------------------------------------------------------
@dataclass
class PlotSettings:
    max_rate: float = 5.0          # plots per second, upper limit
    nperseg: int = 1024            # Welch segment length
    overlap: float = 0.5
    window: str = "hann"
    hist_bin: int = 1              # codes per histogram bin
    paused: bool = False


@dataclass
class PlotData:
    evt: Event
    codes: np.ndarray              # int16 (8, L), 12-bit codes
    t_ns: np.ndarray
    freq_mhz: np.ndarray
    spec_db: np.ndarray            # (8, nfreq)
    hist_edges: np.ndarray
    hist_counts: np.ndarray        # (8, nbins)
    stats: list
    thresh_codes: np.ndarray       # (8,) float
    calc_ms: float = 0.0
    replot: bool = False


class PlotWorker(QObject):
    ready = pyqtSignal(object)               # PlotData

    def __init__(self):
        super().__init__()
        self.settings = PlotSettings()
        self._lock = threading.Lock()
        self._latest: Event | None = None
        self._last_plotted: Event | None = None
        self._new = threading.Event()
        self._gui_free = threading.Event()
        self._gui_free.set()
        self._replot = False
        self._stop = threading.Event()
        self.plotted = 0
        self._thread = threading.Thread(target=self._run, name="luna-plot", daemon=True)
        self._thread.start()

    def offer(self, evt: Event):
        """Receiver thread: newest event replaces any not yet plotted."""
        with self._lock:
            self._latest = evt
        self._new.set()

    def gui_done(self):
        """GUI thread: the previous PlotData has been drawn."""
        self._gui_free.set()

    def replot(self):
        """Settings changed: recompute (the frozen event when paused)."""
        with self._lock:
            self._replot = self._last_plotted is not None
        self._new.set()

    def stop(self):
        self._stop.set()
        self._new.set()
        self._gui_free.set()
        self._thread.join(timeout=2)

    def _run(self):
        last = 0.0
        while not self._stop.is_set():
            self._new.wait()
            if self._stop.is_set():
                break
            # rate limit: at most max_rate per second, and only once the GUI
            # has finished drawing; meanwhile newer events overwrite _latest
            while not self._stop.is_set():
                s = self.settings
                wait = (last + 1.0 / max(s.max_rate, 0.01)) - time.monotonic()
                if wait > 0:
                    time.sleep(min(wait, 0.1))
                    continue
                if not self._gui_free.wait(0.1):
                    if time.monotonic() - last < 5.0:
                        continue
                    self._gui_free.set()     # watchdog: never stall for good
                if s.paused and not self._replot:
                    time.sleep(0.1)
                    continue
                break
            with self._lock:
                replot, self._replot = self._replot, False
                if replot and (self.settings.paused or self._latest is None):
                    evt = self._last_plotted         # keep _latest for later
                else:
                    evt, self._latest = self._latest, None
                if self._latest is None:
                    self._new.clear()
            if evt is None or self._stop.is_set():
                continue
            last = time.monotonic()
            try:
                data = self._analyse(evt)
            except Exception as e:                       # never kill the thread
                print(f"lunaGUI plot analysis error: {e}")
                continue
            data.replot = replot
            self._last_plotted = evt
            self.plotted += 1
            self._gui_free.clear()
            if self._stop.is_set():
                break
            try:
                self.ready.emit(data)
            except RuntimeError:                 # Qt objects gone at shutdown
                break

    def _analyse(self, evt: Event) -> PlotData:
        t0 = time.perf_counter()
        s = self.settings
        codes = evt.adc_codes()                       # correct the 4-bit shift
        f, spec = dsp.welch_dbfs(codes, evt.sample_rate_hz, s.nperseg, s.overlap, s.window)
        edges, counts = dsp.histograms(codes, s.hist_bin)
        return PlotData(evt=evt, codes=codes, t_ns=evt.time_axis_ns(), freq_mhz=f / 1e6,
                        spec_db=spec, hist_edges=edges, hist_counts=counts,
                        stats=dsp.channel_stats(codes),
                        thresh_codes=np.asarray(evt.thresholds, dtype=float) / 16.0,
                        calc_ms=(time.perf_counter() - t0) * 1e3)


# --------------------------------------------------------------------------
# data receiver
# --------------------------------------------------------------------------
@dataclass
class RxCounters:
    events: int = 0
    bytes: int = 0
    seq_gaps: int = 0              # events missed (gaps in seq), incl. server drops
    last_seq: int = -1
    last_lost: int = 0             # FPGA lost count reported in the last event
    last_dropped: int = 0
    ch_trig: list = field(default_factory=lambda: [0] * NCH)   # events per trigger channel
    simulated: bool = False


class DataReceiver(QObject):
    connected = pyqtSignal(bool, str)

    def __init__(self, host: str, port: int, recorder: Recorder, plotter: PlotWorker):
        super().__init__()
        self.host, self.port = host, port
        self.recorder, self.plotter = recorder, plotter
        self.c = RxCounters()
        self._stream: EventStream | None = None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="luna-data", daemon=True)

    def start(self):
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._stream is not None:
            try:
                self._stream.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self._thread.join(timeout=3)

    def _run(self):
        try:
            self._stream = EventStream(self.host, self.port)
        except OSError as e:
            self.connected.emit(False, f"data connection failed: {e}")
            return
        self.connected.emit(True, f"data connected to {self.host}:{self.port}")
        c = self.c
        try:
            while not self._stop.is_set():
                evt = self._stream.read()
                c.events += 1
                c.bytes += evt.samples.nbytes + 128
                if c.last_seq >= 0 and evt.seq > c.last_seq + 1:
                    c.seq_gaps += evt.seq - c.last_seq - 1
                c.last_seq = evt.seq
                c.last_lost = evt.lost
                c.last_dropped = evt.dropped
                c.simulated = evt.simulated
                m = evt.trig_mask
                for ch in range(NCH):
                    if (m >> ch) & 1:
                        c.ch_trig[ch] += 1
                self.recorder.put(evt)
                self.plotter.offer(evt)
        except (OSError, ConnectionError, ValueError) as e:
            if not self._stop.is_set():
                self.connected.emit(False, f"data connection lost: {e}")
                return
        finally:
            try:
                self._stream.close()
            except OSError:
                pass
        self.connected.emit(False, "data disconnected")
