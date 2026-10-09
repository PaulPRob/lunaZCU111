"""lunaserver control protocol (TCP 5001): one text command -> one reply line."""
from __future__ import annotations

import socket

from .protocol import CTRL_PORT


class ControlError(RuntimeError):
    pass


def _kv(reply: str) -> dict:
    out = {}
    for tok in reply.split()[1:]:
        if "=" in tok:
            k, v = tok.split("=", 1)
            out[k] = v
    return out


class Control:
    def __init__(self, host: str = "192.168.2.10", port: int = CTRL_PORT, timeout: float = 10.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.f = self.sock.makefile("rw", encoding="ascii", newline="\n")

    def command(self, cmd: str) -> str:
        """Send one command, return the reply line; raise on 'ERR'."""
        self.f.write(cmd.strip() + "\n")
        self.f.flush()
        reply = self.f.readline().strip()
        if not reply:
            raise ConnectionError("no reply from server")
        if reply.startswith("ERR"):
            raise ControlError(reply)
        return reply

    # convenience wrappers -------------------------------------------------
    def status(self) -> dict:
        return _kv(self.command("STATUS"))

    def config(self) -> dict:
        return _kv(self.command("GET CONFIG"))

    def set_threshold(self, ch, value: int):
        """ch = 0..7 or 'ALL'; value in 16-bit sample units (12-bit code * 16)."""
        return self.command(f"SET THRESH {ch} {int(value)}")

    def set_mode(self, mode: str):
        return self.command(f"SET MODE {mode.upper()}")

    def set_coincidence(self, n: int):
        return self.command(f"SET N {int(n)}")

    def set_window(self, samples: int):
        return self.command(f"SET WINDOW {int(samples)}")

    def set_mask(self, mask: int):
        return self.command(f"SET MASK 0x{int(mask):02X}")

    def set_veto(self, ch: int | None):
        """Anti-coincidence veto channel 0..7 (blocks, never triggers), or None = off."""
        return self.command("SET VETO OFF" if ch is None else f"SET VETO {int(ch)}")

    def set_length(self, samples: int):
        return self.command(f"SET LEN {int(samples)}")

    def arm(self):
        return self.command("ARM")

    def disarm(self):
        return self.command("DISARM")

    def soft_trigger(self):
        return self.command("SOFTTRIG")

    def rates(self) -> list[float]:
        return [float(x) for x in _kv(self.command("GET RATES"))["rates"].split(",")]

    def peaks(self) -> list[int]:
        return [int(x) for x in _kv(self.command("GET PEAKS"))["peaks"].split(",")]

    def resync(self):
        return self.command("RESYNC")

    # spectrometer ---------------------------------------------------------
    def spec_status(self) -> dict:
        return _kv(self.command("GET SPEC"))

    def spec_enable(self, on: bool = True):
        return self.command("SPEC ON" if on else "SPEC OFF")

    def spec_restart(self):
        return self.command("SPEC RESTART")

    def set_spec_input(self, adc: int):
        """ADC channel 0..7 feeding the spectrometer (restarts the integration)."""
        return self.command(f"SET SPEC_INPUT {int(adc)}")

    def set_spec_subband(self, subband: int):
        """Coarse channel 0..16 (centre subband*122.88 MHz) for the fine spectrum."""
        return self.command(f"SET SPEC_SUBBAND {int(subband)}")

    def set_spec_tint(self, seconds: float):
        """Integration time; rounded to a whole number of 33.33 us spectra."""
        return self.command(f"SET SPEC_TINT {float(seconds):.9g}")

    def set_spec_nspec(self, n: int):
        """Integration length as a number of spectra."""
        return self.command(f"SET SPEC_NSPEC {int(n)}")

    def save(self):
        return self.command("SAVE")

    def close(self):
        self.sock.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
