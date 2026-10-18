/*
 * spec.c - integrating spectrometer on a selectable ADC channel (INPUT)
 *
 * The FPGA accumulates ACC_LEN+1 spectra of 4096 fine channels of the
 * selected coarse channel (SUBBAND) of the selected ADC channel (INPUT)
 * and stores each integration in one of
 * two banks; the interrupt stays high while a full bank is waiting.  The
 * banks are read here over AXI-Lite (8192 32-bit reads, ~3 ms) and freed.
 */
#include "spec.h"

#include <math.h>
#include <string.h>

#include "log.h"
#include "pl_regs.h"

#define FS_HZ SPEC_FS_HZ

/* coarse decimation of the bitstream (spec_decim) */
static int g_decim = LUNA_SPEC_D;

int spec_init(struct pl *p)
{
    p->has_spec = 0;
    uint32_t ver = hw_rd(&p->trig, TR_VERSION);
    if ((ver >> 16) < TR_VERSION_SPEC) {
        LOGI("spec: bitstream v%u.%u has no spectrometer", ver >> 16, (ver >> 8) & 0xFF);
        return -1;
    }
    if (hw_open(&p->spec, SPEC_BASE, SPEC_SIZE) < 0)
        return -1;
    uint32_t id = hw_rd(&p->spec, SP_ID);
    if (id != SP_ID_VALUE) {
        LOGE("spec: ID 0x%08x != 0x%08x", id, SP_ID_VALUE);
        hw_close(&p->spec);
        return -1;
    }
    uint32_t sv = hw_rd(&p->spec, SP_VERSION);
    LOGI("spec: spectrometer v%u.%u, %u banks", sv >> 16, (sv >> 8) & 0xFF, sv & 0xFF);
    p->spec_has_input = (sv >> 16) > 1 || ((sv >> 16) == 1 && ((sv >> 8) & 0xFF) >= 1);
    if (!p->spec_has_input)
        LOGW("spec: no input selector in this bitstream - ADC channel 0 only");
    if ((sv >> 16) >= 2) {
        uint32_t pc = hw_rd(&p->spec, SP_PFB_CFG);
        g_decim = (int)SPP_D(pc);
        if (SPP_M(pc) != LUNA_SPEC_M || g_decim < 16 || g_decim > LUNA_SPEC_M) {
            LOGW("spec: unexpected PFB_CFG 0x%08x - assuming D = %d", pc, LUNA_SPEC_D);
            g_decim = LUNA_SPEC_D;
        }
        LOGI("spec: coarse filter bank %u branches, %u taps each, decimation %d "
             "(oversampled %u/%d): fine channel %.3f kHz, spectrum %.3f us",
             SPP_M(pc), SPP_T(pc), g_decim, SPP_M(pc), g_decim,
             spec_fine_hz() / 1e3, spec_t_spectrum() * 1e6);
    } else {
        g_decim = LUNA_SPEC_M;
        LOGI("spec: critically sampled coarse filter bank (v1): fine channel %.3f kHz, "
             "spectrum %.3f us", spec_fine_hz() / 1e3, spec_t_spectrum() * 1e6);
    }
    /* drop anything left from a previous run */
    hw_wr(&p->spec, SP_CTRL, SPC_CNT_CLEAR);
    while (SPS_NFULL(hw_rd(&p->spec, SP_STATUS)))
        hw_wr(&p->spec, SP_RELEASE, 1);
    p->has_spec = 1;
    p->spec_shadow_valid = 0;
    return 0;
}

