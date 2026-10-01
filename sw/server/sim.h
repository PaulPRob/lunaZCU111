/* sim.h - synthetic events for testing clients without hardware */
#ifndef SIM_H
#define SIM_H

#include <stddef.h>
#include <stdint.h>

#include "config.h"

/* build one event (FPGA header + 8 x L samples) as the PL would; returns bytes */
size_t sim_make_event(const struct luna_config *c, void *dst, size_t max,
                      uint32_t seq, uint64_t trig_sample);

/* one integration of the spectrometer: power[LUNA_SPEC_NCHAN] in FFT order */
void sim_make_spectrum(const struct luna_config *c, uint64_t *power);

#endif
