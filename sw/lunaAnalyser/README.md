# lunaAnalyser

An offline viewer for recorded events. It reads the `.npz` files written by `luna-client record` and by lunaGUI's **Record** (one file per event, `luna_<host_time_ns>_<seq>.npz`) and plots each event the way the lunaGUI plot window does: for each channel, the time trace, the Welch spectrum and the code histogram.

It uses lunaGUI's own analysis (`lunagui.dsp`) and plot panels (`lunagui.plotwin.ChannelPlots`), so the scaling and statistics are identical. It needs the `../client` package, which `uv sync` installs (editable) together with PyQt6 and pyqtgraph.

```bash
cd sw/lunaAnalyser
uv sync
uv run lunaAnalyser                              # reopens the last directory
uv run lunaAnalyser ~/data/run_20261007_101500   # or -d DIR
uv run lunaAnalyser -d ~/data -r                 # every run below ~/data
uv run lunaAnalyser ~/data/run1 -i -1            # start at the last file
```

**Files**
- **Open directory…** (Ctrl+O) or the command line chooses the directory. *Subdirectories* (`-r` / `--no-recursive`) also lists the files in its subdirectories, for example several runs. Spectrometer files (`spec_*.npz`) are ignored.
- The files are in recording order (host time, then `seq`). The list on the left, the file number box and the **|◀ ◀ ▶ ▶|** buttons move through them, as do the keys ← →, PgUp/PgDn (±10), Home/End. **Play** (Space) steps through them at the set interval.
- New files are picked up automatically, so you can browse a run that lunaGUI is still recording. **Rescan** re-reads the directory by hand.
- The header line shows the file, `seq`, trigger source, mask and channels, mode, length, trigger offset and time, the host date and time, and `lost`. The files do not store `bank`, `trig_count`, `dropped` or the simulated flag.

**Plots** (as in lunaGUI)
- *Show* 0–7 (with **All** / **None**) picks the channels to display, and *Columns* sets the grid. A channel whose trigger took part in the event is tagged **● TRIG**.
- Welch segment, overlap and window; histogram bin width and log scale; *Time: full scale* (±2048 codes).
- Zoom with the mouse wheel or right-drag, and pan with left-drag. The x axes of each plot type are linked across channels. A zoom is kept as you move from file to file, until **Reset zoom**. Right-click a plot for pyqtgraph's own menu, which includes per-plot export (PNG, SVG, CSV).

**Markers**
- Each plot type (time, spectrum, histogram) has two markers, **M1** (orange) and **M2** (blue), at the same x in every channel. **Ctrl+click** places M1 and **Shift+click** places M2. Drag a marker line to move it.
- A dot marks the nearest sample, frequency bin or histogram bin on each trace. The *Markers* table gives each shown channel's x and value, Δx and Δvalue (M2 − M1), and 1/Δx: a frequency for time markers, a period for spectrum markers.
- **Time peak → M1** and **Spectrum peak → M1** put M1 on the largest |code| or the spectral peak (DC excluded) of the *Ref ch*. **Copy table** copies the table as tab-separated text.

**Export**: **Export PNG…** (Ctrl+S) saves the header line and the plot grid as shown, including markers and zoom. The default name is the event file's name with `.png`.

The window layout and all settings are remembered between sessions.