void spec_apply(struct pl *p, const struct luna_config *c)
{
    if (!p->has_spec)
        return;
    uint32_t acc = c->spec_nspec - 1;
    uint32_t sb = (uint32_t)c->spec_subband;
    uint32_t in = (uint32_t)c->spec_input;
    if (p->spec_has_input && (!p->spec_shadow_valid || in != p->spec_input))
        hw_wr(&p->spec, SP_INPUT, in);
    p->spec_input = in;
    if (!p->spec_shadow_valid || acc != p->spec_acc_len)
        hw_wr(&p->spec, SP_ACC_LEN, acc);
    if (!p->spec_shadow_valid || sb != p->spec_subband)
        hw_wr(&p->spec, SP_SUBBAND, sb);
    p->spec_acc_len = acc;
    p->spec_subband = sb;
    p->spec_shadow_valid = 1;
    /* ENABLE is a level; 0 -> 1 restarts the integration in the FPGA */
    hw_wr(&p->spec, SP_CTRL, SPC_IRQ_EN | (c->spec_enable ? SPC_ENABLE : 0));
}

void spec_restart(struct pl *p)
{
    if (!p->has_spec)
        return;
    uint32_t ctrl = hw_rd(&p->spec, SP_CTRL) & (SPC_ENABLE | SPC_IRQ_EN);
    hw_wr(&p->spec, SP_CTRL, ctrl | SPC_RESTART);
}

void spec_get_status(struct pl *p, struct spec_status *s)
{
    memset(s, 0, sizeof *s);
    if (!p->has_spec)
        return;
    s->status = hw_rd(&p->spec, SP_STATUS);
    s->count = hw_rd(&p->spec, SP_SPEC_COUNT);
    s->lost = hw_rd(&p->spec, SP_LOST_COUNT);
    s->restarts = hw_rd(&p->spec, SP_RESTARTS);
}

int spec_read(struct pl *p, struct luna_spec_hdr *h, uint64_t *power)
{
    if (!p->has_spec)
        return 0;
    uint32_t st = hw_rd(&p->spec, SP_STATUS);
    if (SPS_NFULL(st) == 0)
        return 0;
    uint32_t base = SP_MEM(SPS_HEAD(st));
    uint32_t flags = hw_rd(&p->spec, SP_HEAD_FLAGS);
    h->seq = hw_rd(&p->spec, SP_HEAD_SEQ);
    h->n_spectra = hw_rd(&p->spec, SP_HEAD_ACCLEN) + 1;
    h->subband = (uint8_t)SPF_SUBBAND(flags);
    h->adc_input = (uint8_t)SPF_INPUT(flags);
    h->flags = ((flags & SPF_FIRST) ? LUNA_SPEC_F_FIRST : 0) |
               ((uint32_t)g_decim << LUNA_SPEC_F_DECIM_SHIFT);
    h->end_sample = ((uint64_t)hw_rd(&p->spec, SP_HEAD_TS_HI) << 32) |
                    hw_rd(&p->spec, SP_HEAD_TS_LO);
    for (int k = 0; k < LUNA_SPEC_NCHAN; k++) {
        uint32_t lo = hw_rd(&p->spec, base + 8u * (uint32_t)k);
        uint32_t hi = hw_rd(&p->spec, base + 8u * (uint32_t)k + 4u);
        power[k] = ((uint64_t)hi << 32) | lo;
    }
    hw_wr(&p->spec, SP_RELEASE, 1);
    h->lost = hw_rd(&p->spec, SP_LOST_COUNT);
    h->restarts = hw_rd(&p->spec, SP_RESTARTS);
    return 1;
}

int spec_has_input(const struct pl *p)
{
    return p->has_spec && p->spec_has_input;
}

int spec_decim(void)
{
    return g_decim;
}

double spec_t_spectrum(void)
{
    return LUNA_SPEC_NCHAN * (double)g_decim / FS_HZ;
}

double spec_fine_hz(void)
{
    return FS_HZ / g_decim / LUNA_SPEC_NCHAN;
}

uint32_t spec_nspec_from_seconds(double t)
{
    double n = floor(t / spec_t_spectrum() + 0.5);
    if (n < 1)
        n = 1;
    if (n > 4294967295.0)
        n = 4294967295.0;
    return (uint32_t)n;
}

double spec_seconds(uint32_t nspec)
{
    return nspec * spec_t_spectrum();
}

double spec_centre_hz(int subband)
{
    return subband * FS_HZ / LUNA_SPEC_M;
}
