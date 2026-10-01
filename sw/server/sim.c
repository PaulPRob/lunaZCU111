/*
 * sim.c - synthetic events with the exact FPGA event layout
 *
 * Each channel: Gaussian-like noise (~40 ADC codes rms, 12-bit code in the
 * top bits) plus, on the channels of a random trigger mask, a short
 * band-limited pulse centred on the trigger offset.
 */
#include "sim.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "protocol.h"

static uint32_t rng_state = 0x12345678u;

static uint32_t xorshift(void)
{
    uint32_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return rng_state = x;
}

static double gauss(void)
{
    /* sum of 4 uniforms, variance 1 */
    double s = 0;
    for (int i = 0; i < 4; i++)
        s += (double)(xorshift() & 0xFFFF) / 65536.0;
    return (s - 2.0) * 1.7320508;
}

size_t sim_make_event(const struct luna_config *c, void *dst, size_t max,
                      uint32_t seq, uint64_t trig_sample)
{
    const uint32_t L = (uint32_t)c->cap_len;
    size_t bytes = sizeof(struct luna_event_hdr) + (size_t)L * LUNA_NCH * 2;
    if (bytes > max)
        return 0;

    struct luna_event_hdr *h = dst;
    memset(h, 0, sizeof *h);
    trig_sample &= ~(uint64_t)0 >> 1;
    uint64_t start = ((trig_sample >> 4) - L / 32) << 4;
    h->magic = LUNA_EVENT_MAGIC;
    h->version = 1;
    h->hdr_bytes = 64;
    h->seq = seq;
    h->n_samples = L;
    h->trig_sample = trig_sample;
    h->start_sample = start;
    h->trig_offset = (uint32_t)(trig_sample - start);
    h->n_channels = LUNA_NCH;
    h->bank = (uint8_t)(seq & 3);
    h->window = (uint16_t)c->window;
    h->coinc_n = (uint8_t)c->coinc_n;
    h->mode = (uint8_t)c->mode_anti;
    h->trig_count = seq + 1;

    uint8_t mask;
    if (c->mode_anti) {
        mask = (uint8_t)(1u << (xorshift() % LUNA_NCH));
        h->trig_src = LUNA_SRC_ANTI;
    } else {
        if (__builtin_popcount(c->ch_mask) <= c->coinc_n) {
            mask = (uint8_t)c->ch_mask;
        } else {
            do {
                mask = (uint8_t)(xorshift() & c->ch_mask);
            } while (__builtin_popcount(mask) < c->coinc_n);
        }
        h->trig_src = LUNA_SRC_COINC;
    }
    h->trig_mask = mask;

    int16_t *s = (int16_t *)(h + 1);
    for (int ch = 0; ch < LUNA_NCH; ch++) {
        int delay = (mask >> ch) & 1 ? -(int)(xorshift() % (uint32_t)c->window) : 0;
        double amp = 1.2 * c->thresh[ch] / 16.0;          /* in ADC codes */
        for (uint32_t i = 0; i < L; i++) {
            double v = 40.0 * gauss();
            if ((mask >> ch) & 1) {
                double t = (double)((int)i - (int)h->trig_offset - delay);
                v += amp * exp(-t * t / 18.0) * cos(0.9 * t);
            }
            long code = lround(v);
            if (code > 2047) code = 2047;
            if (code < -2048) code = -2048;
            s[ch * L + i] = (int16_t)(code * 16);         /* MSB justified */
        }
    }
    return bytes;
}
