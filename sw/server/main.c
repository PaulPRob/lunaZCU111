/*
 * lunaserver - ZCU111 8-channel transient capture server (runs on the PS)
 *
 *  - programs the RF clocks (LMK04208 / LMX2594), starts the MMCM, the RF
 *    data converter and multi-tile synchronisation
 *  - configures the trigger core, waits for its interrupt (UIO), reads each
 *    captured event via DMA and pushes it to all clients on TCP 5000
 *  - runs the integrating spectrometer on one ADC channel and pushes each
 *    integration to all clients on TCP 5002
 *  - accepts text commands on TCP 5001 (thresholds, mode, spectrometer ...)
 *
 * usage: lunaserver [options]
 *   -c FILE     configuration file (default /etc/lunaserver.conf)
 *   -d PORT     data port (5000)          -p PORT   control port (5001)
 *   -S PORT     spectrum port (5002)
 *   -b BUS      i2c bus of the SC18IS602 (default: auto)
 *   -n          do not program the RF clocks (already done)
 *   -s RATE     simulation: no hardware, synthetic events at RATE Hz
 *   -v          verbose
 */
#include <errno.h>
#include <getopt.h>
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/timerfd.h>
#include <time.h>
#include <unistd.h>

#include "clocks.h"
#include "config.h"
#include "log.h"
#include "net.h"
#include "pl.h"
#include "pl_regs.h"
#include "protocol.h"
#include "rfdc_init.h"
#include "sim.h"
#include "spec.h"

#define FS_HZ        3.93216e9
#define EVENT_MAX    (sizeof(struct luna_event_hdr) + LUNA_MAX_SAMPLES * LUNA_NCH * 2)
#define SPEC_PAYLOAD (8u * LUNA_SPEC_NCHAN)
#define SIM_SPEC_MIN_PERIOD 0.1    /* s, simulation only */

int g_verbose;

static volatile sig_atomic_t g_stop;
static struct luna_config g_cfg;
static const char *g_cfg_path = "/etc/lunaserver.conf";
static struct pl g_pl;
static int g_sim;
static double g_sim_rate = 1.0;
static uint32_t g_sim_seq;
static uint64_t g_events;
static uint64_t g_spectra;
static struct net *g_net;
static int g_spec_fd = -1;          /* spectrometer UIO fd, or timerfd in simulation */
static uint32_t g_sim_spec_seq, g_sim_spec_restarts;
static int g_sim_spec_first = 1;

/* rates */
static uint32_t g_last_hits[LUNA_NCH];
static struct timespec g_last_hits_t;

static void sim_tick(int force);

static void on_signal(int s) { (void)s; g_stop = 1; }

static double now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ts.tv_nsec * 1e-9;
}

static uint64_t realtime_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static int spec_present(void)
{
    return g_sim || g_pl.has_spec;
}

static int veto_present(void)
{
    return g_sim || g_pl.has_veto;
}

/* "OFF", the veto channel, or "absent" (bitstream without the VETO register) */
static const char *veto_str(void)
{
    static char s[8];
    if (!veto_present())
        return "absent";
    if (!g_cfg.veto_en)
        return "OFF";
    snprintf(s, sizeof s, "%d", g_cfg.veto_ch);
    return s;
}

/* simulation: one synthetic integration per integration time (>= 0.1 s) */
static void sim_spec_timer_update(void)
{
    if (!g_sim || g_spec_fd < 0)
        return;
    struct itimerspec its = { 0 };
    if (g_cfg.spec_enable) {
        double period = spec_seconds(g_cfg.spec_nspec);
        if (period < SIM_SPEC_MIN_PERIOD)
            period = SIM_SPEC_MIN_PERIOD;
        its.it_interval.tv_sec = (time_t)period;
        its.it_interval.tv_nsec = (long)((period - floor(period)) * 1e9);
        its.it_value = its.it_interval;
    }
    timerfd_settime(g_spec_fd, 0, &its, NULL);
}

static void apply_config(void)
{
    config_sanitize(&g_cfg);
    if (!g_sim) {
        pl_apply_config(&g_pl, &g_cfg);
        pl_arm(&g_pl, g_cfg.armed);
        spec_apply(&g_pl, &g_cfg);
    }
}

