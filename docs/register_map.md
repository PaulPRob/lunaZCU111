# PL address map and registers

| Base address  | Size   | Block                         | Clock          | Linux access            |
|---------------|--------|-------------------------------|----------------|-------------------------|
| `0xA000_0000` | 256 KB | RF Data Converter (AXI-Lite)  | pl_clk0 100 MHz | librfdc / libmetal (UIO) |
| `0xA010_0000` | 4 KB   | `trigger_capture` registers   | clk_1x 245.76 MHz | UIO, IRQ SPI 89        |
| `0xA011_0000` | 64 KB  | AXI DMA (S2MM only, simple mode) | pl_clk0     | UIO, IRQ SPI 90         |
| `0xA012_0000` | 64 KB  | AXI GPIO: MMCM reset/lock     | pl_clk0        | UIO                     |
| `0xA014_0000` | 128 KB | `spectrometer` registers + spectrum banks | clk_spec 122.88 MHz | UIO, IRQ SPI 92 |
| `0x7000_0000` | 16 MB  | DMA target (reserved DDR)     | –              | UIO memory map          |

> **Warning:** The trigger core and the spectrometer are clocked by the MMCM, which runs from the LMK04208 PL reference clock. That clock exists only after the RF clocks have been programmed. Reading or writing `0xA010_0000` or `0xA014_0000` before the MMCM has locked (GPIO2 bit 0 = 1) hangs the AXI bus. The spectrometer exists only in bitstreams whose trigger-core VERSION major is 2 or more.

## AXI GPIO `0xA012_0000`

| Offset | Bit | Meaning |
|--------|-----|---------|
| 0x00 (GPIO_DATA)  | 0 | MMCM reset (1 = reset) |
| 0x04 (GPIO_TRI)   | 0 | set to 0 (output) |
| 0x08 (GPIO2_DATA) | 0 | MMCM locked |

## Trigger / capture core `0xA010_0000`

All registers are 32 bit. RO = read only, RW = read/write, WO = write only, W1P = writing 1 generates a single pulse.

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x000 | ID | RO | `0x4C554E41` ("LUNA") |
| 0x004 | VERSION | RO | [31:16] major, [15:8] minor, [7:0] number of capture banks (4). Major 2 = the design includes the spectrometer; minor 1 adds VETO |
| 0x008 | CTRL | RW/W1P | bit0 **ARM** (level), bit8 **IRQ_EN** (level); pulses: bit1 SOFT_TRIG, bit2 TS_RESET (also flushes), bit3 FLUSH, bit4 CNT_CLEAR. Always write the level bits back with any pulse. |
| 0x00C | STATUS | RO | [3:0] banks full (events waiting), [7:4] head bank, bit8 capturing (post-trigger), bit9 readout busy, bit10 active bank pre-filled (ready to trigger), bit16 armed |
| 0x010 | MODE | RW | bit0: 0 = coincidence, 1 = anti-coincidence |
| 0x014 | COINC_N | RW | 1..8 channels required within the window (clamped) |
| 0x018 | WINDOW | RW | coincidence window W in samples, 1..255 (default 64) |
| 0x01C | CH_MASK | RW | [7:0] channels taking part in triggering (default 0xFF) |
| 0x020 | CAP_LEN | RW | samples per channel L, 4096..16384, multiple of 32 (default 16384) |
| 0x024 | READOUT | WO | bit0: stream the oldest full bank to the DMA |
| 0x028 | RELEASE | WO | bit0: free the oldest full bank (after its DMA completed) |
| 0x030 | TS_LO | RO | current sample counter [31:0]; reading it latches TS_HI |
| 0x034 | TS_HI | RO | current sample counter [63:32] |
| 0x038 | TRIG_COUNT | RO | accepted triggers |
| 0x03C | LOST_COUNT | RO | triggers lost: all banks full, or pre-trigger fill incomplete |
| 0x040 + 4·i | THRESH[i] | RW | channel i threshold; a sample with \|x\| > THRESH is a hit (16-bit units, 12-bit code × 16), reset value 0x4000 |
| 0x060 + 4·i | HITCNT[i] | RO | channel i: number of 245.76 MHz cycles containing ≥ 1 hit (free running) |
| 0x080 + 4·i | PEAK[i] | RO | channel i: max \|x\| since the last read (reading clears it) |
| 0x0A0 | SYSREF_CNT | RO | PL SYSREF rising edges seen (7.68 MHz when present) |
| 0x0A4 | SCRATCH | RW | scratch register |
| 0x0A8 | VETO | RW | [2:0] veto channel, bit8 enable. Anti-coincidence only: the veto channel never starts a trigger, but its hit within ±WINDOW of a candidate blocks it, whether or not it is set in CH_MASK. VERSION minor ≥ 1 |

