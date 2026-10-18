/* config.c - load/save trigger and spectrometer configuration as key=value text */
#include "config.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "log.h"

void config_defaults(struct luna_config *c)
{
    memset(c, 0, sizeof *c);
    for (int i = 0; i < LUNA_NCH; i++)
        c->thresh[i] = 16384;
    c->mode_anti = 0;
    c->coinc_n = 2;
    c->window = 64;
    c->ch_mask = 0xFF;
    c->cap_len = 16384;
    c->armed = 1;
    c->spec_enable = 1;
    c->spec_input = 0;
    c->spec_subband = SPEC_SUBBAND_DEFAULT;
    c->spec_nspec = SPEC_NSPEC_DEFAULT;
    c->spec_tint = SPEC_TINT_DEFAULT;
}

int config_sanitize(struct luna_config *c)
{
    if (c->coinc_n < 1) c->coinc_n = 1;
    if (c->coinc_n > LUNA_NCH) c->coinc_n = LUNA_NCH;
    if (c->window < 1) c->window = 1;
    if (c->window > 255) c->window = 255;
    c->ch_mask &= 0xFF;
    c->veto_en = !!c->veto_en;
    if (c->veto_ch < 0 || c->veto_ch >= LUNA_NCH) c->veto_ch = 0;
    if (c->cap_len < LUNA_MIN_SAMPLES) c->cap_len = LUNA_MIN_SAMPLES;
    if (c->cap_len > LUNA_MAX_SAMPLES) c->cap_len = LUNA_MAX_SAMPLES;
    c->cap_len &= ~31;
    c->mode_anti = !!c->mode_anti;
    c->armed = !!c->armed;
    c->spec_enable = !!c->spec_enable;
    if (c->spec_input < 0 || c->spec_input >= LUNA_SPEC_NINPUT) c->spec_input = 0;
    if (c->spec_subband < 0) c->spec_subband = 0;
    if (c->spec_subband > LUNA_SPEC_NSUB - 1) c->spec_subband = LUNA_SPEC_NSUB - 1;
    if (c->spec_nspec < 1) c->spec_nspec = 1;
    if (!(c->spec_tint > 0)) c->spec_tint = SPEC_TINT_DEFAULT;
    return 0;
}

int config_load(struct luna_config *c, const char *path)
{
    FILE *f = fopen(path, "r");
    if (!f) {
        if (errno != ENOENT)
            LOGW("config: cannot read %s: %s", path, strerror(errno));
        return -1;
    }
    char line[256];
    int have_tint = 0, have_nspec = 0;
    while (fgets(line, sizeof line, f)) {
        char key[64];
        long v;
        int ch;
        double d;
        if (line[0] == '#')
            continue;
        if (sscanf(line, "spec_tint = %lf", &d) == 1) {
            c->spec_tint = d;
            have_tint = 1;
        } else if (sscanf(line, "thresh%d = %li", &ch, &v) == 2 && ch >= 0 && ch < LUNA_NCH)
            c->thresh[ch] = (uint16_t)v;
        else if (sscanf(line, "%63[a-z_] = %li", key, &v) == 2) {
            if (!strcmp(key, "mode_anti"))    c->mode_anti = (int)v;
            else if (!strcmp(key, "coinc_n")) c->coinc_n = (int)v;
            else if (!strcmp(key, "window"))  c->window = (int)v;
            else if (!strcmp(key, "ch_mask")) c->ch_mask = (uint32_t)v;
            else if (!strcmp(key, "veto_enable")) c->veto_en = (int)v;
            else if (!strcmp(key, "veto_ch"))     c->veto_ch = (int)v;
            else if (!strcmp(key, "cap_len")) c->cap_len = (int)v;
            else if (!strcmp(key, "armed"))   c->armed = (int)v;
            else if (!strcmp(key, "spec_enable"))  c->spec_enable = (int)v;
            else if (!strcmp(key, "spec_input"))   c->spec_input = (int)v;
            else if (!strcmp(key, "spec_subband")) c->spec_subband = (int)v;
            else if (!strcmp(key, "spec_nspec")) {
                c->spec_nspec = (uint32_t)v;
                have_nspec = 1;
            }
        }
    }
    fclose(f);
    /* a file from before spec_tint: keep its integration time, which was
     * spec_nspec spectra of the critically sampled spectrometer */
    if (have_nspec && !have_tint) {
        c->spec_tint = c->spec_nspec * SPEC_T_SPECTRUM_V1;
        LOGI("config: spec_nspec = %u from an older server = %.6f s", c->spec_nspec,
             c->spec_tint);
    }
    config_sanitize(c);
    LOGI("config: loaded %s", path);
    return 0;
}

int config_save(const struct luna_config *c, const char *path)
{
    char tmp[512];
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "w");
    if (!f) {
        LOGE("config: cannot write %s: %s", tmp, strerror(errno));
        return -1;
    }
    fprintf(f, "# lunaserver configuration\n");
    for (int i = 0; i < LUNA_NCH; i++)
        fprintf(f, "thresh%d = %u\n", i, c->thresh[i]);
    fprintf(f, "mode_anti = %d\ncoinc_n = %d\nwindow = %d\nch_mask = 0x%02X\n"
               "cap_len = %d\narmed = %d\n",
            c->mode_anti, c->coinc_n, c->window, c->ch_mask, c->cap_len, c->armed);
    fprintf(f, "veto_enable = %d\nveto_ch = %d\n", c->veto_en, c->veto_ch);
    fprintf(f, "spec_enable = %d\nspec_input = %d\nspec_subband = %d\nspec_nspec = %u\n",
            c->spec_enable, c->spec_input, c->spec_subband, c->spec_nspec);
    fprintf(f, "spec_tint = %.9g\n", c->spec_tint);
    fclose(f);
    if (rename(tmp, path) < 0) {
        LOGE("config: rename to %s: %s", path, strerror(errno));
        return -1;
    }
    return 0;
}
