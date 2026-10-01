/* config.h - trigger and spectrometer configuration (persisted in /etc/lunaserver.conf) */
#ifndef CONFIG_H
#define CONFIG_H

#include <stdint.h>
#include "protocol.h"

struct luna_config {
    uint16_t thresh[LUNA_NCH];  /* |x| > thresh is a hit (16-bit sample units) */
    int      mode_anti;         /* 0 coincidence, 1 anti-coincidence            */
    int      coinc_n;           /* 1..8                                          */
    int      window;            /* 1..255 samples                                */
    uint32_t ch_mask;           /* channels taking part                          */
    int      cap_len;           /* 4096..16384 samples, multiple of 32           */
    int      armed;             /* arm on start-up                               */
    /* spectrometer (ADC channel 0) */
    int      spec_enable;       /* 0/1                                           */
    int      spec_subband;      /* coarse channel 0..16 for the fine spectrum    */
    uint32_t spec_nspec;        /* spectra per integration (180000 = 6.000 s)    */
};

#define SPEC_NSPEC_DEFAULT  180000u
#define SPEC_SUBBAND_DEFAULT 12

void config_defaults(struct luna_config *c);
int  config_load(struct luna_config *c, const char *path);
int  config_save(const struct luna_config *c, const char *path);
/* clamp to valid ranges; returns 0 */
int  config_sanitize(struct luna_config *c);

#endif
