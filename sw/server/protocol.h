/*
 * protocol.h - network protocol of lunaserver (see docs/protocol.md)
 *
 * DATA port (TCP 5000): the server pushes one frame per captured event
 *     struct luna_frame_hdr      64 bytes  (added by the server)
 *     struct luna_event_hdr      64 bytes  (produced by the FPGA)
 *     int16_t samples[8][n]      channel-major, little endian
 *
 * CONTROL port (TCP 5001): line based ASCII commands, one reply line each
 *     "OK ..." or "ERR ...".  See HELP / docs/protocol.md.
 *
 * All multi-byte fields are little endian.
 */
#ifndef LUNA_PROTOCOL_H
#define LUNA_PROTOCOL_H

#include <stdint.h>

#define LUNA_DATA_PORT      5000
#define LUNA_CTRL_PORT      5001
#define LUNA_NCH            8
#define LUNA_MAX_SAMPLES    16384
#define LUNA_MIN_SAMPLES    4096

#define LUNA_FRAME_MAGIC    0x5456454Cu   /* "LEVT" : bytes 'L','E','V','T' */
#define LUNA_EVENT_MAGIC    0x414E554Cu   /* "LUNA" */
#define LUNA_PROTO_VERSION  1

/* trigger source codes (luna_event_hdr.trig_src) */
#define LUNA_SRC_COINC 1
#define LUNA_SRC_ANTI  2
#define LUNA_SRC_SOFT  3

struct luna_frame_hdr {
    uint32_t magic;           /* LUNA_FRAME_MAGIC                            */
    uint16_t version;         /* LUNA_PROTO_VERSION                          */
    uint16_t hdr_bytes;       /* 64                                          */
    uint32_t frame_bytes;     /* whole frame incl. this header               */
    uint32_t flags;           /* bit0: simulated data                        */
    uint64_t host_time_ns;    /* CLOCK_REALTIME when the event was read out  */
    double   sample_rate_hz;  /* 3.93216e9                                   */
    uint16_t thresh[LUNA_NCH];/* thresholds in effect                        */
    uint32_t dropped;         /* frames dropped for THIS client so far       */
    uint32_t reserved[3];
} __attribute__((packed));

struct luna_event_hdr {       /* written by the FPGA (capture_ctrl.vhd)      */
    uint32_t magic;           /* LUNA_EVENT_MAGIC                            */
    uint16_t version;         /* 1                                           */
    uint16_t hdr_bytes;       /* 64                                          */
    uint32_t seq;             /* accepted-event sequence number              */
    uint32_t n_samples;       /* samples per channel (L)                     */
    uint64_t trig_sample;     /* absolute sample index of the trigger        */
    uint64_t start_sample;    /* absolute sample index of samples[ch][0]     */
    uint32_t trig_offset;     /* trig_sample - start_sample (L/2 .. L/2+15)  */
    uint8_t  trig_mask;       /* channels that took part                     */
    uint8_t  trig_src;        /* LUNA_SRC_*                                  */
    uint8_t  n_channels;      /* 8                                           */
    uint8_t  bank;            /* capture bank used                           */
    uint16_t window;          /* coincidence window (samples)                */
    uint8_t  coinc_n;         /* coincidence N                               */
    uint8_t  mode;            /* 0 coincidence, 1 anti-coincidence           */
    uint32_t lost;            /* triggers lost before this event             */
    uint32_t trig_count;      /* accepted triggers incl. this one            */
    uint32_t reserved[3];
} __attribute__((packed));

_Static_assert(sizeof(struct luna_frame_hdr) == 64, "frame header size");
_Static_assert(sizeof(struct luna_event_hdr) == 64, "event header size");

#endif
