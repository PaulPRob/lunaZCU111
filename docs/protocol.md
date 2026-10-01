# lunaserver network protocol

The server runs on the ZCU111 PS at **192.168.2.10**. It has two TCP ports:

| Port | Direction | Content |
|------|-----------|---------|
| 5000 | server → client | one binary frame per captured event (any number of clients) |
| 5001 | both | ASCII control commands, one reply line per command |

## Data port (5000)

Each event is sent as one frame. All values are little endian. The C definitions are in `sw/server/protocol.h`, and the Python parser is in `sw/client/lunaclient/protocol.py`.

```
struct luna_frame_hdr  (64 bytes, added by the server)
  0  char[4]  magic        "LEVT"
  4  u16      version      1
  6  u16      hdr_bytes    64
  8  u32      frame_bytes  total size of this frame
 12  u32      flags        bit0 = simulated data
 16  u64      host_time_ns CLOCK_REALTIME when the event was read out
 24  f64      sample_rate  3.93216e9
 32  u16[8]   thresholds   in effect
 48  u32      dropped      frames dropped for this client before this frame
 52  u32[3]   reserved
struct luna_event_hdr  (64 bytes, written by the FPGA; see register_map.md)
int16 samples[8][L]        channel major; 12-bit ADC code in bits 15..4
```

The trigger sample is `samples[ch][trig_offset]`, where `trig_offset = L/2 + (trig_sample mod 16)`, which is always within 16 samples of the centre. `trig_sample` is a 64-bit count of samples, common to all channels. The counter starts from 0 when the server initialises the core, and it is aligned across tiles by MTS.

**Slow clients:** each client has a queue of 64 frames on top of the TCP socket buffers. When the queue is full, new frames for that client are dropped; the capture is never throttled. A gap in the event `seq` numbers is the reliable way to detect drops. The `dropped` field only counts drops that happened before the frame that carries it.

## Control port (5001)

Commands are case-insensitive, one per line. Each reply is one line beginning with `OK` or `ERR`, usually made of `key=value` fields. You can also use `nc 192.168.2.10 5001` by hand.

| Command | Effect |
|---------|--------|
| `HELP` | list the commands |
| `STATUS` | armed, mode, banks full, trigger/lost counts, clients, frames sent/dropped, sample counter, SYSREF count, RFDC PLL lock and MTS latency |
| `GET CONFIG` | thresholds, mode, N, window, mask, length, armed |
| `GET RATES` | per channel: clock cycles with a hit per second since the previous `GET RATES` |
| `GET PEAKS` | per channel: largest \|x\| since the previous `GET PEAKS` (noise level; useful for choosing thresholds) |
| `SET THRESH <ch\|ALL> <0-32767>` | threshold in 16-bit units (12-bit code × 16) |
| `SET MODE COINC\|ANTI` | coincidence or anti-coincidence |
| `SET N <1-8>` | channels required within the window (coincidence) |
| `SET WINDOW <1-255>` | window in samples (default 64 = 16.3 ns) |
| `SET MASK <0x00-0xFF>` | channels taking part in triggering |
| `SET LEN <4096-16384>` | capture length per channel (multiple of 32); changing it discards any captured events that have not been read out |
| `ARM` / `DISARM` | enable/disable triggering (events already captured are still sent) |
| `SOFTTRIG` | force one capture now |
| `RESYNC` | run multi-tile synchronisation again |
| `SAVE` | save the configuration (SD card: `/mnt/sd/lunaserver.conf`) |

### Trigger definitions

- **Coincidence:** the trigger fires at sample q when an enabled channel has a hit at q and at least N enabled channels have a hit in [q−W+1, q]. It fires on the hit that completes the coincidence, and the mask lists all participating channels. N = 1 gives a simple OR of the channels.
- **Anti-coincidence:** the trigger fires at sample p when enabled channel r has a hit at p and no other enabled channel has a hit in [p−W+1, p+W−1]. The mask is 1<<r. The decision is taken W−1 samples later, but the buffer is still centred on p.
- A hit means |x| > threshold on that channel. The evaluation is sample-exact at 3.93216 GS/s.
- Triggers that arrive while the post-trigger half of an event is still being recorded belong to that same event and are ignored. After each event the next capture bank needs L/2 samples of pre-trigger data (2.1 µs at L = 16384) before it can trigger.
