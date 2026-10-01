"""lunaserver data protocols - see docs/protocol.md.

Events (TCP 5000), one frame per captured event:
    frame header  64 bytes  (added by the server)
    event header  64 bytes  (produced by the FPGA)
    samples       int16 little endian, shape (8, n_samples), channel major

Spectra (TCP 5002), one frame per spectrometer integration:
    spectrum header  64 bytes
    power            uint64 little endian, 4096 fine channels in FFT order
"""
from __future__ import annotations

import socket
import struct
from dataclasses import dataclass, field

import numpy as np

DATA_PORT = 5000
CTRL_PORT = 5001
SPEC_PORT = 5002
NCH = 8

FRAME_MAGIC = b"LEVT"
EVENT_MAGIC = b"LUNA"
SPEC_MAGIC = b"LSPC"

SAMPLE_RATE_HZ = 3.93216e9
SPEC_NCHAN = 4096                         # fine channels per subband
SPEC_NSUB = 17                            # coarse channels 0..16
SUBBAND_HZ = SAMPLE_RATE_HZ / 32          # 122.88 MHz: spacing and width
FINE_HZ = SUBBAND_HZ / SPEC_NCHAN         # 30 kHz
SPECTRUM_S = SPEC_NCHAN / SUBBAND_HZ      # one spectrum: 33.33 us

# struct luna_frame_hdr (protocol.h)
FRAME_HDR = struct.Struct("<4sHHIIQd8HI12x")
# struct luna_event_hdr (protocol.h / capture_ctrl.vhd)
EVENT_HDR = struct.Struct("<4sHHIIQQIBBBBHBBII12x")
# struct luna_spec_hdr (protocol.h)
SPEC_HDR = struct.Struct("<4sHHIIQQdIIIIHBxI")
assert FRAME_HDR.size == 64 and EVENT_HDR.size == 64 and SPEC_HDR.size == 64

SPEC_F_SIM = 1
SPEC_F_FIRST = 2

SRC_NAMES = {1: "coinc", 2: "anti", 3: "soft"}


@dataclass
class Event:
    """One captured event."""

    seq: int                   # accepted-event sequence number (FPGA)
    n_samples: int             # samples per channel
    trig_sample: int           # absolute sample index of the trigger
    start_sample: int          # absolute sample index of samples[:, 0]
    trig_offset: int           # index of the trigger sample in 'samples'
    trig_mask: int             # channels that took part in the trigger
    trig_src: str              # "coinc", "anti" or "soft"
    bank: int
    window: int
    coinc_n: int
    mode: int                  # 0 coincidence, 1 anti-coincidence
    lost: int                  # triggers lost (no free bank) before this event
    trig_count: int
    host_time_ns: int          # server CLOCK_REALTIME at readout
    sample_rate_hz: float
    thresholds: tuple
    dropped: int               # frames the server dropped for this client
    simulated: bool
    samples: np.ndarray = field(repr=False)   # int16 (8, n_samples)

    @property
    def trig_channels(self) -> list[int]:
        return [c for c in range(NCH) if (self.trig_mask >> c) & 1]

    @property
    def trig_time_s(self) -> float:
        """Trigger time in seconds since the FPGA sample counter was reset."""
        return self.trig_sample / self.sample_rate_hz

    def adc_codes(self) -> np.ndarray:
        """Samples as 12-bit ADC codes (-2048..2047)."""
        return self.samples >> 4

    def time_axis_ns(self) -> np.ndarray:
        """Sample times relative to the trigger, in ns."""
        return (np.arange(self.n_samples) - self.trig_offset) / self.sample_rate_hz * 1e9


def parse_frame(buf: bytes) -> Event:
    (fmagic, fver, fhdr, frame_bytes, flags, host_ns, fs, *rest) = FRAME_HDR.unpack_from(buf, 0)
    thresholds, dropped = tuple(rest[:8]), rest[8]
    if fmagic != FRAME_MAGIC or fhdr != 64:
        raise ValueError(f"bad frame header {fmagic!r}")
    (emagic, ever, ehdr, seq, n, trig, start, off, mask, src, nch, bank, win, cn, mode,
     lost, tcount) = EVENT_HDR.unpack_from(buf, 64)
    if emagic != EVENT_MAGIC or nch != NCH:
        raise ValueError(f"bad event header {emagic!r}")
    data = np.frombuffer(buf, dtype="<i2", count=NCH * n, offset=128).reshape(NCH, n)
    return Event(seq=seq, n_samples=n, trig_sample=trig, start_sample=start, trig_offset=off,
                 trig_mask=mask, trig_src=SRC_NAMES.get(src, str(src)), bank=bank, window=win,
                 coinc_n=cn, mode=mode, lost=lost, trig_count=tcount, host_time_ns=host_ns,
                 sample_rate_hz=fs, thresholds=thresholds, dropped=dropped,
                 simulated=bool(flags & 1), samples=data)