/* the spectrometer settings changed: the FPGA restarts the integration */
static void spec_changed(void)
{
    if (g_sim) {
        g_sim_spec_first = 1;
        g_sim_spec_restarts++;
        sim_spec_timer_update();
    }
    apply_config();
}

/* ------------------------------------------------------------------------ */
/* control commands                                                         */
/* ------------------------------------------------------------------------ */

static const char *help_text =
    "OK commands: STATUS | GET CONFIG | GET RATES | GET PEAKS | "
    "SET THRESH <ch|ALL> <0-32767> | SET MODE COINC|ANTI | SET N <1-8> | "
    "SET WINDOW <1-255> | SET MASK <0x00-0xFF> | SET VETO <0-7|OFF> | SET LEN <4096-16384> | "
    "ARM | DISARM | SOFTTRIG | RESYNC | "
    "GET SPEC | SPEC ON|OFF|RESTART | SET SPEC_INPUT <0-7> | SET SPEC_SUBBAND <0-16> | "
    "SET SPEC_TINT <seconds> | SET SPEC_NSPEC <spectra> | SAVE | HELP";

static void cmd_status(char *r, size_t n)
{
    uint32_t st = 0, trig = 0, lost = 0, sysref = 0;
    uint64_t ts = 0;
    char rf[256] = "rfdc=sim";
    if (!g_sim) {
        st = pl_status(&g_pl);
        pl_counters(&g_pl, &trig, &lost, &sysref);
        ts = pl_timestamp(&g_pl);
        rf_status(rf, sizeof rf);
    } else {
        trig = g_sim_seq;
    }
    snprintf(r, n,
             "OK armed=%d mode=%s n=%d window=%d mask=0x%02X veto=%s len=%d banks_full=%u "
             "capturing=%d triggers=%u lost=%u events=%llu clients=%d sent=%llu "
             "dropped=%llu sample=%llu sysref=%u %s spec=%s spectra=%llu",
             g_cfg.armed, g_cfg.mode_anti ? "ANTI" : "COINC", g_cfg.coinc_n, g_cfg.window,
             g_cfg.ch_mask, veto_str(), g_cfg.cap_len, ST_NFULL(st), !!(st & ST_CAPTURING),
             trig, lost,
             (unsigned long long)g_events, net_data_clients(g_net, NET_STREAM_EVENTS),
             (unsigned long long)net_frames_sent(g_net, NET_STREAM_EVENTS),
             (unsigned long long)net_frames_dropped(g_net, NET_STREAM_EVENTS),
             (unsigned long long)ts, sysref, rf,
             !spec_present() ? "absent" : g_cfg.spec_enable ? "on" : "off",
             (unsigned long long)g_spectra);
}

static void cmd_spec(char *r, size_t n)
{
    struct spec_status s = { 0 };
    if (!g_sim)
        spec_get_status(&g_pl, &s);
    else {
        s.count = g_sim_spec_seq;
        s.restarts = g_sim_spec_restarts;
    }
    snprintf(r, n,
             "OK present=%d enabled=%d input=%d subband=%d nspec=%u tint=%.6f centre_mhz=%.3f "
             "bandwidth_mhz=%.3f fine_khz=%.3f integrations=%u lost=%u restarts=%u "
             "banks_full=%u clients=%d sent=%llu dropped=%llu",
             spec_present(), g_cfg.spec_enable, g_cfg.spec_input, g_cfg.spec_subband,
             g_cfg.spec_nspec,
             spec_seconds(g_cfg.spec_nspec), spec_centre_hz(g_cfg.spec_subband) / 1e6,
             FS_HZ / 32 / 1e6, FS_HZ / 32 / LUNA_SPEC_NCHAN / 1e3, s.count, s.lost, s.restarts,
             SPS_NFULL(s.status), net_data_clients(g_net, NET_STREAM_SPEC),
             (unsigned long long)net_frames_sent(g_net, NET_STREAM_SPEC),
             (unsigned long long)net_frames_dropped(g_net, NET_STREAM_SPEC));
}

