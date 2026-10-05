# lunaclient

A Python client for `lunaserver` on the ZCU111 (192.168.2.10). It receives captured events from TCP 5000 and spectrometer integrations from TCP 5002, and sends control commands to TCP 5001.

```bash
uv sync
uv run luna-client status
uv run luna-client set --thresh 8000 --n 2 --window 64 --len 16384
uv run luna-client watch          # one line per event
uv run luna-client record -o data # .npz per event

uv run luna-spec status                                # spectrometer settings and counters
uv run luna-spec set --input 5 --subband 12 --tint 6   # ADC 5, 1474.56 MHz ± 61.44 MHz, 6 s
uv run luna-spec watch                                 # one line per integration
uv run luna-spec record -o spectra --skip-first        # .npz per integration
uv run --extra plot luna-spec plot                     # live matplotlib plot
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

Spectra in your own code:

```python
from lunaclient import SpectrumStream

with SpectrumStream("192.168.2.10") as spectra:
    for s in spectra:
        f_hz, p = s.ordered()          # frequency-sorted; p = mean power per spectrum
        print(s.seq, s.adc_input, s.subband, s.tint_s, f_hz[p.argmax()] / 1e6)
```

The per-event stub `on_event()` is in `lunaclient/cli.py`. The protocol is described in `../../docs/protocol.md`.

## lunaGUI (PyQt6)

A graphical front end that uses the same library (the CLI is unchanged).

```bash
uv sync --extra gui
uv run lunaGUI                    # LUNA_HOST sets the default host
uv run lunaGUI --connect --plots  # connect and open the plot window at start-up
uv run lunaGUI --connect --spectrum  # ... and the spectrum window
uv run lunaGUI --font-size 10      # default: 2 pt below the desktop font (or LUNA_GUI_FONT)
```

**Main window**
- Per channel: trigger enable (mask), threshold (16-bit units, also shown in ADC codes), hit rate from `GET RATES`, the rate of received events whose trigger mask includes the channel, and the `GET PEAKS` noise peak.
- Mode, N, window and buffer length. **Apply** sends only the settings that changed. Changing the length asks for confirmation, because it discards captured events.
- Arm/disarm, **SOFTTRIG – capture now** (forces one capture, armed or not), resync, save on the server, and a raw command line.
- Status: FPGA trigger and lost rates (from `STATUS` counter differences), received events/s and MB/s, `seq` gaps, banks, SYSREF rate, RFDC state.
- Spectrometer: enable, ADC input (0–7), subband (with its centre frequency) and integration time. **Apply** sends only what changed; every change restarts the integration. **Restart integration**, live status (`GET SPEC`: integrations, lost, restarts; spectra received and missed), and **Record spectra**: one `.npz` per integration (the same format as `luna-spec record`) in `<dir>/<prefix>spec_<date>_<time>/`, skipping integrations flagged "first after restart". The spectrum port is optional: with an older server only events and control are used.
- Recording: one `.npz` per event, written by `luna-client`'s own `save_event()`, so the files are identical to `luna-client record` output. Each run goes in `<dir>/<prefix><date>_<time>/`. A separate thread does the writing; if the disk falls behind, the number of events not saved is reported.

**Plot window**
- For each channel: the time trace with ±threshold and trigger-time markers, the Welch spectrum (dBFS; a full-scale sine reads 0 dBFS), and the histogram of the 12-bit codes (samples >> 4).
- Statistics: mean, rms, peak |x| and its time, threshold, the spectral peak, and min/max.
- *Max plots/s* (default 5) caps the plotting rate. Below that trigger rate every event is plotted; above it only the newest is, and never before the previous plot has been drawn, so plotting cannot slow down reception or recording.
- Welch segment length, overlap and window; histogram bin width and log scale; which channels to show and how many columns.
- After a mouse zoom or pan, that axis stops following the data until you press **Reset zoom**.

**Spectrum window**
- The latest integration as mean power per 33.33 µs spectrum against absolute frequency (subband centre ± 61.44 MHz), in dB or linear, with its ADC, subband, integration time and peak.
- Running average over N integrations, max hold, and a waterfall of the most recent integrations. The waterfall keeps the maximum of each group of 4 fine channels, so narrow lines stay visible.
- The average, max hold and waterfall restart automatically when the input, subband or integration length changes. *Skip 'first after restart'* ignores the first integration after a change.