@dataclass
class Spectrum:
    """One integration of the spectrometer (ADC channel 0)."""

    seq: int                   # integration sequence number (FPGA)
    n_spectra: int             # spectra accumulated
    subband: int               # coarse channel 0..16
    first: bool                # first integration after a restart (enable,
                               # subband or integration-time change)
    simulated: bool
    lost: int                  # integrations lost in the FPGA so far (banks full)
    dropped: int               # frames the server dropped for this client
    restarts: int
    end_sample: int            # ADC sample counter at the end (event time base)
    host_time_ns: int          # server CLOCK_REALTIME at readout
    sample_rate_hz: float
    power: np.ndarray = field(repr=False)   # uint64 (4096,), FFT order

    @property
    def tint_s(self) -> float:
        """Integration time in seconds."""
        return self.n_spectra * SPEC_NCHAN / (self.sample_rate_hz / 32)

    @property
    def centre_hz(self) -> float:
        """Centre frequency of the subband (first Nyquist zone)."""
        return self.subband * self.sample_rate_hz / 32

    @property
    def end_time_s(self) -> float:
        """End of the integration, s since the FPGA sample counter was reset."""
        return self.end_sample / self.sample_rate_hz

    def offsets_hz(self) -> np.ndarray:
        """Frequency of each channel (FFT order) relative to the subband centre."""
        return np.fft.fftfreq(SPEC_NCHAN, d=1.0) * (self.sample_rate_hz / 32)

    def freqs_hz(self) -> np.ndarray:
        """Absolute frequency of each channel, FFT order (matches .power)."""
        return self.centre_hz + self.offsets_hz()

    def ordered(self) -> tuple[np.ndarray, np.ndarray]:
        """(frequency_hz, mean power per spectrum), sorted by frequency."""
        return (np.fft.fftshift(self.freqs_hz()),
                np.fft.fftshift(self.power.astype(np.float64) / self.n_spectra))


def parse_spec_frame(buf: bytes) -> Spectrum:
    (magic, ver, hdr, frame_bytes, flags, host_ns, end_sample, fs, seq, nspec, dropped, lost,
     nchan, subband, restarts) = SPEC_HDR.unpack_from(buf, 0)
    if magic != SPEC_MAGIC or hdr != 64 or nchan != SPEC_NCHAN:
        raise ValueError(f"bad spectrum header {magic!r}")
    power = np.frombuffer(buf, dtype="<u8", count=nchan, offset=64)
    return Spectrum(seq=seq, n_spectra=nspec, subband=subband, first=bool(flags & SPEC_F_FIRST),
                    simulated=bool(flags & SPEC_F_SIM), lost=lost, dropped=dropped,
                    restarts=restarts, end_sample=end_sample, host_time_ns=host_ns,
                    sample_rate_hz=fs, power=power)


class _FrameStream:
    """A TCP data port: one 64-byte header (magic, frame size at byte 8) + payload."""

    magic = b""

    def __init__(self, host: str, port: int, timeout: float | None = None):
        self.sock = socket.create_connection((host, port), timeout=10)
        self.sock.settimeout(timeout)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)

    def _recv_exact(self, n: int) -> bytearray:
        buf = bytearray(n)
        view = memoryview(buf)
        got = 0
        while got < n:
            r = self.sock.recv_into(view[got:], n - got)
            if r == 0:
                raise ConnectionError("server closed the connection")
            got += r
        return buf

    def _read_frame(self) -> bytes:
        head = self._recv_exact(64)
        if bytes(head[:4]) != self.magic:
            raise ValueError("lost frame synchronisation")
        frame_bytes = struct.unpack_from("<I", head, 8)[0]
        rest = self._recv_exact(frame_bytes - 64)
        return bytes(head) + bytes(rest)

    def __iter__(self):
        while True:
            yield self.read()

    def close(self):
        self.sock.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


class EventStream(_FrameStream):
    """Iterate over events pushed by the server on the data port (5000)."""

    magic = FRAME_MAGIC

    def __init__(self, host: str = "192.168.2.10", port: int = DATA_PORT, timeout: float | None = None):
        super().__init__(host, port, timeout)

    def read(self) -> Event:
        return parse_frame(self._read_frame())


class SpectrumStream(_FrameStream):
    """Iterate over spectrometer integrations pushed on the spectrum port (5002)."""

    magic = SPEC_MAGIC

    def __init__(self, host: str = "192.168.2.10", port: int = SPEC_PORT, timeout: float | None = None):
        super().__init__(host, port, timeout)

    def read(self) -> Spectrum:
        return parse_spec_frame(self._read_frame())
