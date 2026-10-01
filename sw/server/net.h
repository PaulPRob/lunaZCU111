/* net.h - data (event / spectrum push) and control (text command) TCP servers */
#ifndef NET_H
#define NET_H

#include <poll.h>
#include <stddef.h>
#include <stdint.h>

#include "protocol.h"

#define NET_MAX_CLIENTS   16
#define NET_MAX_QUEUE     64          /* frames queued per data client */
#define NET_MAX_STREAMS   2           /* data ports: events, spectra */

/* data streams (index into the data_ports given to net_create) */
#define NET_STREAM_EVENTS 0
#define NET_STREAM_SPEC   1

/*
 * reference counted frame payload.  'hdr' is the 64-byte frame header
 * (struct luna_frame_hdr or struct luna_spec_hdr); its 32-bit 'dropped'
 * field at LUNA_HDR_DROPPED_OFF is filled in per client.
 */
struct net_event {
    int      refs;
    size_t   len;
    uint8_t  hdr[LUNA_HDR_BYTES] __attribute__((aligned(8)));
    uint8_t  data[];
};

struct net_event *net_event_alloc(size_t payload_len);
void net_event_put(struct net_event *e);

/* callback for one control line; writes a reply (without newline) */
typedef void (*net_ctrl_fn)(const char *line, char *reply, size_t reply_len);

struct net;
/* listen on 'ndata' data ports (stream i on data_ports[i]) and the control port */
struct net *net_create(const int *data_ports, int ndata, int ctrl_port, net_ctrl_fn fn);
void net_destroy(struct net *n);

/* poll integration: add our fds to 'pfd' (returns count), then handle */
int  net_max_pollfds(void);
int  net_fill_pollfds(struct net *n, struct pollfd *pfd, int max);
void net_handle(struct net *n, const struct pollfd *pfd, int count);

/* queue a frame to every client of 'stream' (takes one reference per client) */
void net_publish(struct net *n, int stream, struct net_event *e);

int  net_data_clients(const struct net *n, int stream);
uint64_t net_frames_sent(const struct net *n, int stream);
uint64_t net_frames_dropped(const struct net *n, int stream);

#endif
