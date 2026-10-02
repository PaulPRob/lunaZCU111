#!/usr/bin/env python3
"""Check spec_writes.txt from tb_spec (spectrometer_top + CSIRO PFB/DFB).

usage: check_spec.py [--mode data|restart] spec_writes.txt [spec_events.txt]

Every stored integration must have all 4096 channels written exactly once.

data    (tb_spec TEST_MODE 0): two integrations with ACC_LEN = 1, the first
        flagged "first after restart"; tones in subband 12: tone A (600
        codes) in fine channel 25, tone B (150 codes) in fine channel
        4096-100 = 3996, so power(A)/power(B) ~ 16.
restart (TEST_MODE 1, no PFB, data all zero): after shortening ACC_LEN from
        7 to 0, two integrations with ACC_LEN = 0, the first flagged.
"""
import argparse
import os
import sys

import numpy as np

NCHAN = 4096
BIN_A, BIN_B = 25, NCHAN - 100


def load(path):
    specs, cur = [], {}
    for line in open(path):
        p = line.split()
        if not p:
            continue
        if p[0] == "W":
            cur[int(p[2])] = int(p[3], 16)
        elif p[0] == "C":
            specs.append(dict(seq=int(p[1]), first=p[2].strip("'") == "1",
                              subband=int(p[3]), acc_len=int(p[4]), data=cur))
            cur = {}
    return specs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["data", "restart"], default="data")
    ap.add_argument("writes")
    ap.add_argument("events", nargs="?")
    a = ap.parse_args()
    events = a.events or os.path.join(os.path.dirname(a.writes), "spec_events.txt")
    if os.path.exists(events):
        print("handshake events (clk_spec cycle):")
        for line in open(events):
            print("   ", line.rstrip())
    specs = load(a.writes)
    ok = True
    print(f"{len(specs)} integrations stored")
    for s in specs:
        d = s["data"]
        tag = (f"seq {s['seq']}: acc_len {s['acc_len']} first {int(s['first'])} "
               f"subband {s['subband']}")
        if sorted(d) != list(range(NCHAN)):
            print(f"{tag}  FAIL: {len(d)} channels written, not 0..4095 once each")
            ok = False
            continue
        p = np.array([d[k] for k in range(NCHAN)], dtype=float)
        if a.mode == "restart":
            print(f"{tag}  complete")
            continue
        order = np.argsort(p)[::-1]
        ratio = p[BIN_A] / max(p[BIN_B], 1)
        print(f"{tag}  top {order[:4].tolist()}  P[25]={p[BIN_A]:.3e} P[3996]={p[BIN_B]:.3e} "
              f"A/B={ratio:.2f} P[25]/spectrum={p[BIN_A] / (s['acc_len'] + 1):.3e} "
              f"median={np.median(p):.3e}")
        if not p.any():
            print("  FAIL: empty integration stored")
            ok = False
        elif order[0] != BIN_A or order[1] != BIN_B:
            print("  FAIL: tones not in fine channels 25 and 3996")
            ok = False
        elif not 8 < ratio < 32:
            print("  FAIL: tone power ratio far from 16")
            ok = False
    want_len = 1 if a.mode == "data" else 0
    got = [(s["acc_len"], s["first"]) for s in specs]
    if got[:2] != [(want_len, True), (want_len, False)]:
        print(f"FAIL: expected integrations (acc_len, first) = "
              f"[({want_len}, True), ({want_len}, False)], got {got}")
        ok = False
    print(f"SPEC CHECK ({a.mode}) PASSED" if ok else f"SPEC CHECK ({a.mode}) FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
