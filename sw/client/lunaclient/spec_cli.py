"""luna-spec : spectrometer client for lunaserver.

The FPGA takes one ADC channel (0-7, SET SPEC_INPUT), splits it into 17
coarse channels ("subbands") of
122.88 MHz (subband k is centred on k * 122.88 MHz), passes one of them to a
4096-channel filter bank (30 kHz channels) and integrates the power.  Each
integration arrives on TCP 5002.

examples
  luna-spec status
  luna-spec set --input 0 --subband 12 --tint 6 --on --save
  luna-spec watch                          # one line per integration
  luna-spec record -o spectra/ --skip-first
  luna-spec plot                           # live plot (needs matplotlib)
"""
from __future__ import annotations

import argparse
import os
import sys
import time

import numpy as np

from .control import Control, ControlError
from .protocol import CTRL_PORT, FINE_HZ, SPEC_PORT, Spectrum, SpectrumStream


def describe(s: Spectrum) -> str:
    f, p = s.ordered()
    k = int(np.argmax(p))
    return (f"seq {s.seq:6d}  ADC {s.adc_input}  subband {s.subband:2d} ({s.centre_hz / 1e6:8.2f} MHz)  "
            f"tint {s.tint_s:8.3f} s  mean {p.mean():11.4e}  peak {p[k]:11.4e} @ {f[k] / 1e6:10.4f} MHz"
            f"  lost {s.lost}  dropped {s.dropped}"
            + ("  [first after restart]" if s.first else "")
            + ("  [SIM]" if s.simulated else ""))


def save_spectrum(s: Spectrum, outdir: str) -> str:
    """Write one integration to <outdir>/spec_<host_time_ns>_<seq>.npz.

    power      uint64 (4096,) accumulated power, FFT order
    freqs_hz   float64 (4096,) absolute frequency of each element of power
    n_spectra  spectra accumulated (mean power per spectrum = power / n_spectra)
    """
    fn = os.path.join(outdir, f"spec_{s.host_time_ns}_{s.seq:08d}.npz")
    np.savez(fn, power=s.power, freqs_hz=s.freqs_hz(), seq=s.seq, n_spectra=s.n_spectra,
             subband=s.subband, adc_input=s.adc_input, centre_hz=s.centre_hz, fine_hz=FINE_HZ,
             tint_s=s.tint_s,
             first=s.first, simulated=s.simulated, end_sample=s.end_sample,
             host_time_ns=s.host_time_ns, sample_rate_hz=s.sample_rate_hz, lost=s.lost,
             restarts=s.restarts)
    return fn


def live_plot(stream: SpectrumStream, count: int) -> int:
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("plot needs matplotlib: uv sync --extra plot", file=sys.stderr)
        return 1
    plt.ion()
    fig, ax = plt.subplots(figsize=(11, 5))
    line = None
    n = 0
    for s in stream:
        f, p = s.ordered()
        db = 10 * np.log10(np.maximum(p, 1e-3))
        if line is None or len(line.get_xdata()) != len(f) or line.get_xdata()[0] != f[0] / 1e6:
            ax.clear()
            (line,) = ax.plot(f / 1e6, db, lw=0.7)
            ax.set_xlabel("frequency (MHz)")
            ax.set_ylabel("power per spectrum (dB, arbitrary)")
            ax.grid(alpha=0.3)
        else:
            line.set_ydata(db)
            ax.relim()
            ax.autoscale_view()
        ax.set_title(f"ADC {s.adc_input}, subband {s.subband} ({s.centre_hz / 1e6:.2f} MHz), "
                     f"seq {s.seq}, {s.tint_s:.3f} s" + ("  (first after restart)" if s.first else ""))
        fig.canvas.draw_idle()
        plt.pause(0.01)
        n += 1
        if count and n >= count:
            break
        if not plt.fignum_exists(fig.number):
            break
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="luna-spec", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default=os.environ.get("LUNA_HOST", "192.168.2.10"))
    ap.add_argument("--spec-port", type=int, default=SPEC_PORT)
    ap.add_argument("--ctrl-port", type=int, default=CTRL_PORT)
    sub = ap.add_subparsers(dest="action", required=True)

    sub.add_parser("status", help="print the spectrometer settings and counters")
    s = sub.add_parser("set", help="configure the spectrometer")
    s.add_argument("--input", type=int, help="ADC channel 0-7 feeding the spectrometer")
    s.add_argument("--subband", type=int, help="coarse channel 0-16 (centre = k * 122.88 MHz)")
    g = s.add_mutually_exclusive_group()
    g.add_argument("--tint", type=float, help="integration time in seconds (default 6)")
    g.add_argument("--nspec", type=int, help="integration length in spectra of 33.33 us")
    g2 = s.add_mutually_exclusive_group()
    g2.add_argument("--on", action="store_true", help="enable the spectrometer")
    g2.add_argument("--off", action="store_true", help="disable the spectrometer")
    s.add_argument("--restart", action="store_true", help="restart the current integration")
    s.add_argument("--save", action="store_true", help="persist on the server")
    r = sub.add_parser("record", help="save each integration to an .npz file")
    r.add_argument("-o", "--outdir", default=".")
    r.add_argument("-n", "--count", type=int, default=0, help="stop after N integrations (0 = forever)")
    r.add_argument("--skip-first", action="store_true",
                   help="do not save integrations flagged 'first after restart'")
    w = sub.add_parser("watch", help="print one line per integration")
    w.add_argument("-n", "--count", type=int, default=0)
    p = sub.add_parser("plot", help="live plot of each integration (matplotlib)")
    p.add_argument("-n", "--count", type=int, default=0)
    args = ap.parse_args(argv)

    if args.action in ("status", "set"):
        with Control(args.host, args.ctrl_port) as ctl:
            if args.action == "set":
                if args.input is not None:
                    ctl.set_spec_input(args.input)
                if args.subband is not None:
                    ctl.set_spec_subband(args.subband)
                if args.tint is not None:
                    ctl.set_spec_tint(args.tint)
                if args.nspec is not None:
                    ctl.set_spec_nspec(args.nspec)
                if args.on or args.off:
                    ctl.spec_enable(args.on)
                if args.restart:
                    ctl.spec_restart()
                if args.save:
                    ctl.save()
            for k, v in ctl.spec_status().items():
                print(f"{k:14s} {v}")
        return 0

    with SpectrumStream(args.host, args.spec_port) as stream:
        if args.action == "plot":
            return live_plot(stream, args.count)
        if args.action == "record":
            os.makedirs(args.outdir, exist_ok=True)
        n = 0
        t0 = time.time()
        try:
            for spec in stream:
                print(describe(spec))
                if args.action == "record":
                    if args.skip_first and spec.first:
                        continue
                    save_spectrum(spec, args.outdir)
                n += 1
                if args.count and n >= args.count:
                    break
        except KeyboardInterrupt:
            pass
        print(f"{n} integrations in {time.time() - t0:.1f} s", file=sys.stderr)
    return 0


def run() -> int:
    try:
        return main()
    except ControlError as e:
        print(e, file=sys.stderr)
        return 1
    except (ConnectionError, OSError) as e:
        print(f"connection problem: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(run())
