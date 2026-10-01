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

    def save(self):
        return self.command("SAVE")

    def close(self):
        self.sock.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