/* SET SPEC_* ; returns 0 if handled (reply written), 1 if not a SPEC_ key */
static int set_spec(const char *key, const char *val, char *r, size_t n)
{
    char *end;
    if (!strcasecmp(key, "SPEC_INPUT")) {
        long v = strtol(val, &end, 0);
        if (*end || v < 0 || v >= LUNA_SPEC_NINPUT) {
            snprintf(r, n, "ERR SPEC_INPUT must be 0-7");
            return 0;
        }
        if (v != 0 && !g_sim && !spec_has_input(&g_pl)) {
            snprintf(r, n, "ERR this bitstream's spectrometer has ADC channel 0 only");
            return 0;
        }
        g_cfg.spec_input = (int)v;
    } else if (!strcasecmp(key, "SPEC_SUBBAND")) {
        long v = strtol(val, &end, 0);
        if (*end || v < 0 || v >= LUNA_SPEC_NSUB) {
            snprintf(r, n, "ERR SPEC_SUBBAND must be 0-16");
            return 0;
        }
        g_cfg.spec_subband = (int)v;
    } else if (!strcasecmp(key, "SPEC_TINT")) {
        double t = strtod(val, &end);
        if (*end || !(t > 0) || t > 1e5) {
            snprintf(r, n, "ERR SPEC_TINT must be > 0 seconds");
            return 0;
        }
        g_cfg.spec_nspec = spec_nspec_from_seconds(t);
    } else if (!strcasecmp(key, "SPEC_NSPEC")) {
        unsigned long v = strtoul(val, &end, 0);
        if (*end || v < 1 || v > 0xFFFFFFFFul) {
            snprintf(r, n, "ERR SPEC_NSPEC must be 1-4294967295");
            return 0;
        }
        g_cfg.spec_nspec = (uint32_t)v;
    } else {
        return 1;
    }
    if (!spec_present()) {
        snprintf(r, n, "ERR no spectrometer in this bitstream");
        return 0;
    }
    spec_changed();
    cmd_spec(r, n);
    return 0;
}

static void cmd_config(char *r, size_t n)
{
    snprintf(r, n, "OK thresh=%u,%u,%u,%u,%u,%u,%u,%u mode=%s n=%d window=%d mask=0x%02X veto=%s "
             "len=%d armed=%d spec_enable=%d spec_input=%d spec_subband=%d spec_nspec=%u",
             g_cfg.thresh[0], g_cfg.thresh[1], g_cfg.thresh[2], g_cfg.thresh[3],
             g_cfg.thresh[4], g_cfg.thresh[5], g_cfg.thresh[6], g_cfg.thresh[7],
             g_cfg.mode_anti ? "ANTI" : "COINC", g_cfg.coinc_n, g_cfg.window,
             g_cfg.ch_mask, veto_str(), g_cfg.cap_len, g_cfg.armed,
             g_cfg.spec_enable, g_cfg.spec_input, g_cfg.spec_subband, g_cfg.spec_nspec);
}

static void cmd_rates(char *r, size_t n)
{
    uint32_t hits[LUNA_NCH] = { 0 };
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    double dt = (t.tv_sec - g_last_hits_t.tv_sec) + (t.tv_nsec - g_last_hits_t.tv_nsec) * 1e-9;
    if (!g_sim)
        pl_hit_counts(&g_pl, hits);
    size_t k = (size_t)snprintf(r, n, "OK interval=%.3f rates=", dt);
    for (int i = 0; i < LUNA_NCH && k < n; i++) {
        double rate = dt > 0 ? (uint32_t)(hits[i] - g_last_hits[i]) / dt : 0;
        k += (size_t)snprintf(r + k, n - k, "%s%.1f", i ? "," : "", rate);
        g_last_hits[i] = hits[i];
    }
    g_last_hits_t = t;
}

static void cmd_peaks(char *r, size_t n)
{
    uint16_t pk[LUNA_NCH] = { 0 };
    if (!g_sim)
        pl_peaks(&g_pl, pk);
    snprintf(r, n, "OK peaks=%u,%u,%u,%u,%u,%u,%u,%u",
             pk[0], pk[1], pk[2], pk[3], pk[4], pk[5], pk[6], pk[7]);
}

