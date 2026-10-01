# lunaclient

A Python client for `lunaserver` on the ZCU111 (192.168.2.10). It receives captured events from TCP 5000 and sends control commands to TCP 5001.

```bash
uv sync
uv run luna-client status
uv run luna-client set --thresh 8000 --n 2 --window 64 --len 16384
uv run luna-client watch          # one line per event
uv run luna-client record -o data # .npz per event
```

In your own code:

```python
from lunaclient import Control, EventStream

with Control("192.168.2.10") as ctl:
    ctl.set_threshold("ALL", 8000)
    ctl.set_mode("coinc"); ctl.set_coincidence(3); ctl.set_window(64)

with EventStream("192.168.2.10") as events:
    for evt in events:
        x = evt.adc_codes()            # int16 (8, n_samples), 12-bit codes
        t = evt.time_axis_ns()         # ns relative to the trigger
        print(evt.seq, evt.trig_src, evt.trig_channels, x[:, evt.trig_offset])
```

The per-event stub `on_event()` is in `lunaclient/cli.py`. The protocol is described in `../../docs/protocol.md`.
