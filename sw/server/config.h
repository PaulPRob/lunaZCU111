/* config.h - trigger configuration (persisted in /etc/lunaserver.conf) */
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
};

void config_defaults(struct luna_config *c);
int  config_load(struct luna_config *c, const char *path);
int  config_save(const struct luna_config *c, const char *path);
/* clamp to valid ranges; returns 0 */
int  config_sanitize(struct luna_config *c);

#endif
