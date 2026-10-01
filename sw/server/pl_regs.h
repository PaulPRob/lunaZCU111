/*
 * pl_regs.h - PL address map and register definitions
 * (must match hw/scripts/build_bd.tcl and hw/hdl/trig_regs_axil.vhd)
 */
#ifndef PL_REGS_H
#define PL_REGS_H

/* physical addresses (block design address map) */
#define RFDC_BASE        0xA0000000u
#define TRIG_BASE        0xA0100000u
#define DMA_BASE         0xA0110000u
#define GPIO_BASE        0xA0120000u
/* DMA target: reserved-memory region in the device tree */
#define DMABUF_BASE      0x70000000u
#define DMABUF_SIZE      0x01000000u

/* trigger_capture registers */
#define TR_ID            0x000
#define TR_VERSION       0x004
#define TR_CTRL          0x008
#define   CTRL_ARM         (1u << 0)
#define   CTRL_SOFT_TRIG   (1u << 1)
#define   CTRL_TS_RESET    (1u << 2)
#define   CTRL_FLUSH       (1u << 3)
#define   CTRL_CNT_CLEAR   (1u << 4)
#define   CTRL_IRQ_EN      (1u << 8)
#define TR_STATUS        0x00C
#define   ST_NFULL(x)      ((x) & 0xF)
#define   ST_HEAD(x)       (((x) >> 4) & 0xF)
#define   ST_CAPTURING     (1u << 8)
#define   ST_RD_BUSY       (1u << 9)
#define   ST_PREFILLED     (1u << 10)
#define   ST_ARMED         (1u << 16)
#define TR_MODE          0x010
#define TR_COINC_N       0x014
#define TR_WINDOW        0x018
#define TR_CH_MASK       0x01C
#define TR_CAP_LEN       0x020
#define TR_READOUT       0x024
#define TR_RELEASE       0x028
#define TR_TS_LO         0x030
#define TR_TS_HI         0x034
#define TR_TRIG_COUNT    0x038
#define TR_LOST_COUNT    0x03C
#define TR_THRESH(i)     (0x040 + 4 * (i))
#define TR_HITCNT(i)     (0x060 + 4 * (i))
#define TR_PEAK(i)       (0x080 + 4 * (i))
#define TR_SYSREF_CNT    0x0A0
#define TR_SCRATCH       0x0A4
#define TR_ID_VALUE      0x4C554E41u

/* AXI DMA (simple mode, S2MM only) */
#define DMA_S2MM_DMACR   0x30
#define   DMACR_RS         (1u << 0)
#define   DMACR_RESET      (1u << 2)
#define   DMACR_IOC_IRQEN  (1u << 12)
#define   DMACR_ERR_IRQEN  (1u << 14)
#define DMA_S2MM_DMASR   0x34
#define   DMASR_HALTED     (1u << 0)
#define   DMASR_IDLE       (1u << 1)
#define   DMASR_ERR_MASK   0x770u
#define   DMASR_IOC_IRQ    (1u << 12)
#define   DMASR_ERR_IRQ    (1u << 14)
#define DMA_S2MM_DA      0x48
#define DMA_S2MM_DA_MSB  0x4C
#define DMA_S2MM_LENGTH  0x58

/* AXI GPIO: channel 1 bit0 = MMCM reset (out), channel 2 bit0 = MMCM locked */
#define GPIO_DATA        0x00
#define GPIO_TRI         0x04
#define GPIO2_DATA       0x08

#endif
