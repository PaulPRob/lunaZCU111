/*
 * hw.h - access to PL register blocks and the DMA buffer from user space
 *
 * Devices are located through /sys/class/uio by their physical base
 * address (device tree nodes with compatible = "generic-uio").  If no UIO
 * device matches, /dev/mem is used as a fallback (no interrupts then).
 */
#ifndef HW_H
#define HW_H

#include <stddef.h>
#include <stdint.h>

struct hw_region {
    int                fd;        /* /dev/uioN (or -1)                      */
    int                uio_num;   /* N, -1 when mapped through /dev/mem     */
    volatile uint32_t *regs;      /* mapping                                */
    size_t             size;
    uint64_t           phys;
};

int  hw_open(struct hw_region *r, uint64_t phys, size_t size);
void hw_close(struct hw_region *r);

static inline uint32_t hw_rd(const struct hw_region *r, uint32_t off)
{
    return r->regs[off / 4];
}

static inline void hw_wr(const struct hw_region *r, uint32_t off, uint32_t v)
{
    r->regs[off / 4] = v;
}

/* UIO interrupt handling (level interrupts: re-enable after servicing) */
int hw_irq_enable(struct hw_region *r);
/* returns 1 if an interrupt was consumed, 0 on timeout, -1 on error */
int hw_irq_wait(struct hw_region *r, int timeout_ms);

/* copy from a Device-type (uncached) mapping: aligned 16-byte loads only */
void hw_copy_from_io(void *dst, const volatile void *src, size_t len);

#endif