### Event readout sequence (what `lunaserver` does)

1. The IRQ (level, SPI 89) is high while STATUS.banks_full > 0 and IRQ_EN = 1.
2. Program the DMA: DMASR ← clear, DMACR ← RS, S2MM_DA ← `0x7000_0000`, S2MM_LENGTH ← buffer size.
3. READOUT ← 1. The core streams 64 + 16·L bytes and asserts `tlast` on the last beat.
4. Wait for DMASR.IOC. S2MM_LENGTH then gives the number of bytes received.
5. Copy the event out of the buffer, then RELEASE ← 1.

### Event layout written by the DMA (little endian)

| Byte | Field |
|------|-------|
| 0  | magic "LUNA" |
| 4  | u16 version = 2, u16 header bytes = 64 (version 1: byte 52 is always 0) |
| 8  | u32 event sequence number |
| 12 | u32 samples per channel L |
| 16 | u64 trigger sample index T |
| 24 | u64 start sample index S (sample [0] of every channel) |
| 32 | u32 trigger offset T − S (= L/2 + T mod 16) |
| 36 | u8 trigger mask, u8 source (1 coinc, 2 anti, 3 soft), u8 channels (8), u8 bank |
| 40 | u16 window, u8 N, u8 mode |
| 44 | u32 lost-trigger count, u32 trigger count |
| 52 | u8 veto: bit7 enable, [2:0] channel (register VETO at trigger time; acts only when mode = 1) |
| 53 | reserved (11 bytes) |
| 64 | int16 ch0[L], ch1[L], … ch7[L] |

## Spectrometer `0xA014_0000`

Integrating spectrometer on one ADC channel (`hw/hdl/spectrometer_top.vhd`):

- **Input select:** the INPUT register picks one of the 8 ADC channels (default 0), after the trigger core's gearbox. It's a pipelined 8:1 mux at 245.76 MHz (spectrometer v1.1).
- **Coarse filter bank (`pfb32x16t`):** splits the 3.93216 GS/s real signal into 17 coarse channels ("subbands") of 122.88 MHz, each sampled at 122.88 MS/s complex. Subband k is centred on k × 122.88 MHz. Subbands 0 (DC) and 16 (Nyquist) are real.
- **Fine filter bank (`dfb4096x1c`):** the subband selected by SUBBAND goes to this 4096-channel filter bank, with 30 kHz channels. A spectrum takes 4096 / 122.88 MHz = 33.33 µs.
- **Integration:** the power in each channel is accumulated (64 bit) over ACC_LEN + 1 spectra. The default is 180000 spectra = 6.000 s.
- **Storage:** each integration is written to one of two banks. The interrupt is high while a full bank is waiting. When both banks are full, further integrations are counted in LOST_COUNT.

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x000 | ID | RO | `0x4C535043` ("LSPC") |
| 0x004 | VERSION | RO | [31:16] major, [15:8] minor, [7:0] number of banks (2). v1.1 adds INPUT |
| 0x008 | CTRL | RW/W1P | bit0 **ENABLE** (level; 0→1 restarts the integration), bit8 **IRQ_EN** (level); pulses: bit1 RESTART, bit4 CNT_CLEAR. Always write the level bits back with any pulse. |
| 0x00C | STATUS | RO | [1:0] banks full, bit4 head bank, bit8 enabled, bit9 running (fine filter bank fed), bit10 writing a bank |
| 0x010 | SUBBAND | RW | coarse channel 0..16 for the fine filter bank (default 12 = 1474.56 MHz). A write restarts the integration |
| 0x014 | ACC_LEN | RW | spectra per integration − 1 (default 179999 = 6.000 s). A write restarts the integration |
| 0x018 | RELEASE | WO | bit0: free the oldest full bank |
| 0x01C | SPEC_COUNT | RO | integrations stored (= next sequence number) |
| 0x020 | LOST_COUNT | RO | integrations lost because both banks were full |
| 0x024 | RESTARTS | RO | integration restarts |
| 0x028 | SCRATCH | RW | scratch register |
| 0x02C | INPUT | RW | ADC channel 0..7 feeding the filter banks (default 0, v1.1+). A write restarts the integration |
| 0x030 | HEAD_SEQ | RO | oldest full bank: sequence number |
| 0x034 | HEAD_FLAGS | RO | oldest full bank: bit0 first integration after a restart, [12:8] subband, [18:16] input ADC channel |
| 0x038 | HEAD_ACCLEN | RO | oldest full bank: ACC_LEN it was integrated with |
| 0x03C / 0x040 | HEAD_TS_LO / HI | RO | oldest full bank: ADC sample counter (trigger-core time base) when the integration ended |
| 0x10000 + 0x8000·b + 8·k | BANK[b][k] | RO | bank b, fine channel k: accumulated power [31:0] at +0, [63:32] at +4 |

