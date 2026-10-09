#!/usr/bin/env python3
"""Golden model + stimulus generator for tb_trig (chan_detect + trig_logic).

Definitions (identical to the VHDL documentation in trig_logic.vhd):
  COINC : trigger at sample q if an enabled channel hits at q and >= N enabled
          channels have a hit in [q-W+1, q].  Mask = those channels.
  ANTI  : trigger at sample p if enabled channel r hits at p and no other
          enabled channel has a hit in [p-W+1, p+W-1].  Mask = 1<<r.
  VETO  : (ANTI only, veto = channel V >= 0) V never starts a trigger, but a
          V hit in [p-W+1, p+W-1] blocks, whether or not V is in the mask.
  Hardware emits at most one trigger per clock cycle (16 samples): the
  earliest qualifying lane of the evaluation cycle (q for COINC, p+W-1 for ANTI).

usage:
  trig_model.py gen  <seed> <mode> <N> <W> <mask> <veto> <stim> <expect>
                     (veto = channel 0..7, or -1 for none)
  trig_model.py cmp  <expect> <out>
"""
import random
import sys

NCH, LANES = 8, 16


def gen(seed, mode, n_req, win, mask, ncycles=3000):
    rng = random.Random(seed)
    hits = [set() for _ in range(NCH)]
    t = 400
    end = (ncycles - 40) * LANES
    while t < end - 400:
        kind = rng.random()
        if kind < 0.15:
            # isolated single hit
            hits[rng.randrange(NCH)].add(t)
        elif kind < 0.35:
            # directed boundary case: two channels exactly W-1 / W apart
            a, b = rng.sample(range(NCH), 2)
            d = rng.choice([win - 1, win, max(win - 2, 0), win + 1])
            hits[a].add(t)
            hits[b].add(t + d)
        else:
            # cluster on a random subset of channels
            k = rng.randint(1, NCH)
            spread = rng.choice([4, 16, 40, 80, 150])
            for ch in rng.sample(range(NCH), k):
                base = t + rng.randint(-spread, spread)
                for _ in range(rng.choice([1, 1, 1, 2, 3])):
                    hits[ch].add(base + rng.randint(0, 20))
        t += rng.randint(120, 900)
    hits = [sorted(h) for h in hits]
    return hits


def expected(hits, mode, n_req, win, mask, veto=-1):
    en = [(mask >> j) & 1 for j in range(NCH)]
    # anti-coincidence roles: cand may start a trigger, blk blocks others
    a_cand = [en[j] and j != veto for j in range(NCH)]
    a_blk = [en[j] or j == veto for j in range(NCH)]
    hs = [set(h) for h in hits]
    maxpos = max((max(h) for h in hits if h), default=0) + 2 * win + 64
    trig = []

    def has_hit(j, lo, hi):
        return any(lo <= p <= hi for p in hits[j])

    if mode == 0:
        # evaluate every sample q that is an enabled hit
        cand = sorted({p for j in range(NCH) if en[j] for p in hits[j]})
        last_cycle = -1
        for q in cand:
            c = q // LANES
            if c == last_cycle:
                continue
            chans = [j for j in range(NCH) if en[j] and has_hit(j, q - win + 1, q)]
            if len(chans) >= n_req:
                trig.append((q, sum(1 << j for j in chans), 1))
                last_cycle = c
    else:
        pr = sorted({(p, r) for r in range(NCH) if a_cand[r] for p in hits[r]})
        last_cycle = -1
        for p, r in pr:
            c = (p + win - 1) // LANES
            if c == last_cycle:
                continue
            ok = all(not has_hit(j, p - win + 1, p + win - 1)
                     for j in range(NCH) if a_blk[j] and j != r)
            if ok:
                trig.append((p, 1 << r, 2))
                last_cycle = c
    return trig


def write_stim(fname, hits, mode, n_req, win, mask, veto, ncycles=3000):
    lanes = [[0] * ncycles for _ in range(NCH)]
    for j in range(NCH):
        for p in hits[j]:
            lanes[j][p // LANES] |= 1 << (p % LANES)
    with open(fname, "w") as f:
        f.write(f"{mode} {n_req} {win} {mask} {int(veto >= 0)} {max(veto, 0)}\n")
        for c in range(ncycles):
            f.write(" ".join(str(lanes[j][c]) for j in range(NCH)) + "\n")


def main():
    if sys.argv[1] == "gen":
        seed, mode, n_req, win, mask, veto = map(int, sys.argv[2:8])
        hits = gen(seed, mode, n_req, win, mask)
        write_stim(sys.argv[8], hits, mode, n_req, win, mask, veto)
        with open(sys.argv[9], "w") as f:
            for t in expected(hits, mode, n_req, win, mask, veto):
                f.write("%d %d %d\n" % t)
    elif sys.argv[1] == "cmp":
        exp = [tuple(map(int, l.split())) for l in open(sys.argv[2]) if l.strip()]
        got = [tuple(map(int, l.split())) for l in open(sys.argv[3]) if l.strip()]
        if exp == got:
            print(f"PASS  {len(got)} triggers match")
            return 0
        print(f"FAIL  expected {len(exp)} got {len(got)}")
        se, sg = set(exp), set(got)
        for t in sorted(se - sg)[:10]:
            print("  missing ", t)
        for t in sorted(sg - se)[:10]:
            print("  extra   ", t)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
