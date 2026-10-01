/* pl.h - trigger/capture core, MMCM control and DMA event readout */
#ifndef PL_H
#define PL_H

#include <stddef.h>
#include <stdint.h>

#include "config.h"
#include "hw.h"

struct pl {
    struct hw_region trig;   /* trigger_capture registers (+ trigger IRQ)  */
    struct hw_region dma;    /* AXI DMA S2MM                                */
    struct hw_region gpio;   /* MMCM reset / locked                         */
    struct hw_region buf;    /* DMA target buffer (reserved memory)         */
    struct hw_region spec;   /* spectrometer registers + spectrum banks     */
    int nbanks;
    uint32_t ctrl_levels;    /* shadow of the CTRL level bits (ARM, IRQ_EN) */
    int has_spec;            /* spectrometer present (see spec.h)           */
    int spec_shadow_valid;
    uint32_t spec_acc_len, spec_subband;   /* last values written          */
};

int  pl_open(struct pl *p);
void pl_close(struct pl *p);

/* reset the MMCM (after the LMK04208 has been programmed) and wait for lock */
int  pl_mmcm_start(struct pl *p, int timeout_ms);
int  pl_mmcm_locked(struct pl *p);

/* check the core ID, flush banks, reset DMA */
int  pl_core_init(struct pl *p);
void pl_apply_config(struct pl *p, const struct luna_config *c);
void pl_arm(struct pl *p, int arm);
void pl_soft_trigger(struct pl *p);
uint32_t pl_status(struct pl *p);
uint64_t pl_timestamp(struct pl *p);

/*
 * Read the oldest captured event: start the readout stream, DMA it to the
 * reserved buffer, copy it to 'dst' and release the bank.
 * Returns the number of bytes (64-byte header + 8*L*2), 0 if no event
 * is waiting, -1 on error.
 */
long pl_read_event(struct pl *p, void *dst, size_t max);

/* statistics */
void pl_counters(struct pl *p, uint32_t *trig, uint32_t *lost, uint32_t *sysref);
void pl_hit_counts(struct pl *p, uint32_t cnt[8]);
void pl_peaks(struct pl *p, uint16_t peak[8]);

#endif
