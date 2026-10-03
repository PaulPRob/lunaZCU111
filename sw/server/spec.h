/* spec.h - integrating spectrometer on a selectable ADC channel (hw/hdl/spectrometer_top.vhd) */
#ifndef SPEC_H
#define SPEC_H

#include <stdint.h>

#include "config.h"
#include "pl.h"
#include "protocol.h"

/* one spectrum: 4096 fine channels of 1/(122.88 MHz) * 4096 = 33.33 us */
#define SPEC_T_SPECTRUM   (LUNA_SPEC_NCHAN / LUNA_SPEC_FFT_CLK)
#define SPEC_FRAME_BYTES  (sizeof(struct luna_spec_hdr) + 8u * LUNA_SPEC_NCHAN)

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

/* integration time <-> number of spectra */
uint32_t spec_nspec_from_seconds(double t);
double   spec_seconds(uint32_t nspec);
/* centre frequency of coarse channel 'subband' (Hz, first Nyquist zone) */
double   spec_centre_hz(int subband);

#endif