static void ctrl_handler(const char *line, char *r, size_t n)
{
    char w1[32] = "", w2[32] = "", w3[32] = "", w4[32] = "";
    int nw = sscanf(line, "%31s %31s %31s %31s", w1, w2, w3, w4);
    char *end;
    LOGD("ctrl: %s", line);

    if (!strcasecmp(w1, "HELP")) {
        snprintf(r, n, "%s", help_text);
    } else if (!strcasecmp(w1, "STATUS")) {
        cmd_status(r, n);
    } else if (!strcasecmp(w1, "GET") && nw >= 2) {
        if (!strcasecmp(w2, "CONFIG"))     cmd_config(r, n);
        else if (!strcasecmp(w2, "RATES")) cmd_rates(r, n);
        else if (!strcasecmp(w2, "PEAKS")) cmd_peaks(r, n);
        else if (!strcasecmp(w2, "SPEC"))  cmd_spec(r, n);
        else snprintf(r, n, "ERR unknown GET %s", w2);
    } else if (!strcasecmp(w1, "SPEC") && nw >= 2) {
        if (!spec_present()) {
            snprintf(r, n, "ERR no spectrometer in this bitstream");
        } else if (!strcasecmp(w2, "ON") || !strcasecmp(w2, "OFF")) {
            int on = !strcasecmp(w2, "ON");
            if (on != g_cfg.spec_enable) {
                g_cfg.spec_enable = on;
                spec_changed();
            }
            cmd_spec(r, n);
        } else if (!strcasecmp(w2, "RESTART")) {
            if (!g_sim)
                spec_restart(&g_pl);
            else
                spec_changed();
            cmd_spec(r, n);
        } else {
            snprintf(r, n, "ERR usage: SPEC ON|OFF|RESTART");
        }
    } else if (!strcasecmp(w1, "SET") && nw >= 3 && set_spec(w2, w3, r, n) == 0) {
        /* handled */
    } else if (!strcasecmp(w1, "SET") && nw >= 3) {
        if (!strcasecmp(w2, "THRESH")) {
            long v = strtol(w4, &end, 0);
            if (nw < 4 || *end || v < 0 || v > 32767) {
                snprintf(r, n, "ERR usage: SET THRESH <ch|ALL> <0-32767>");
                return;
            }
            if (!strcasecmp(w3, "ALL")) {
                for (int i = 0; i < LUNA_NCH; i++)
                    g_cfg.thresh[i] = (uint16_t)v;
            } else {
                long ch = strtol(w3, &end, 0);
                if (*end || ch < 0 || ch >= LUNA_NCH) {
                    snprintf(r, n, "ERR channel must be 0-7 or ALL");
                    return;
                }
                g_cfg.thresh[ch] = (uint16_t)v;
            }
        } else if (!strcasecmp(w2, "MODE")) {
            if (!strcasecmp(w3, "COINC"))     g_cfg.mode_anti = 0;
            else if (!strcasecmp(w3, "ANTI")) g_cfg.mode_anti = 1;
            else { snprintf(r, n, "ERR mode must be COINC or ANTI"); return; }
        } else if (!strcasecmp(w2, "VETO")) {
            /* anti-coincidence only: the channel blocks but never triggers */
            long v = strtol(w3, &end, 0);
            if (!veto_present()) {
                snprintf(r, n, "ERR this bitstream has no VETO register (trigger core v2.1+)");
                return;
            }
            if (!strcasecmp(w3, "OFF")) {
                g_cfg.veto_en = 0;
            } else if (*end || v < 0 || v >= LUNA_NCH) {
                snprintf(r, n, "ERR VETO must be 0-7 or OFF");
                return;
            } else {
                g_cfg.veto_en = 1;
                g_cfg.veto_ch = (int)v;
            }
        } else {
            long v = strtol(w3, &end, 0);
            if (*end) { snprintf(r, n, "ERR bad number '%s'", w3); return; }
            if (!strcasecmp(w2, "N")) {
                if (v < 1 || v > 8) { snprintf(r, n, "ERR N must be 1-8"); return; }
                g_cfg.coinc_n = (int)v;
            } else if (!strcasecmp(w2, "WINDOW")) {
                if (v < 1 || v > 255) { snprintf(r, n, "ERR WINDOW must be 1-255"); return; }
                g_cfg.window = (int)v;
            } else if (!strcasecmp(w2, "MASK")) {
                if (v < 0 || v > 255) { snprintf(r, n, "ERR MASK must be 0x00-0xFF"); return; }
                g_cfg.ch_mask = (uint32_t)v;
            } else if (!strcasecmp(w2, "LEN")) {
                if (v < LUNA_MIN_SAMPLES || v > LUNA_MAX_SAMPLES || (v % 32)) {
                    snprintf(r, n, "ERR LEN must be 4096-16384, multiple of 32");
                    return;
                }
                g_cfg.cap_len = (int)v;
            } else {
                snprintf(r, n, "ERR unknown SET %s", w2);
                return;
            }
        }
        apply_config();
        cmd_config(r, n);
    } else if (!strcasecmp(w1, "ARM") || !strcasecmp(w1, "DISARM")) {
        g_cfg.armed = !strcasecmp(w1, "ARM");
        apply_config();
        snprintf(r, n, "OK armed=%d", g_cfg.armed);
    } else if (!strcasecmp(w1, "SOFTTRIG")) {
        if (!g_sim)
            pl_soft_trigger(&g_pl);
        else
            sim_tick(1);
        snprintf(r, n, "OK");
    } else if (!strcasecmp(w1, "RESYNC")) {
        if (g_sim || rf_mts() == 0)
            snprintf(r, n, "OK mts done");
        else
            snprintf(r, n, "ERR mts failed (see server log)");
    } else if (!strcasecmp(w1, "SAVE")) {
        if (config_save(&g_cfg, g_cfg_path) == 0)
            snprintf(r, n, "OK saved %s", g_cfg_path);
        else
            snprintf(r, n, "ERR cannot write %s", g_cfg_path);
    } else {
        snprintf(r, n, "ERR unknown command '%s' (try HELP)", w1);
    }
}

