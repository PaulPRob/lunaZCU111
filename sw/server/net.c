/*
 * net.c - TCP servers
 *
 * Data clients receive every event as one frame (64-byte frame header +
 * event).  Sending is non-blocking with a bounded per-client queue: a client
 * that cannot keep up loses frames (counted in its frame header 'dropped'),
 * but it never slows down the capture.
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
    struct net_event     *e;
    struct luna_frame_hdr hdr;
    size_t                off;      /* bytes of (hdr + data) already sent */
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

struct net {
    int            dl, cl;
    struct dclient d[NET_MAX_CLIENTS];
    int            nd;
    struct cclient c[NET_MAX_CLIENTS];
    int            nc;
    net_ctrl_fn    fn;
    uint64_t       sent, dropped;
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

struct net *net_create(int data_port, int ctrl_port, net_ctrl_fn fn)
{
    struct net *n = calloc(1, sizeof *n);
    if (!n)
        return NULL;
    n->fn = fn;
    n->dl = listen_on(data_port);
    n->cl = listen_on(ctrl_port);
    if (n->dl < 0 || n->cl < 0) {
        net_destroy(n);
        return NULL;
    }
    LOGI("net: data port %d, control port %d", data_port, ctrl_port);
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
    for (int i = 0; i < n->nd; i++)
        dclient_close(&n->d[i]);
    for (int i = 0; i < n->nc; i++)
        if (n->c[i].fd >= 0)
            close(n->c[i].fd);
    if (n->dl >= 0)
        close(n->dl);
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

int net_fill_pollfds(struct net *n, struct pollfd *pfd, int max)
{
    int k = 0;
    if (max < 2 + n->nd + n->nc)
        return 0;
    pfd[k++] = (struct pollfd){ .fd = n->dl, .events = POLLIN };
    pfd[k++] = (struct pollfd){ .fd = n->cl, .events = POLLIN };
    for (int i = 0; i < n->nd; i++)
        pfd[k++] = (struct pollfd){ .fd = n->d[i].fd,
                                    .events = (short)(POLLIN | (n->d[i].qn ? POLLOUT : 0)) };
    for (int i = 0; i < n->nc; i++)
        pfd[k++] = (struct pollfd){ .fd = n->c[i].fd, .events = POLLIN };
    return k;
}

/* send as much of the queue as the socket accepts */
static int dclient_flush(struct net *n, struct dclient *c)
{
    while (c->qn) {
        struct qitem *it = &c->q[c->qh];
        size_t hl = sizeof it->hdr;
        size_t total = hl + it->e->len;
        struct iovec iov[2];
        int niov = 0;
        if (it->off < hl) {
            iov[niov].iov_base = (uint8_t *)&it->hdr + it->off;
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
        n->sent++;
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
    if (count < 2)
        return;
    int k = 2;
    for (int i = 0; i < n->nd && k < count; i++, k++) {
        struct dclient *c = &n->d[i];
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
        if ((pfd[k].revents & POLLOUT) && dclient_flush(n, c) < 0)
            dclient_close(c);
    }
    for (int i = 0; i < n->nc && k < count; i++, k++)
        if (pfd[k].revents & (POLLIN | POLLHUP | POLLERR))
            cclient_input(n, &n->c[i]);

    /* compact closed clients */
    int j = 0;
    for (int i = 0; i < n->nd; i++)
        if (n->d[i].fd >= 0)
            n->d[j++] = n->d[i];
    n->nd = j;
    j = 0;
    for (int i = 0; i < n->nc; i++)
        if (n->c[i].fd >= 0)
            n->c[j++] = n->c[i];
    n->nc = j;

    /* new connections */
    if (pfd[0].revents & POLLIN) {
        char peer[48];
        int fd = accept_one(n->dl, peer, sizeof peer);
        if (fd >= 0) {
            if (n->nd >= NET_MAX_CLIENTS) {
                close(fd);
            } else {
                int sz = 8 << 20;
                setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sz, sizeof sz);
                struct dclient *c = &n->d[n->nd++];
                memset(c, 0, sizeof *c);
                c->fd = fd;
                snprintf(c->peer, sizeof c->peer, "%s", peer);
                LOGI("net: data client %s connected", peer);
            }
        }
    }
    if (pfd[1].revents & POLLIN) {
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

void net_publish(struct net *n, struct net_event *e)
{
    for (int i = 0; i < n->nd; i++) {
        struct dclient *c = &n->d[i];
        if (c->fd < 0)
            continue;
        if (c->qn >= NET_MAX_QUEUE) {
            c->dropped++;
            n->dropped++;
            continue;
        }
        struct qitem *it = &c->q[(c->qh + c->qn) % NET_MAX_QUEUE];
        it->e = e;
        it->hdr = e->fhdr;
        it->hdr.dropped = c->dropped;
        it->off = 0;
        e->refs++;
        c->qn++;
        if (c->qn == 1 && dclient_flush(n, c) < 0)   /* try immediately */
            dclient_close(c);
    }
}

int net_data_clients(const struct net *n)   { return n->nd; }
uint64_t net_frames_sent(const struct net *n)    { return n->sent; }
uint64_t net_frames_dropped(const struct net *n) { return n->dropped; }
