/* spec.h - integrating spectrometer on a selectable ADC channel (hw/hdl/spectrometer_top.vhd) */
#ifndef SPEC_H
#define SPEC_H

#include <stdint.h>

#include "config.h"
#include "pl.h"
#include "protocol.h"

#define SPEC_FRAME_BYTES  (sizeof(struct luna_spec_hdr) + 8u * LUNA_SPEC_NCHAN)
#define SPEC_FS_HZ        3.93216e9

struct spec_status {
    uint32_t status;      /* SP_STATUS                              */
    uint32_t count;       /* integrations stored                    */
    uint32_t lost;        /* integrations lost (both banks full)    */
    uint32_t restarts;
};

/*
 * Map the spectrometer and check its ID.  Call after pl_core_init() (the
 * trigger core VERSION tells whether the bitstream has a spectrometer;
 * touching a missing AXI slave would hang the bus).  Returns 0 if present.
 */
int  spec_init(struct pl *p);
/* enable / input / subband / integration length; INPUT, SUBBAND and ACC_LEN
 * are only written when they change (a write restarts the integration) */
void spec_apply(struct pl *p, const struct luna_config *c);
void spec_restart(struct pl *p);
void spec_get_status(struct pl *p, struct spec_status *s);
/* the bitstream's spectrometer has the INPUT register (v1.1+) */
int  spec_has_input(const struct pl *p);
/*
 * Read the oldest stored integration: fill the FPGA fields of 'h' (seq,
 * n_spectra, subband, adc_input, flags FIRST, end_sample, lost, restarts) and
 * power[LUNA_SPEC_NCHAN], then free the bank.
 * Returns 1 if a spectrum was read, 0 if none is waiting.
 */
int  spec_read(struct pl *p, struct luna_spec_hdr *h, uint64_t *power);

/*
 * Coarse decimation D of the bitstream's filter bank: 27 (oversampled 32/27,
 * spectrometer v2.0+, also the default without hardware) or 32 (critically
 * sampled, v1.x).  The subband is sampled at fs/D, a fine channel is
 * fs/D/4096 wide and one spectrum lasts 4096 * D / fs.
 */
int      spec_decim(void);
double   spec_t_spectrum(void);      /* s: 28.125 us (D = 27), 33.33 us (32) */
double   spec_fine_hz(void);         /* 35.556 kHz (D = 27), 30 kHz (32)    */
/* integration time <-> number of spectra */
uint32_t spec_nspec_from_seconds(double t);
double   spec_seconds(uint32_t nspec);
/* centre frequency of coarse channel 'subband' (Hz, first Nyquist zone);
 * the subbands are fs/32 = 122.88 MHz apart */
double   spec_centre_hz(int subband);

#endif