/* ------------------------------------------------------------------------ */
/* events                                                                   */
/* ------------------------------------------------------------------------ */

static void publish(struct net_event *e, size_t len)
{
    e->len = len;
    struct luna_frame_hdr *f = (struct luna_frame_hdr *)e->hdr;
    f->magic = LUNA_FRAME_MAGIC;
    f->version = LUNA_PROTO_VERSION;
    f->hdr_bytes = sizeof *f;
    f->frame_bytes = (uint32_t)(sizeof *f + len);
    f->flags = g_sim ? 1u : 0u;
    f->host_time_ns = realtime_ns();
    f->sample_rate_hz = FS_HZ;
    memcpy(f->thresh, g_cfg.thresh, sizeof f->thresh);
    g_events++;
    net_publish(g_net, NET_STREAM_EVENTS, e);
    net_event_put(e);
}

/* complete the spectrum frame header (FPGA fields already set) and send it */
static void publish_spec(struct net_event *e)
{
    struct luna_spec_hdr *h = (struct luna_spec_hdr *)e->hdr;
    e->len = SPEC_PAYLOAD;
    h->magic = LUNA_SPEC_MAGIC;
    h->version = LUNA_SPEC_VERSION;
    h->hdr_bytes = sizeof *h;
    h->frame_bytes = (uint32_t)(sizeof *h + SPEC_PAYLOAD);
    if (g_sim)
        h->flags |= LUNA_SPEC_F_SIM;
    h->host_time_ns = realtime_ns();
    h->sample_rate_hz = FS_HZ;
    h->n_channels = LUNA_SPEC_NCHAN;
    g_spectra++;
    LOGD("spectrum seq %u input %u subband %u n %u%s", h->seq, h->adc_input, h->subband,
         h->n_spectra,
         (h->flags & LUNA_SPEC_F_FIRST) ? " (first after restart)" : "");
    net_publish(g_net, NET_STREAM_SPEC, e);
    net_event_put(e);
}

/* read out every integration waiting in the spectrometer banks */
static void service_spec(void)
{
    for (int i = 0; i < 2; i++) {
        struct net_event *e = net_event_alloc(SPEC_PAYLOAD);
        if (!e) {
            LOGE("out of memory");
            return;
        }
        struct luna_spec_hdr *h = (struct luna_spec_hdr *)e->hdr;
        if (spec_read(&g_pl, h, (uint64_t *)e->data) <= 0) {
            net_event_put(e);
            return;
        }
        publish_spec(e);
    }
}

