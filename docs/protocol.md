# lunaserver network protocol

The server runs on the ZCU111 PS at **192.168.2.10**. It has three TCP ports:

| Port | Direction | Content |
|------|-----------|---------|
| 5000 | server → client | one binary frame per captured event (any number of clients) |
| 5001 | both | ASCII control commands, one reply line per command |
| 5002 | server → client | one binary frame per spectrometer integration (any number of clients) |

The three ports are independent. A client can stream events and spectra and send control commands at the same time.

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

## Spectrum port (5002)

The spectrometer works on one ADC channel, chosen with `SET SPEC_INPUT` (default 0):
- **Coarse channels:** the signal is split into 17 coarse channels ("subbands") of 122.88 MHz. Subband k is centred on k × 122.88 MHz.
- **Fine channels:** the selected subband goes through a 4096-channel filter bank, with 30 kHz channels.
- **Integration:** the power in each channel is accumulated over the integration time, 6.000 s by default.

Each integration is sent as one frame:

```
struct luna_spec_hdr  (64 bytes)
  0  char[4]  magic        "LSPC"
  4  u16      version      2 (1 = servers before SPEC_INPUT: byte 59 is then 0)
  6  u16      hdr_bytes    64
  8  u32      frame_bytes  64 + 8 * 4096
 12  u32      flags        bit0 = simulated data, bit1 = first integration after a restart
 16  u64      host_time_ns CLOCK_REALTIME when the spectrum was read out
 24  u64      end_sample   ADC sample counter when the integration ended (same time base
                           as trig_sample of the events)
 32  f64      sample_rate  3.93216e9
 40  u32      seq          integration sequence number (FPGA)
 44  u32      n_spectra    spectra accumulated (integration time = n_spectra * 33.33 us)
 48  u32      dropped      frames dropped for this client before this frame
 52  u32      lost         integrations lost in the FPGA (both banks full) so far
 56  u16      n_channels   4096
 58  u8       subband      0..16
 59  u8       adc_input    ADC channel 0..7 the spectrum was taken on
 60  u32      restarts     integration restarts so far
u64 power[4096]            accumulated power per fine channel, FFT order
```

- **Channel frequencies:** channel k is at `subband × 122.88 MHz + k × 30 kHz` for k < 2048, and at `subband × 122.88 MHz + (k − 4096) × 30 kHz` for k ≥ 2048. In numpy this is `np.fft.fftfreq(4096) * 122.88e6`, and `np.fft.fftshift` puts the channels in frequency order.
- **Mean power:** `power / n_spectra` is the mean power per spectrum, in arbitrary units.
- **Restarts:** enabling the spectrometer, `SPEC RESTART`, or changing the input, subband or integration time restarts the integration immediately. The FPGA discards everything until the filter bank has settled (about 6 spectra, 0.2 ms), so the first integration you receive after a change contains only data taken after it. That integration has flag bit 1 set, for information.
- **Lost integrations:** the FPGA holds two finished integrations. The server reads each one in about 3 ms. Integrations shorter than about 50 ms can therefore be lost, and they are counted in `lost`.

## Control port (5001)

Commands are case-insensitive, one per line. Each reply is one line beginning with `OK` or `ERR`, usually made of `key=value` fields. You can also use `nc 192.168.2.10 5001` by hand.

| Command | Effect |
|---------|--------|
| `HELP` | list the commands |
| `STATUS` | armed, mode, banks full, trigger/lost counts, clients, frames sent/dropped, sample counter, SYSREF count, RFDC PLL lock and MTS latency |
| `GET CONFIG` | thresholds, mode, N, window, mask, length, armed, spec_enable, spec_input, spec_subband, spec_nspec |
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
| `GET SPEC` | spectrometer: present, enabled, input, subband, nspec, tint (s), centre_mhz, bandwidth_mhz, fine_khz, integrations, lost, restarts, banks_full, clients, sent, dropped |
| `SPEC ON` / `SPEC OFF` | enable or disable the spectrometer (ON starts a fresh integration) |
| `SPEC RESTART` | discard the current integration and start a new one |
| `SET SPEC_INPUT <0-7>` | ADC channel feeding the spectrometer (default 0); restarts the integration. Needs spectrometer v1.1; older bitstreams accept only 0 |
| `SET SPEC_SUBBAND <0-16>` | coarse channel for the fine spectrum, centre = k × 122.88 MHz (default 12 = 1474.56 MHz); restarts the integration |
| `SET SPEC_TINT <seconds>` | integration time, rounded to whole spectra of 33.33 µs (default 6.0); restarts the integration |
| `SET SPEC_NSPEC <n>` | integration time as a number of spectra (180000 = 6.000 s); restarts the integration |
| `SAVE` | save the configuration, including the spectrometer settings (SD card: `/mnt/sd/lunaserver.conf`) |

### Trigger definitions

- **Coincidence:** the trigger fires at sample q when an enabled channel has a hit at q and at least N enabled channels have a hit in [q−W+1, q]. It fires on the hit that completes the coincidence, and the mask lists all participating channels. N = 1 gives a simple OR of the channels.
- **Anti-coincidence:** the trigger fires at sample p when enabled channel r has a hit at p and no other enabled channel has a hit in [p−W+1, p+W−1]. The mask is 1<<r. The decision is taken W−1 samples later, but the buffer is still centred on p.
- A hit means |x| > threshold on that channel. The evaluation is sample-exact at 3.93216 GS/s.
- Triggers that arrive while the post-trigger half of an event is still being recorded belong to that same event and are ignored. After each event the next capture bank needs L/2 samples of pre-trigger data (2.1 µs at L = 16384) before it can trigger.
