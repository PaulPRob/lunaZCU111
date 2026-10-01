#!/usr/bin/env python3
"""Check spec_writes.txt from tb_spec (spectrometer_top + CSIRO PFB/DFB).

usage: check_spec.py spec_writes.txt

Expected (see tb_spec.vhd): two tones in subband 12, tone A (600 codes) in
fine channel 25 and tone B (150 codes) in fine channel 4096-100 = 3996, so
power(A)/power(B) ~ 16.  Integrations: step 1 ACC_LEN=1 (first after
restart), step 2 ACC_LEN=0 (first after restart), step 3 ACC_LEN=0.
"""
import sys

import numpy as np

NCHAN = 4096
BIN_A, BIN_B = 25, NCHAN - 100


def load(path):
    specs, cur = [], {}
    for line in open(path):
        p = line.split()
        if p[0] == "W":
            cur[int(p[2])] = int(p[3], 16)
        elif p[0] == "C":
            specs.append(dict(seq=int(p[1]), first=p[2].strip("'") == "1",
                              subband=int(p[3]), acc_len=int(p[4]), data=cur))
            cur = {}
    return specs


def main():
    specs = load(sys.argv[1])
    ok = True
    print(f"{len(specs)} integrations stored")
    want = [(1, True), (0, True), (0, False)]
    if len(specs) < len(want):
        print("FAIL: expected at least 3 integrations")
        ok = False
    for i, s in enumerate(specs):
        d = s["data"]
        if sorted(d) != list(range(NCHAN)):
            print(f"FAIL seq {s['seq']}: {len(d)} channels written, not 0..4095 once each")
            ok = False
            continue
        p = np.array([d[k] for k in range(NCHAN)], dtype=float)
        order = np.argsort(p)[::-1]
        floor = np.median(p)
        ratio = p[BIN_A] / max(p[BIN_B], 1)
        print(f"seq {s['seq']}: acc_len {s['acc_len']} first {int(s['first'])} subband {s['subband']} "
              f"top bins {order[:4].tolist()}  P[25]={p[BIN_A]:.3e} P[3996]={p[BIN_B]:.3e} "
              f"A/B={ratio:.2f} median={floor:.3e}")
        if set(order[:2].tolist()) != {BIN_A, BIN_B} or order[0] != BIN_A:
            print("  FAIL: tones not in the expected fine channels")
            ok = False
        if not 8 < ratio < 32:
            print("  FAIL: tone power ratio far from 16")
            ok = False
        if i < len(want) and (s["acc_len"], s["first"]) != want[i]:
            print(f"  FAIL: expected acc_len/first = {want[i]}")
            ok = False
    if len(specs) >= 2 and specs[0]["data"] and specs[1]["data"]:
        p0 = specs[0]["data"][BIN_A] / 2      # 2 spectra
        p1 = specs[1]["data"][BIN_A] / 1
        print(f"tone A power per spectrum: {p0:.4e} (2-spectrum) vs {p1:.4e} (1-spectrum)")
    print("SPEC CHECK PASSED" if ok else "SPEC CHECK FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