static void sim_spec_tick(void)
{
    struct net_event *e = net_event_alloc(SPEC_PAYLOAD);
    if (!e)
        return;
    struct luna_spec_hdr *h = (struct luna_spec_hdr *)e->hdr;
    h->seq = g_sim_spec_seq++;
    h->n_spectra = g_cfg.spec_nspec;
    h->subband = (uint8_t)g_cfg.spec_subband;
    h->adc_input = (uint8_t)g_cfg.spec_input;
    h->flags = g_sim_spec_first ? LUNA_SPEC_F_FIRST : 0;
    h->end_sample = (uint64_t)(now_s() * FS_HZ);
    h->restarts = g_sim_spec_restarts;
    g_sim_spec_first = 0;
    sim_make_spectrum(&g_cfg, (uint64_t *)e->data);
    publish_spec(e);
}

/* read out every event waiting in the capture banks */
static void service_trigger(void)
{
    for (int i = 0; i < 16; i++) {
        struct net_event *e = net_event_alloc(EVENT_MAX);
        if (!e) {
            LOGE("out of memory");
            return;
        }
        long len = pl_read_event(&g_pl, e->data, EVENT_MAX);
        if (len <= 0) {
            net_event_put(e);
            return;
        }
        const struct luna_event_hdr *h = (const void *)e->data;
        LOGD("event seq %u trig %llu mask 0x%02x src %u", h->seq,
                (unsigned long long)h->trig_sample, h->trig_mask, h->trig_src);
        publish(e, (size_t)len);
    }
}

static void sim_tick(int force)
{
    if (!g_cfg.armed && !force)
        return;
    struct net_event *e = net_event_alloc(EVENT_MAX);
    if (!e)
        return;
    uint64_t ts = (uint64_t)(now_s() * FS_HZ);
    size_t len = sim_make_event(&g_cfg, e->data, EVENT_MAX, g_sim_seq++, ts);
    publish(e, len);
}

/* ------------------------------------------------------------------------ */


static int hw_bringup(int program_clocks, int i2c_bus)
{
    if (program_clocks) {
        LOGI("programming RF clocks");
        if (clocks_program(i2c_bus) < 0)
            LOGW("clock programming failed - continuing with existing clocks");
    }
    if (pl_open(&g_pl) < 0)
        return -1;
    if (pl_mmcm_start(&g_pl, 2000) < 0)
        return -1;
    if (rf_init() < 0)
        return -1;
    if (rf_startup() < 0)
        LOGW("RFDC start-up incomplete");
    if (rf_mts() < 0)
        LOGW("continuing WITHOUT multi-tile sync - channels on different tiles "
                 "may be misaligned (use RESYNC)");
    if (pl_core_init(&g_pl) < 0)
        return -1;
    if (spec_init(&g_pl) < 0)
        LOGW("spectrometer not available");
    apply_config();
    if (hw_irq_enable(&g_pl.trig) < 0)
        LOGW("no trigger interrupt (UIO) - polling the status register");
    if (g_pl.has_spec && hw_irq_enable(&g_pl.spec) < 0)
        LOGW("no spectrometer interrupt (UIO) - polling its status register");
    return 0;
}

