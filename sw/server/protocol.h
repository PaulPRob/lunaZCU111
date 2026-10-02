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
 * SPECTRUM port (TCP 5002): one frame per integration of the spectrometer
 *     struct luna_spec_hdr       64 bytes
 *     uint64_t power[4096]       accumulated power per fine channel, FFT
 *                                order: channel k is k*30 kHz from the
 *                                subband centre for k < 2048, (k-4096)*30 kHz
 *                                for k >= 2048
 *
 * All multi-byte fields are little endian.
 */
#ifndef LUNA_PROTOCOL_H
#define LUNA_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#define LUNA_DATA_PORT      5000
#define LUNA_CTRL_PORT      5001
#define LUNA_SPEC_PORT      5002
#define LUNA_NCH            8
#define LUNA_MAX_SAMPLES    16384
#define LUNA_MIN_SAMPLES    4096

#define LUNA_FRAME_MAGIC    0x5456454Cu   /* "LEVT" : bytes 'L','E','V','T' */
#define LUNA_EVENT_MAGIC    0x414E554Cu   /* "LUNA" */
#define LUNA_SPEC_MAGIC     0x4350534Cu   /* "LSPC" */
#define LUNA_PROTO_VERSION  1
#define LUNA_SPEC_VERSION   1

/* every frame header is 64 bytes with the per-client 'dropped' count at 48 */
#define LUNA_HDR_BYTES       64
#define LUNA_HDR_DROPPED_OFF 48

/* spectrometer (ADC channel 0) */
#define LUNA_SPEC_NCHAN     4096          /* fine channels per subband       */
#define LUNA_SPEC_NSUB      17            /* coarse channels 0..16           */
#define LUNA_SPEC_FFT_CLK   122.88e6      /* complex samples/s per subband   */

/* trigger source codes (luna_event_hdr.trig_src) */
#define LUNA_SRC_COINC 1
#define LUNA_SRC_ANTI  2
#define LUNA_SRC_SOFT  3

/* luna_spec_hdr.flags */
#define LUNA_SPEC_F_SIM    (1u << 0)      /* simulated data                  */
#define LUNA_SPEC_F_FIRST  (1u << 1)      /* first integration after a
                                             restart (enable, SUBBAND or
                                             integration time change); its
                                             data are all from after it     */

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

struct luna_spec_hdr {
    uint32_t magic;           /* LUNA_SPEC_MAGIC                             */
    uint16_t version;         /* LUNA_SPEC_VERSION                           */
    uint16_t hdr_bytes;       /* 64                                          */
    uint32_t frame_bytes;     /* 64 + 8 * n_channels                         */
    uint32_t flags;           /* LUNA_SPEC_F_*                               */
    uint64_t host_time_ns;    /* CLOCK_REALTIME when the spectrum was read   */
    uint64_t end_sample;      /* ADC sample counter (trigger time base) when
                                 the integration ended                       */
    double   sample_rate_hz;  /* ADC rate, 3.93216e9                         */
    uint32_t seq;             /* integration sequence number (FPGA)          */
    uint32_t n_spectra;       /* spectra accumulated (ACC_LEN + 1)           */
    uint32_t dropped;         /* frames dropped for THIS client so far       */
    uint32_t lost;            /* integrations lost in the FPGA (banks full)  */
    uint16_t n_channels;      /* 4096                                        */
    uint8_t  subband;         /* coarse channel 0..16                        */
    uint8_t  reserved0;
    uint32_t restarts;        /* integration restarts so far                 */
} __attribute__((packed));

_Static_assert(sizeof(struct luna_frame_hdr) == LUNA_HDR_BYTES, "frame header size");
_Static_assert(sizeof(struct luna_event_hdr) == 64, "event header size");
_Static_assert(sizeof(struct luna_spec_hdr) == LUNA_HDR_BYTES, "spectrum header size");
_Static_assert(offsetof(struct luna_frame_hdr, dropped) == LUNA_HDR_DROPPED_OFF, "dropped");
_Static_assert(offsetof(struct luna_spec_hdr, dropped) == LUNA_HDR_DROPPED_OFF, "dropped");

#endif
