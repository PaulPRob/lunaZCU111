#!/usr/bin/env python3
"""Bit-exact model of hw/hdl/ospfb.vhd (32/27 oversampled coarse filter bank)
and stimulus/compare for tb_ospfb.

usage:
  ospfb_model.py gen  <seed> <stim> [k]      random tones + noise, with gaps
                                             (k: plus a strong tone in subband k)
  ospfb_model.py cmp  <k> <stim> <out>       compare tb_ospfb output (bit exact)
  ospfb_model.py selftest                    response checks of the model itself

Stimulus: one line per clk cycle, "valid c0 c1 ... c26" (12-bit codes, c0
oldest).  tb_ospfb writes "cycle re im" for each cycle with dout_valid.

Model (see ospfb.vhd): for the word whose newest sample is x[n]
  v[p] = sat18(round(sum_t c[p+32t] x[n-p-32t] / 2^11))
  Re   = sum_{p<16} (v[p] + v[32-p]) TWC[kp], v[32] := (-1)^k v[16]
  Im   = sum_{0<p<16} (v[p] - v[32-p]) TWS[kp]
  zs   = round(Z' / 2^13)
  out  = sat18(round(zs * (ROTC[q] - j ROTS[q]) / 2^24)),  q = k r mod 32,
         r = r0 + 27 m  (m = output index, r0 unknown constant: searched)
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
P = json.load(open(os.path.join(HERE, "ospfb_coefs.json")))
M, D, T = P["M"], P["D"], P["T"]
C = np.array(P["coef"], dtype=np.int64)
TWC, TWS = np.array(P["tw_cos"]), np.array(P["tw_sin"])
ROTC, ROTS = np.array(P["rot_cos"]), np.array(P["rot_sin"])
L = M * T
FILL = -(-((M - 1) + (M + D) * (T - 1) + 1) // D)      # 34 words


def rnd(x, sh):
    return (x + (1 << (sh - 1))) >> sh


def sat(x, w):
    return np.clip(x, -(1 << (w - 1)), (1 << (w - 1)) - 1)


def branch_sums(x, n):
    """v[m, p] for the anchors n[m] (newest sample index of each word)."""
    idx = n[:, None, None] - np.arange(M)[None, :, None] - M * np.arange(T)[None, None, :]
    cc = C.reshape(T, M).T                      # cc[p, t] = c[p + 32 t]
    s = (x[idx] * cc[None]).sum(axis=2)
    return sat(rnd(s, 11), 18)


def dft_bin(v, k):
    p = np.arange(M // 2)
    kp = (k * p) % M
    sgn = -1 if k % 2 else 1
    a = v[:, :M // 2].copy()
    a[:, 0] += sgn * v[:, M // 2]
    a[:, 1:] += v[:, M - p[1:]]
    d = np.zeros_like(a)
    d[:, 1:] = v[:, 1:M // 2] - v[:, M - p[1:]]
    zr = (a * TWC[kp]).sum(axis=1)
    zi = (d * TWS[kp]).sum(axis=1)
    return sat(rnd(zr, 13), 27), sat(rnd(zi, 13), 27)


def rotate(zr, zi, k, r):
    q = (k * r) % M
    sr = zr * ROTC[q] + zi * ROTS[q]
    si = zi * ROTC[q] - zr * ROTS[q]
    return sat(rnd(sr, 24), 18), sat(rnd(si, 24), 18)


def ospfb(x, k, r0=0, first_word=None):
    """Outputs for every word m whose window lies inside x (x[0] = oldest).
    Returns (m, re, im); word m holds x[27m .. 27m+26]."""
    nw = len(x) // D
    m0 = FILL - 1 if first_word is None else first_word
    m = np.arange(m0, nw)
    n = D * m + D - 1
    v = branch_sums(x.astype(np.int64), n)
    zr, zi = dft_bin(v, k)
    re, im = rotate(zr, zi, k, (r0 + D * m) % M)
    return m, re, im


# --------------------------------------------------------------- tb support
def gen(seed, path, k=None, nwords=1400):
    """Noise and random tones; with k, a near full-scale tone in subband k
    (exercises the large-signal and saturation paths)."""
    rng = np.random.default_rng(seed)
    n = np.arange(nwords * D)
    fs = P["fs"]
    x = rng.normal(0, 40, len(n))
    if k is not None:
        f = k * fs / M + rng.uniform(-50e6, 50e6) * (k not in (0, 16))
        x += 1400 * np.cos(2 * np.pi * f / fs * n)
    for _ in range(6):
        f = rng.uniform(0, fs / 2)
        x += rng.uniform(50, 400) * np.cos(2 * np.pi * f / fs * n + rng.uniform(0, 6.3))
    x[5000:5040] = 2047          # a short full-scale burst (saturation paths)
    codes = np.clip(np.round(x), -2048, 2047).astype(int)
    valid = np.ones(nwords, dtype=int)
    valid[700:703] = 0           # a gap: the output must go invalid, then recover
    with open(path, "w") as f:
        for m in range(nwords):
            f.write(f"{valid[m]} " + " ".join(map(str, codes[D * m:D * m + D])) + "\n")


def load_stim(path):
    rows = [list(map(int, l.split())) for l in open(path) if l.strip()]
    valid = np.array([r[0] for r in rows])
    x = np.array([c for r in rows for c in r[1:]], dtype=np.int64)
    return valid, x


def cmp(k, stim, out):
    valid, x = load_stim(stim)
    rows = [list(map(int, l.split())) for l in open(out) if l.strip()]
    if not rows:
        print(f"ospfb k={k:2d}: FAIL no valid outputs")
        return 1
    cyc = np.array([r[0] for r in rows])
    hre = np.array([r[1] for r in rows])
    him = np.array([r[2] for r in rows])
    best = None                                 # (mismatches, latency, r0)
    for lat in range(0, 64):
        m = cyc - lat
        if m.min() < FILL - 1 or m.max() >= len(valid):
            continue
        zr, zi = dft_bin(branch_sums(x, D * m + D - 1), k)
        for r0 in range(M):
            re, im = rotate(zr, zi, k, (r0 + D * m) % M)
            bad = int(np.count_nonzero((re != hre) | (im != him)))
            if best is None or bad < best[0]:
                best = (bad, lat, r0)
            if bad == 0:
                break
        if best[0] == 0:
            break
    if best is None:
        print(f"ospfb k={k:2d}: FAIL outputs outside the stimulus")
        return 1
    bad, lat, r0 = best
    # expected validity: every output whose window holds FILL valid words
    exp_valid = np.array([valid[max(0, m - FILL + 1):m + 1].all() and m >= FILL - 1
                          for m in range(len(valid))])
    got_valid = np.zeros(len(valid), dtype=bool)
    got_valid[cyc - lat] = True
    vmis = int(np.count_nonzero(exp_valid[:len(valid) - lat] != got_valid[:len(valid) - lat]))
    peak = int(max(np.abs(hre).max(), np.abs(him).max()))
    ok = bad == 0 and vmis == 0
    print(f"ospfb k={k:2d}: {len(rows)} outputs, latency {lat}, r0 {r0}, mismatches {bad}, "
          f"valid-flag mismatches {vmis}, peak |out| {peak}  {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


# ----------------------------------------------------------------- selftest
def tone(f_hz, amp, nwords=600, phase=0.3):
    n = np.arange(nwords * D)
    return np.round(amp * np.cos(2 * np.pi * f_hz / P["fs"] * n + phase)).astype(np.int64)


def selftest():
    fs = P["fs"]
    fo = fs / D
    ok = True
    for s in P["summary"]:
        print("filter:", s)
    for k in (1, 7, 12, 15):
        # orientation and gain: tone at centre + 10 MHz must rotate at +10 MHz
        df = 10e6
        _, re, im = ospfb(tone(k * fs / M + df, 600), k)
        z = (re + 1j * im)[50:]
        ph = np.angle(z[1:] * np.conj(z[:-1]))
        f_meas = np.median(ph) / (2 * np.pi) * fo
        amp = np.median(np.abs(z))
        good = abs(f_meas - df) < 1e3 and abs(amp / (32 * 600) - 1) < 0.02
        print(f"k={k:2d}: tone +10 MHz -> {f_meas / 1e6:+.4f} MHz, |out| {amp:.0f} "
              f"(expect {32 * 600})  {'ok' if good else 'FAIL'}")
        ok &= good
        # alias: a tone 90 MHz above the centre lands at 90 - 145.64 = -55.6 MHz
        _, re2, im2 = ospfb(tone(k * fs / M + 90e6, 2000), k)
        a2 = np.sqrt(np.mean((re2[50:] ** 2 + im2[50:] ** 2)))
        rej = 20 * np.log10(max(a2, 1e-3) / (32 * 2000))
        good = rej < -65
        print(f"k={k:2d}: tone +90 MHz (alias at -55.6 MHz): {rej:.1f} dB  {'ok' if good else 'FAIL'}")
        ok &= good
    for k in (0, 16):
        _, re, im = ospfb(tone(k * fs / M + (5e6 if k == 0 else -5e6), 600), k)
        good = not im.any()
        print(f"k={k:2d}: imaginary part all zero: {good}")
        ok &= good
    print("MODEL SELFTEST PASSED" if ok else "MODEL SELFTEST FAILED")
    return 0 if ok else 1


def main(argv):
    if len(argv) >= 3 and argv[0] == "gen":
        gen(int(argv[1]), argv[2], int(argv[3]) if len(argv) > 3 else None)
        return 0
    if len(argv) >= 4 and argv[0] == "cmp":
        return cmp(int(argv[1]), argv[2], argv[3])
    if argv and argv[0] == "selftest":
        return selftest()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
