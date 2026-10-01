/*
 * net.c - TCP servers
 *
 * Each data stream (events on 5000, spectra on 5002) has its own listening
 * port and clients.  A client receives every frame of its stream (64-byte
 * frame header + payload).  Sending is non-blocking with a bounded
 * per-client queue: a client that cannot keep up loses frames (counted in
 * its frame header 'dropped'), but it never slows down the capture.
 */
#include "net.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

#include "log.h"

struct qitem {
    struct net_event *e;
    uint8_t           hdr[LUNA_HDR_BYTES];
    size_t            off;          /* bytes of (hdr + data) already sent */
};

struct dclient {
    int          fd;
    char         peer[48];
    struct qitem q[NET_MAX_QUEUE];
    int          qh, qn;
    uint32_t     dropped;
};

struct cclient {
    int    fd;
    char   peer[48];
    char   buf[1024];
    size_t len;
};

struct dstream {
    int            lfd;
    int            port;
    struct dclient d[NET_MAX_CLIENTS];
    int            nd;
    uint64_t       sent, dropped;
};

struct net {
    struct dstream s[NET_MAX_STREAMS];
    int            ns;
    int            cl;
    struct cclient c[NET_MAX_CLIENTS];
    int            nc;
    net_ctrl_fn    fn;
};

struct net_event *net_event_alloc(size_t payload_len)
{
    struct net_event *e = malloc(sizeof *e + payload_len);
    if (!e)
        return NULL;
    memset(e, 0, sizeof *e);
    e->refs = 1;
    e->len = payload_len;
    return e;
}

void net_event_put(struct net_event *e)
{
    if (e && --e->refs == 0)
        free(e);
}

static int listen_on(int port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = { .sin_family = AF_INET, .sin_port = htons((uint16_t)port),
                             .sin_addr.s_addr = htonl(INADDR_ANY) };
    if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0 || listen(fd, 8) < 0) {
        LOGE("net: cannot listen on port %d: %s", port, strerror(errno));
        close(fd);
        return -1;
    }
    fcntl(fd, F_SETFL, O_NONBLOCK);
    return fd;
}

struct net *net_create(const int *data_ports, int ndata, int ctrl_port, net_ctrl_fn fn)
{
    if (ndata < 1 || ndata > NET_MAX_STREAMS)
        return NULL;
    struct net *n = calloc(1, sizeof *n);
    if (!n)
        return NULL;
    n->fn = fn;
    n->ns = ndata;
    for (int i = 0; i < NET_MAX_STREAMS; i++)
        n->s[i].lfd = -1;
    int ok = 1;
    for (int i = 0; i < ndata; i++) {
        n->s[i].port = data_ports[i];
        n->s[i].lfd = listen_on(data_ports[i]);
        ok &= n->s[i].lfd >= 0;
    }
    n->cl = listen_on(ctrl_port);
    if (!ok || n->cl < 0) {
        net_destroy(n);
        return NULL;
    }
    for (int i = 0; i < ndata; i++)
        LOGI("net: data stream %d on port %d", i, data_ports[i]);
    LOGI("net: control port %d", ctrl_port);
    return n;
}

static void dclient_close(struct dclient *c)
{
    for (int i = 0; i < c->qn; i++)
        net_event_put(c->q[(c->qh + i) % NET_MAX_QUEUE].e);
    c->qn = 0;
    if (c->fd >= 0) {
        LOGI("net: data client %s disconnected (%u frames dropped)", c->peer, c->dropped);
        close(c->fd);
    }
    c->fd = -1;
}

void net_destroy(struct net *n)
{
    if (!n)
        return;
    for (int s = 0; s < n->ns; s++) {
        struct dstream *st = &n->s[s];
        for (int i = 0; i < st->nd; i++)
            dclient_close(&st->d[i]);
        if (st->lfd >= 0)
            close(st->lfd);
    }
    for (int i = 0; i < n->nc; i++)
        if (n->c[i].fd >= 0)
            close(n->c[i].fd);
    if (n->cl >= 0)
        close(n->cl);
    free(n);
}