**Restarts:**
- **What causes one:** ENABLE 0→1, RESTART, or a write to INPUT, SUBBAND or ACC_LEN. The fine filter bank is resynchronised and its accumulator restarts from zero. An integration that was being written is discarded.
- **Settling after a restart:** the fine filter bank re-synchronises its accumulator about 5 spectra (170 µs) after a restart, when the FFT output restarts. Until then it keeps producing integrations on its old schedule, which may be empty, mixed or cut short. The wrapper ignores every output that begins within 6 spectra of the (re)start, and stores an integration only if all 4096 channels arrived. The first integration stored after a restart therefore contains only data from after the change; it is flagged in HEAD_FLAGS for information.
- **Delay before the first integration:** about 6 spectra (0.2 ms) plus the integration time.

**Fine channel order:**
- Channels are in FFT order. Channel k is at the subband centre + k × 30 kHz for k < 2048, and at the centre + (k − 4096) × 30 kHz for k ≥ 2048.
- `tb_spec` checks this with tones at +25 and −100 channels.

### Spectrum readout sequence (what `lunaserver` does)

1. The IRQ (level, SPI 92) is high while STATUS.banks_full > 0 and IRQ_EN = 1.
2. Read HEAD_SEQ, HEAD_FLAGS, HEAD_ACCLEN and HEAD_TS_LO/HI.
3. Read the 4096 × 64-bit powers of bank STATUS.head (8192 AXI-Lite reads, about 3 ms).
4. RELEASE ← 1.

## Channel mapping

Verified against UG1271 (J47 RFMC connector table) and schematic 0381811.

| Channel | RFDC tile / ADC | IP stream | Package pins | ZCU111 net (J47) |
|---------|-----------------|-----------|--------------|------------------|
| 0 | 224 / VIN_I01 | m00_axis | AP2/AP1 | RFMC_ADC_00 |
| 1 | 224 / VIN_I23 | m02_axis | AM2/AM1 | RFMC_ADC_01 |
| 2 | 225 / VIN_I01 | m10_axis | AK2/AK1 | RFMC_ADC_02 |
| 3 | 225 / VIN_I23 | m12_axis | AH2/AH1 | RFMC_ADC_03 |
| 4 | 226 / VIN_I01 | m20_axis | AF2/AF1 | RFMC_ADC_04 |
| 5 | 226 / VIN_I23 | m22_axis | AD2/AD1 | RFMC_ADC_05 |
| 6 | 227 / VIN_I01 | m30_axis | AB2/AB1 | RFMC_ADC_06 |
| 7 | 227 / VIN_I23 | m32_axis | Y2/Y1 | RFMC_ADC_07 |
