#!/usr/bin/env python3
"""Verify tb_capture output: cap_stream.txt (AXIS beats) against cap_log.txt."""
import struct
import sys

HDR = struct.Struct("<4sHHIIQQIBBBBHBBIIB11x")
PULSE = 0x6000


def load_events(fname):
    events, cur = [], bytearray()
    for line in open(fname):
        h, last = line.split()
        cur += int(h, 16).to_bytes(16, "little")
        if last == "1":
            events.append(bytes(cur))
            cur = bytearray()
    if cur:
        raise SystemExit("FAIL stream ends without tlast")
    return events


def main():
    events = load_events(sys.argv[1])
    log = [l.split() for l in open(sys.argv[2]) if l.strip()]
    exp = [l for l in log if l[0] == "EVT"]
    trigcount = [int(l[1]) for l in log if l[0] == "TRIGCOUNT"]
    errors = []

    if len(events) != len(exp):
        errors.append(f"expected {len(exp)} events, got {len(events)}")

    prev_seq, prev_bank = None, None
    for i, (ev, e) in enumerate(zip(events, exp)):
        L_exp, src_exp, mask_exp, lost_exp = map(int, e[1:5])
        veto_exp = int(e[5]) if len(e) > 5 else 0
        (magic, ver, hbytes, seq, nsamp, trig, start, off, mask, src, nch,
         bank, win, ncoinc, mode, lost, tcnt, veto) = HDR.unpack_from(ev, 0)
        tag = f"event {i} (seq {seq})"
        if magic != b"LUNA" or ver != 2 or hbytes != 64 or nch != 8:
            errors.append(f"{tag}: bad header magic/version/size")
            continue
        if nsamp != L_exp:
            errors.append(f"{tag}: n_samples {nsamp} != {L_exp}")
        if len(ev) != 64 + 8 * nsamp * 2:
            errors.append(f"{tag}: length {len(ev)} != {64 + 16 * nsamp}")
            continue
        if src != src_exp or mask != mask_exp or lost != lost_exp:
            errors.append(f"{tag}: src/mask/lost {src}/{mask}/{lost} "
                          f"!= {src_exp}/{mask_exp}/{lost_exp}")
        if veto != veto_exp:
            errors.append(f"{tag}: veto byte {veto:#x} != {veto_exp:#x}")
        if start % 16 or trig - start != off or off != nsamp // 2 + trig % 16:
            errors.append(f"{tag}: trigger not centred (start {start} trig {trig} off {off})")
        if prev_seq is not None and seq != prev_seq + 1:
            errors.append(f"{tag}: sequence jump {prev_seq} -> {seq}")
        if prev_bank is not None and bank != (prev_bank + 1) % 4:
            errors.append(f"{tag}: bank order {prev_bank} -> {bank}")
        prev_seq, prev_bank = seq, bank

        data = struct.unpack_from(f"<{8 * nsamp}h", ev, 64)
        ch = [data[c * nsamp:(c + 1) * nsamp] for c in range(8)]
        # continuity / alignment: ch c sample i = ((base + i + 1000c) % 4096) - 2048
        base = None
        for k in range(nsamp):
            if ch[0][k] != PULSE:
                base = (ch[0][k] + 2048 - k) % 4096
                break
        pulses = {c: [] for c in range(8)}
        bad = 0
        for c in range(8):
            for k in range(nsamp):
                v = ch[c][k]
                if v == PULSE:
                    pulses[c].append(k)
                elif v != ((base + k + 1000 * c) % 4096) - 2048:
                    bad += 1
        if bad:
            errors.append(f"{tag}: {bad} samples break continuity/alignment")
        if src in (1, 2):
            for c in range(8):
                if (mask >> c) & 1:
                    if not any(off - 63 <= p <= off for p in pulses[c]):
                        errors.append(f"{tag}: ch{c} in mask but no pulse in window")
                elif pulses[c]:
                    errors.append(f"{tag}: unexpected pulse on ch{c}")
            if not any(off in pulses[c] for c in range(8) if (mask >> c) & 1):
                errors.append(f"{tag}: no pulse exactly at trigger offset {off}")
        print(f"  {tag}: L={nsamp} src={src} mask=0x{mask:02x} bank={bank} "
              f"off={off} pulses={ {c: p for c, p in pulses.items() if p} }")

    if trigcount and trigcount[0] != len(exp):
        errors.append(f"TRIG_COUNT {trigcount[0]} != {len(exp)}")

    if errors:
        print("FAIL capture")
        for e in errors:
            print("  ", e)
        return 1
    print(f"PASS capture  {len(events)} events verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
