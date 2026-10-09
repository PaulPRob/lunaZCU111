"""luna-client : command line stub for lunaserver.

examples
  luna-client status
  luna-client cmd "SET THRESH ALL 12000"
  luna-client set --thresh 12000 --mode coinc --n 2 --window 64 --mask 0xff --len 16384
  luna-client set --mode anti --mask 0x7f --veto 7  # ch7 vetoes, never triggers
  luna-client record -o data/ -n 100          # save events as .npz
  luna-client watch                           # print a line per event
"""
from __future__ import annotations

import argparse
import os
import sys
import time

import numpy as np

from .control import Control, ControlError
from .protocol import CTRL_PORT, DATA_PORT, Event, EventStream


def on_event(evt: Event) -> None:
    """STUB: put your own per-event analysis here."""
    pk = np.abs(evt.adc_codes()).max(axis=1)
    veto = f"  veto ch{evt.veto_channel}" if evt.veto_channel is not None else ""
    print(f"seq {evt.seq:7d}  src {evt.trig_src:5s}  mask 0x{evt.trig_mask:02x} "
          f"chans {evt.trig_channels}{veto}  t {evt.trig_time_s:14.9f} s  "
          f"L {evt.n_samples}  peak |code| {pk.tolist()}  lost {evt.lost}  dropped {evt.dropped}"
          + ("  [SIM]" if evt.simulated else ""))


def save_event(evt: Event, outdir: str) -> str:
    fn = os.path.join(outdir, f"luna_{evt.host_time_ns}_{evt.seq:08d}.npz")
    np.savez(fn, samples=evt.samples, seq=evt.seq, trig_sample=evt.trig_sample,
             start_sample=evt.start_sample, trig_offset=evt.trig_offset,
             trig_mask=evt.trig_mask, trig_src=evt.trig_src, window=evt.window,
             coinc_n=evt.coinc_n, mode=evt.mode, veto=evt.veto, lost=evt.lost,
             host_time_ns=evt.host_time_ns, sample_rate_hz=evt.sample_rate_hz,
             thresholds=np.array(evt.thresholds))
    return fn


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="luna-client", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default=os.environ.get("LUNA_HOST", "192.168.2.10"))
    ap.add_argument("--data-port", type=int, default=DATA_PORT)
    ap.add_argument("--ctrl-port", type=int, default=CTRL_PORT)
    sub = ap.add_subparsers(dest="action", required=True)

    sub.add_parser("status", help="print server status")
    c = sub.add_parser("cmd", help="send a raw control command")
    c.add_argument("command", nargs="+")
    s = sub.add_parser("set", help="configure the trigger")
    s.add_argument("--thresh", help="value for all channels, or 8 comma separated values")
    s.add_argument("--mode", choices=["coinc", "anti"])
    s.add_argument("--n", type=int, help="coincidence: channels required (1-8)")
    s.add_argument("--window", type=int, help="coincidence window in samples (1-255)")
    s.add_argument("--mask", type=lambda x: int(x, 0), help="channel mask, e.g. 0xff")
    s.add_argument("--veto", help="anti-coincidence veto channel 0-7, or 'off'")
    s.add_argument("--len", type=int, help="capture length (4096-16384)")
    s.add_argument("--save", action="store_true", help="persist on the server")
    r = sub.add_parser("record", help="save events to .npz files")
    r.add_argument("-o", "--outdir", default=".")
    r.add_argument("-n", "--count", type=int, default=0, help="stop after N events (0 = forever)")
    w = sub.add_parser("watch", help="print one line per event")
    w.add_argument("-n", "--count", type=int, default=0)
    args = ap.parse_args(argv)

    if args.action in ("status", "cmd", "set"):
        with Control(args.host, args.ctrl_port) as ctl:
            if args.action == "status":
                for k, v in ctl.status().items():
                    print(f"{k:12s} {v}")
            elif args.action == "cmd":
                print(ctl.command(" ".join(args.command)))
            else:
                if args.thresh is not None:
                    vals = [int(v, 0) for v in args.thresh.split(",")]
                    if len(vals) == 1:
                        ctl.set_threshold("ALL", vals[0])
                    else:
                        for ch, v in enumerate(vals):
                            ctl.set_threshold(ch, v)
                if args.mode:
                    ctl.set_mode(args.mode)
                if args.n is not None:
                    ctl.set_coincidence(args.n)
                if args.window is not None:
                    ctl.set_window(args.window)
                if args.mask is not None:
                    ctl.set_mask(args.mask)
                if args.veto is not None:
                    ctl.set_veto(None if args.veto.lower() == "off" else int(args.veto))
                if args.len is not None:
                    ctl.set_length(args.len)
                if args.save:
                    ctl.save()
                print(ctl.command("GET CONFIG"))
        return 0

    os.makedirs(getattr(args, "outdir", "."), exist_ok=True)
    n = 0
    t0 = time.time()
    try:
        with EventStream(args.host, args.data_port) as stream:
            for evt in stream:
                on_event(evt)
                if args.action == "record":
                    save_event(evt, args.outdir)
                n += 1
                if args.count and n >= args.count:
                    break
    except KeyboardInterrupt:
        pass
    dt = time.time() - t0
    print(f"{n} events in {dt:.1f} s", file=sys.stderr)
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