static int accept_one(int lfd, char *peer, size_t plen)
{
    struct sockaddr_in a;
    socklen_t al = sizeof a;
    int fd = accept(lfd, (struct sockaddr *)&a, &al);
    if (fd < 0)
        return -1;
    fcntl(fd, F_SETFL, O_NONBLOCK);
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    snprintf(peer, plen, "%s:%u", inet_ntoa(a.sin_addr), ntohs(a.sin_port));
    return fd;
}

int net_max_pollfds(void)
{
    return 1 + NET_MAX_STREAMS * (1 + NET_MAX_CLIENTS) + NET_MAX_CLIENTS;
}

/* pollfd layout: [ctrl listen] [stream listen] x ns [stream clients] [ctrl clients] */
int net_fill_pollfds(struct net *n, struct pollfd *pfd, int max)
{
    int k = 0, need = 1 + n->ns + n->nc;
    for (int s = 0; s < n->ns; s++)
        need += n->s[s].nd;
    if (max < need)
        return 0;
    pfd[k++] = (struct pollfd){ .fd = n->cl, .events = POLLIN };
    for (int s = 0; s < n->ns; s++)
        pfd[k++] = (struct pollfd){ .fd = n->s[s].lfd, .events = POLLIN };
    for (int s = 0; s < n->ns; s++)
        for (int i = 0; i < n->s[s].nd; i++) {
            struct dclient *c = &n->s[s].d[i];
            pfd[k++] = (struct pollfd){ .fd = c->fd,
                                        .events = (short)(POLLIN | (c->qn ? POLLOUT : 0)) };
        }
    for (int i = 0; i < n->nc; i++)
        pfd[k++] = (struct pollfd){ .fd = n->c[i].fd, .events = POLLIN };
    return k;
}

/* send as much of the queue as the socket accepts */
static int dclient_flush(struct dstream *st, struct dclient *c)
{
    while (c->qn) {
        struct qitem *it = &c->q[c->qh];
        size_t hl = sizeof it->hdr;
        size_t total = hl + it->e->len;
        struct iovec iov[2];
        int niov = 0;
        if (it->off < hl) {
            iov[niov].iov_base = it->hdr + it->off;
            iov[niov++].iov_len = hl - it->off;
            iov[niov].iov_base = it->e->data;
            iov[niov++].iov_len = it->e->len;
        } else {
            iov[niov].iov_base = it->e->data + (it->off - hl);
            iov[niov++].iov_len = total - it->off;
        }
        ssize_t w = writev(c->fd, iov, niov);
        if (w < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                return 0;
            return -1;
        }
        it->off += (size_t)w;
        if (it->off < total)
            return 0;
        net_event_put(it->e);
        c->qh = (c->qh + 1) % NET_MAX_QUEUE;
        c->qn--;
        st->sent++;
    }
    return 0;
}

static void cclient_input(struct net *n, struct cclient *c)
{
    ssize_t r = read(c->fd, c->buf + c->len, sizeof c->buf - 1 - c->len);
    if (r <= 0) {
        if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            return;
        LOGI("net: control client %s disconnected", c->peer);
        close(c->fd);
        c->fd = -1;
        return;
    }
    c->len += (size_t)r;
    c->buf[c->len] = 0;
    char *nl;
    while ((nl = strchr(c->buf, '\n')) != NULL) {
        *nl = 0;
        if (nl > c->buf && nl[-1] == '\r')
            nl[-1] = 0;
        char reply[4096];
        reply[0] = 0;
        if (c->buf[0])
            n->fn(c->buf, reply, sizeof reply - 2);
        size_t rl = strlen(reply);
        if (rl) {
            reply[rl++] = '\n';
            if (send(c->fd, reply, rl, MSG_NOSIGNAL) < 0) {
                close(c->fd);
                c->fd = -1;
                return;
            }
        }
        size_t used = (size_t)(nl + 1 - c->buf);
        memmove(c->buf, nl + 1, c->len - used + 1);
        c->len -= used;
    }
    if (c->len >= sizeof c->buf - 1) {  /* overlong line */
        c->len = 0;
        c->buf[0] = 0;
    }
}

