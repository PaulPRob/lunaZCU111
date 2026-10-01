/* net.h - data (event push) and control (text command) TCP servers */
#ifndef NET_H
#define NET_H

#include <poll.h>
#include <stddef.h>
#include <stdint.h>

#include "protocol.h"

#define NET_MAX_CLIENTS   16
#define NET_MAX_QUEUE     64          /* events queued per data client */

/* reference counted event payload (FPGA header + samples) */
struct net_event {
    int      refs;
    size_t   len;
    struct luna_frame_hdr fhdr;       /* template (dropped filled per client) */
    uint8_t  data[];
};

struct net_event *net_event_alloc(size_t payload_len);
void net_event_put(struct net_event *e);

/* callback for one control line; writes a reply (without newline) */
typedef void (*net_ctrl_fn)(const char *line, char *reply, size_t reply_len);

struct net;
struct net *net_create(int data_port, int ctrl_port, net_ctrl_fn fn);
void net_destroy(struct net *n);

/* poll integration: add our fds to 'pfd' (returns count), then handle */
int  net_fill_pollfds(struct net *n, struct pollfd *pfd, int max);
void net_handle(struct net *n, const struct pollfd *pfd, int count);

/* queue an event to every data client (takes one reference per client) */
void net_publish(struct net *n, struct net_event *e);

int  net_data_clients(const struct net *n);
uint64_t net_frames_sent(const struct net *n);
uint64_t net_frames_dropped(const struct net *n);

#endif