int main(int argc, char **argv)
{
    int data_port = LUNA_DATA_PORT, ctrl_port = LUNA_CTRL_PORT, spec_port = LUNA_SPEC_PORT;
    int program_clocks = 1, i2c_bus = -1, opt;

    while ((opt = getopt(argc, argv, "c:d:p:S:b:ns:vh")) != -1) {
        switch (opt) {
        case 'c': g_cfg_path = optarg; break;
        case 'd': data_port = atoi(optarg); break;
        case 'p': ctrl_port = atoi(optarg); break;
        case 'S': spec_port = atoi(optarg); break;
        case 'b': i2c_bus = atoi(optarg); break;
        case 'n': program_clocks = 0; break;
        case 's': g_sim = 1; g_sim_rate = atof(optarg); break;
        case 'v': g_verbose = 1; break;
        default:
            fprintf(stderr, "usage: %s [-c conf] [-d data_port] [-p ctrl_port] "
                            "[-S spec_port] [-b i2c_bus] [-n] [-s sim_rate_hz] [-v]\n",
                    argv[0]);
            return opt == 'h' ? 0 : 1;
        }
    }

    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    config_defaults(&g_cfg);
    config_load(&g_cfg, g_cfg_path);
    config_sanitize(&g_cfg);
    clock_gettime(CLOCK_MONOTONIC, &g_last_hits_t);

    const int data_ports[2] = { data_port, spec_port };
    g_net = net_create(data_ports, 2, ctrl_port, ctrl_handler);
    if (!g_net)
        return 1;

    int ev_fd = -1;       /* trigger UIO fd, or timerfd in simulation */
    if (g_sim) {
        LOGI("SIMULATION mode: %.2f events/s, spectra every %.3f s",
             g_sim_rate, spec_seconds(g_cfg.spec_nspec));
        ev_fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
        double period = g_sim_rate > 0 ? 1.0 / g_sim_rate : 1.0;
        struct itimerspec its;
        its.it_interval.tv_sec = (time_t)period;
        its.it_interval.tv_nsec = (long)((period - floor(period)) * 1e9);
        its.it_value = its.it_interval;
        timerfd_settime(ev_fd, 0, &its, NULL);
        g_spec_fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
        sim_spec_timer_update();
    } else {
        if (hw_bringup(program_clocks, i2c_bus) < 0) {
            LOGE("hardware bring-up failed");
            net_destroy(g_net);
            return 1;
        }
        ev_fd = g_pl.trig.fd;
        if (g_pl.has_spec)
            g_spec_fd = g_pl.spec.fd;
    }
    LOGI("lunaserver running");

    struct pollfd pfd[64];
    _Static_assert(1 + 2 * (1 + NET_MAX_CLIENTS) + NET_MAX_CLIENTS + 2 <= 64, "pollfd array");
    while (!g_stop) {
        int k = 0;
        pfd[k++] = (struct pollfd){ .fd = ev_fd, .events = POLLIN };
        pfd[k++] = (struct pollfd){ .fd = g_spec_fd, .events = POLLIN };   /* -1: ignored */
        int nn = net_fill_pollfds(g_net, pfd + k, (int)(sizeof pfd / sizeof pfd[0]) - k);
        int rc = poll(pfd, (nfds_t)(k + nn), ev_fd >= 0 ? 200 : 20);
        if (rc < 0) {
            if (errno == EINTR)
                continue;
            LOGE("poll: %s", strerror(errno));
            break;
        }
        if (g_sim) {
            uint64_t exp;
            if ((pfd[0].revents & POLLIN) && read(ev_fd, &exp, sizeof exp) == sizeof exp)
                sim_tick(0);
            if ((pfd[1].revents & POLLIN) && read(g_spec_fd, &exp, sizeof exp) == sizeof exp)
                sim_spec_tick();
        } else {
            if (ev_fd < 0 || (pfd[0].revents & POLLIN)) {
                if (ev_fd >= 0) {
                    uint32_t cnt;
                    if (read(ev_fd, &cnt, sizeof cnt) != sizeof cnt)
                        LOGW("uio read failed");
                }
                service_trigger();
                if (ev_fd >= 0)
                    hw_irq_enable(&g_pl.trig);    /* level IRQ: re-enable */
            }
            if (g_pl.has_spec && (g_spec_fd < 0 || (pfd[1].revents & POLLIN))) {
                if (g_spec_fd >= 0) {
                    uint32_t cnt;
                    if (read(g_spec_fd, &cnt, sizeof cnt) != sizeof cnt)
                        LOGW("uio read failed (spectrometer)");
                }
                service_spec();
                if (g_spec_fd >= 0)
                    hw_irq_enable(&g_pl.spec);
            }
        }
        net_handle(g_net, pfd + k, nn);
    }

    LOGI("shutting down");
    if (!g_sim) {
        pl_arm(&g_pl, 0);
        rf_close();
        pl_close(&g_pl);
    } else if (g_spec_fd >= 0) {
        close(g_spec_fd);
    }
    net_destroy(g_net);
    return 0;
}
