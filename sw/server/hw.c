/*
 * hw.c - UIO / devmem access helpers
 */
#include "hw.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "log.h"

static int read_sysfs_u64(const char *path, uint64_t *v)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return -1;
    int ok = fscanf(f, "%lx", (unsigned long *)v) == 1;
    fclose(f);
    return ok ? 0 : -1;
}

/* find the UIO device whose map0 starts at 'phys' */
static int uio_find(uint64_t phys, uint64_t *map_size)
{
    DIR *d = opendir("/sys/class/uio");
    if (!d)
        return -1;
    struct dirent *e;
    int found = -1;
    while ((e = readdir(d)) != NULL) {
        int n;
        if (sscanf(e->d_name, "uio%d", &n) != 1)
            continue;
        char path[256];
        uint64_t addr, size;
        snprintf(path, sizeof path, "/sys/class/uio/uio%d/maps/map0/addr", n);
        if (read_sysfs_u64(path, &addr) < 0 || addr != phys)
            continue;
        snprintf(path, sizeof path, "/sys/class/uio/uio%d/maps/map0/size", n);
        if (read_sysfs_u64(path, &size) < 0)
            continue;
        *map_size = size;
        found = n;
        break;
    }
    closedir(d);
    return found;
}

int hw_open(struct hw_region *r, uint64_t phys, size_t size)
{
    memset(r, 0, sizeof *r);
    r->fd = -1;
    r->uio_num = -1;
    r->phys = phys;

    uint64_t map_size = 0;
    int n = uio_find(phys, &map_size);
    if (n >= 0) {
        char dev[32];
        snprintf(dev, sizeof dev, "/dev/uio%d", n);
        r->fd = open(dev, O_RDWR | O_SYNC);
        if (r->fd < 0) {
            LOGE("open %s: %s", dev, strerror(errno));
            return -1;
        }
        if (map_size < size)
            size = map_size;
        void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, r->fd, 0);
        if (p == MAP_FAILED) {
            LOGE("mmap %s: %s", dev, strerror(errno));
            close(r->fd);
            r->fd = -1;
            return -1;
        }
        r->regs = p;
        r->size = size;
        r->uio_num = n;
        LOGI("0x%08lx: mapped via /dev/uio%d (%zu bytes)",
                 (unsigned long)phys, n, size);
        return 0;
    }

    /* fallback: /dev/mem */
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        LOGE("no UIO device for 0x%08lx and /dev/mem failed: %s",
                (unsigned long)phys, strerror(errno));
        return -1;
    }
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)phys);
    close(fd);
    if (p == MAP_FAILED) {
        LOGE("mmap /dev/mem 0x%08lx: %s", (unsigned long)phys, strerror(errno));
        return -1;
    }
    r->regs = p;
    r->size = size;
    LOGW("0x%08lx: no UIO device, mapped via /dev/mem (no interrupts)",
             (unsigned long)phys);
    return 0;
}

void hw_close(struct hw_region *r)
{
    if (r->regs)
        munmap((void *)r->regs, r->size);
    if (r->fd >= 0)
        close(r->fd);
    r->regs = NULL;
    r->fd = -1;
}

int hw_irq_enable(struct hw_region *r)
{
    if (r->fd < 0)
        return -1;
    uint32_t one = 1;
    return write(r->fd, &one, sizeof one) == sizeof one ? 0 : -1;
}

int hw_irq_wait(struct hw_region *r, int timeout_ms)
{
    if (r->fd < 0)
        return -1;
    struct pollfd p = { .fd = r->fd, .events = POLLIN };
    int rc = poll(&p, 1, timeout_ms);
    if (rc <= 0)
        return rc;
    uint32_t count;
    if (read(r->fd, &count, sizeof count) != sizeof count)
        return -1;
    return 1;
}

void hw_copy_from_io(void *dst, const volatile void *src, size_t len)
{
    /* Device memory must be read with naturally aligned accesses; the
     * buffers here are 64-byte aligned and len is a multiple of 16. */
    typedef struct { uint64_t a, b; } u128_t;
    const volatile u128_t *s = src;
    u128_t *d = dst;
    size_t n = len / sizeof(u128_t);
    for (size_t i = 0; i < n; i++) {
        u128_t v;
        v.a = s[i].a;
        v.b = s[i].b;
        d[i] = v;
    }
}