void net_handle(struct net *n, const struct pollfd *pfd, int count)
{
    if (count < 1 + n->ns)
        return;
    int k = 1 + n->ns;
    for (int s = 0; s < n->ns; s++) {
        struct dstream *st = &n->s[s];
        for (int i = 0; i < st->nd && k < count; i++, k++) {
            struct dclient *c = &st->d[i];
            if (pfd[k].revents & (POLLERR | POLLHUP)) {
                dclient_close(c);
                continue;
            }
            if (pfd[k].revents & POLLIN) {       /* clients should not send */
                char tmp[256];
                ssize_t r = read(c->fd, tmp, sizeof tmp);
                if (r == 0 || (r < 0 && errno != EAGAIN)) {
                    dclient_close(c);
                    continue;
                }
            }
            if ((pfd[k].revents & POLLOUT) && dclient_flush(st, c) < 0)
                dclient_close(c);
        }
    }
    for (int i = 0; i < n->nc && k < count; i++, k++)
        if (pfd[k].revents & (POLLIN | POLLHUP | POLLERR))
            cclient_input(n, &n->c[i]);

    /* compact closed clients */
    int j;
    for (int s = 0; s < n->ns; s++) {
        struct dstream *st = &n->s[s];
        j = 0;
        for (int i = 0; i < st->nd; i++)
            if (st->d[i].fd >= 0)
                st->d[j++] = st->d[i];
        st->nd = j;
    }
    j = 0;
    for (int i = 0; i < n->nc; i++)
        if (n->c[i].fd >= 0)
            n->c[j++] = n->c[i];
    n->nc = j;

    /* new connections */
    for (int s = 0; s < n->ns; s++) {
        struct dstream *st = &n->s[s];
        if (!(pfd[1 + s].revents & POLLIN))
            continue;
        char peer[48];
        int fd = accept_one(st->lfd, peer, sizeof peer);
        if (fd >= 0) {
            if (st->nd >= NET_MAX_CLIENTS) {
                close(fd);
            } else {
                int sz = 8 << 20;
                setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sz, sizeof sz);
                struct dclient *c = &st->d[st->nd++];
                memset(c, 0, sizeof *c);
                c->fd = fd;
                snprintf(c->peer, sizeof c->peer, "%s", peer);
                LOGI("net: data client %s connected to port %d", peer, st->port);
            }
        }
    }
    if (pfd[0].revents & POLLIN) {
        char peer[48];
        int fd = accept_one(n->cl, peer, sizeof peer);
        if (fd >= 0) {
            if (n->nc >= NET_MAX_CLIENTS) {
                close(fd);
            } else {
                struct cclient *c = &n->c[n->nc++];
                memset(c, 0, sizeof *c);
                c->fd = fd;
                snprintf(c->peer, sizeof c->peer, "%s", peer);
                LOGI("net: control client %s connected", peer);
            }
        }
    }
}

void net_publish(struct net *n, int stream, struct net_event *e)
{
    if (stream < 0 || stream >= n->ns)
        return;
    struct dstream *st = &n->s[stream];
    for (int i = 0; i < st->nd; i++) {
        struct dclient *c = &st->d[i];
        if (c->fd < 0)
            continue;
        if (c->qn >= NET_MAX_QUEUE) {
            c->dropped++;
            st->dropped++;
            continue;
        }
        struct qitem *it = &c->q[(c->qh + c->qn) % NET_MAX_QUEUE];
        it->e = e;
        memcpy(it->hdr, e->hdr, sizeof it->hdr);
        memcpy(it->hdr + LUNA_HDR_DROPPED_OFF, &c->dropped, sizeof c->dropped);
        it->off = 0;
        e->refs++;
        c->qn++;
        if (c->qn == 1 && dclient_flush(st, c) < 0)   /* try immediately */
            dclient_close(c);
    }
}

static const struct dstream *stream_of(const struct net *n, int s)
{
    return (s >= 0 && s < n->ns) ? &n->s[s] : NULL;
}

int net_data_clients(const struct net *n, int s)
{
    const struct dstream *st = stream_of(n, s);
    return st ? st->nd : 0;
}

uint64_t net_frames_sent(const struct net *n, int s)
{
    const struct dstream *st = stream_of(n, s);
    return st ? st->sent : 0;
}

uint64_t net_frames_dropped(const struct net *n, int s)
{
    const struct dstream *st = stream_of(n, s);
    return st ? st->dropped : 0;
}
