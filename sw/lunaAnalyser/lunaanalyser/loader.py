"""Event files: finding and loading the .npz files of luna-client / lunaGUI.

Each file holds one event, as written by lunaclient.cli.save_event():
samples (int16, (8, L), MSB-justified 12-bit codes) plus the event metadata.
The files are named luna_<host_time_ns>_<seq>.npz, so sorting on the two
numbers puts them in recording order.
"""
from __future__ import annotations

import re
import zipfile
from pathlib import Path

import numpy as np

from lunaclient.protocol import NCH, SAMPLE_RATE_HZ, Event

EVENT_RE = re.compile(r"^luna_(\d+)_(\d+)\.npz$")


def _order(p: Path):
    m = EVENT_RE.match(p.name)
    if m:
        return (0, int(m[1]), int(m[2]), str(p))
    return (1, 0, 0, str(p))                 # other names: after, by path


def find_events(directory: str | Path, recursive: bool = False) -> list[Path]:
    """Event files in a directory (optionally its subdirectories), in time order.

    Spectrometer files (spec_*.npz) are left out.
    """
    d = Path(directory)
    files = d.rglob("*.npz") if recursive else d.glob("*.npz")
    return sorted((p for p in files if p.is_file() and not p.name.startswith("spec_")),
                  key=_order)


def load_event(path: str | Path) -> Event:
    """Read one event file back into a lunaclient Event.

    Fields that save_event() does not store (bank, trig_count, dropped,
    simulated) are set to 0 / False.
    """
    if not zipfile.is_zipfile(path):
        raise ValueError("not a valid .npz file (damaged, or still being written?)")
    with np.load(path, allow_pickle=False) as z:
        if "samples" not in z.files:
            raise ValueError("not an event file (no 'samples' array)")
        samples = np.ascontiguousarray(z["samples"], dtype=np.int16)
        if samples.ndim != 2 or samples.shape[0] != NCH:
            raise ValueError(f"samples have shape {samples.shape}, expected ({NCH}, L)")

        def get(key, default):
            return z[key].item() if key in z.files else default

        thr = tuple(int(v) for v in z["thresholds"]) if "thresholds" in z.files else (0,) * NCH
        n = samples.shape[1]
        return Event(seq=int(get("seq", 0)), n_samples=n,
                     trig_sample=int(get("trig_sample", 0)),
                     start_sample=int(get("start_sample", 0)),
                     trig_offset=int(get("trig_offset", 0)),
                     trig_mask=int(get("trig_mask", 0)), trig_src=str(get("trig_src", "?")),
                     bank=0, window=int(get("window", 0)), coinc_n=int(get("coinc_n", 0)),
                     mode=int(get("mode", 0)), lost=int(get("lost", 0)), trig_count=0,
                     host_time_ns=int(get("host_time_ns", 0)),
                     sample_rate_hz=float(get("sample_rate_hz", SAMPLE_RATE_HZ)),
                     thresholds=thr, dropped=0, simulated=False, samples=samples)
