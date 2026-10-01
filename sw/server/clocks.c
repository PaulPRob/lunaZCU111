/*
 * clocks.c - program the ZCU111 LMK04208 and LMX2594s through the
 *            SC18IS602B I2C-to-SPI bridge using Linux i2c-dev.
 *
 * Sequence:
 *   1. LMK04208: all registers (reset first), then a SYNC (toggle
 *      SYNC_POL_INV in R11) so that the /384 SYSREF outputs are phase
 *      aligned with the /24 122.88 MHz outputs (SYNC_EN_AUTO = 0).
 *   2. wait for the LMK PLLs, then the three LMX2594 (245.76 MHz).
 */
#include "clocks.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/i2c-dev.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "clk_tables.h"
#include "log.h"

#define SC18IS602_ADDR   0x2F
#define TCA9548_ADDR     0x74
#define TCA9548_CHAN     5
#define SS_LMX_U104      0
#define SS_LMK           1
#define SS_LMX_U103      2
#define SS_LMX_U102      3

/* SC18IS602B "configure SPI" function: MSB first, mode 0, 461 kHz */
#define SC18_FN_CONFIG   0xF0
#define SC18_CFG_461KHZ  0x01

static int read_line(const char *path, char *buf, size_t len)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return -1;
    if (!fgets(buf, (int)len, f)) {
        fclose(f);
        return -1;
    }
    fclose(f);
    buf[strcspn(buf, "\n")] = 0;
    return 0;
}

/*
 * Find the i2c adapter for TCA9548A (0x74) channel 5.  With the pca954x
 * driver the channel adapters are named "i2c-<parent>-mux (chan_id 5)" and
 * live below .../<parent>-0074/ in sysfs.
 */
static int find_mux_bus(void)
{
    DIR *d = opendir("/sys/bus/i2c/devices");
    if (!d)
        return -1;
    struct dirent *e;
    int bus = -1;
    while ((e = readdir(d)) != NULL) {
        int n;
        if (sscanf(e->d_name, "i2c-%d", &n) != 1)
            continue;
        char path[PATH_MAX], name[128], real[PATH_MAX];
        snprintf(path, sizeof path, "/sys/bus/i2c/devices/%s/name", e->d_name);
        if (read_line(path, name, sizeof name) < 0)
            continue;
        if (!strstr(name, "chan_id 5"))
            continue;
        snprintf(path, sizeof path, "/sys/bus/i2c/devices/%s", e->d_name);
        if (!realpath(path, real) || !strstr(real, "-0074/"))
            continue;
        bus = n;
        break;
    }
    closedir(d);
    return bus;
}

/* PS I2C1 (Cadence controller at 0xff030000) - used if no mux driver */
static int find_ps_i2c1(void)
{
    DIR *d = opendir("/sys/bus/i2c/devices");
    if (!d)
        return -1;
    struct dirent *e;
    int bus = -1;
    while ((e = readdir(d)) != NULL) {
        int n;
        if (sscanf(e->d_name, "i2c-%d", &n) != 1)
            continue;
        char path[PATH_MAX], name[128];
        snprintf(path, sizeof path, "/sys/bus/i2c/devices/%s/name", e->d_name);
        if (read_line(path, name, sizeof name) == 0 && strstr(name, "ff030000")) {
            bus = n;
            break;
        }
    }
    closedir(d);
    return bus;
}

static int i2c_set_addr(int fd, int addr)
{
    if (ioctl(fd, I2C_SLAVE, addr) < 0) {
        if (errno != EBUSY || ioctl(fd, I2C_SLAVE_FORCE, addr) < 0)
            return -1;
    }
    return 0;
}

/* I2C write with retries: the SC18IS602B NACKs while an SPI transfer runs */
static int i2c_write_retry(int fd, const uint8_t *buf, size_t len)
{
    for (int tries = 0; tries < 200; tries++) {
        ssize_t w = write(fd, buf, len);
        if (w == (ssize_t)len)
            return 0;
        usleep(100);
    }
    return -1;
}

static int spi_write(int fd, int ss, uint32_t word, int nbytes)
{
    uint8_t buf[5];
    buf[0] = (uint8_t)(1u << ss);
    for (int i = 0; i < nbytes; i++)
        buf[1 + i] = (uint8_t)(word >> (8 * (nbytes - 1 - i)));
    if (i2c_write_retry(fd, buf, (size_t)nbytes + 1) < 0) {
        LOGE("SC18IS602 write (SS%d, 0x%08x) failed: %s", ss, word, strerror(errno));
        return -1;
    }
    /* 32 bits @ 461 kHz ~ 70 us; allow the bridge to finish */
    usleep(150);
    return 0;
}

static int program_lmx(int fd, int ss, const char *name)
{
    for (size_t i = 0; i < LMX2594_REGS_LEN; i++) {
        if (spi_write(fd, ss, lmx2594_regs[i], 3) < 0)
            return -1;
        if (i == 0)
            usleep(1000);          /* after RESET */
    }
    LOGI("  %s programmed (%zu registers, 245.76 MHz)", name, LMX2594_REGS_LEN);
    return 0;
}

int clocks_program(int i2c_bus)
{
    int bus = i2c_bus;
    int need_mux_select = 0;

    if (bus < 0)
        bus = find_mux_bus();
    if (bus < 0) {
        bus = find_ps_i2c1();
        need_mux_select = 1;
    }
    if (bus < 0) {
        LOGE("clocks: cannot find the I2C bus of the SC18IS602 bridge");
        return -1;
    }

    char dev[32];
    snprintf(dev, sizeof dev, "/dev/i2c-%d", bus);
    int fd = open(dev, O_RDWR);
    if (fd < 0) {
        LOGE("clocks: open %s: %s", dev, strerror(errno));
        return -1;
    }
    LOGI("clocks: using %s%s", dev, need_mux_select ? " (selecting TCA9548A ch5)" : "");

    if (need_mux_select) {
        uint8_t sel = 1u << TCA9548_CHAN;
        if (i2c_set_addr(fd, TCA9548_ADDR) < 0 || write(fd, &sel, 1) != 1) {
            LOGE("clocks: TCA9548A select failed: %s", strerror(errno));
            close(fd);
            return -1;
        }
    }

    if (i2c_set_addr(fd, SC18IS602_ADDR) < 0) {
        LOGE("clocks: cannot address SC18IS602 (0x%02x): %s", SC18IS602_ADDR, strerror(errno));
        close(fd);
        return -1;
    }
    uint8_t cfg[2] = { SC18_FN_CONFIG, SC18_CFG_461KHZ };
    if (i2c_write_retry(fd, cfg, 2) < 0) {
        LOGE("clocks: SC18IS602 not responding (is J23 bridge-inhibit jumper off?)");
        close(fd);
        return -1;
    }
    usleep(1000);

    /* ---- LMK04208 ---- */
    for (size_t i = 0; i < LMK04208_REGS_LEN; i++) {
        if (spi_write(fd, SS_LMK, lmk04208_regs[i], 4) < 0)
            goto fail;
        if (i == 0)
            usleep(1000);          /* after RESET */
    }
    /* SYNC: assert by inverting SYNC polarity, release again */
    usleep(20000);
    if (spi_write(fd, SS_LMK, LMK_R11_VALUE | (1u << 16), 4) < 0)
        goto fail;
    usleep(1000);
    if (spi_write(fd, SS_LMK, LMK_R11_VALUE, 4) < 0)
        goto fail;
    LOGI("  LMK04208 programmed (%zu registers), SYNC issued: "
             "PL refclk 122.88 MHz, SYSREF 7.68 MHz", LMK04208_REGS_LEN);
    usleep(100000);                /* PLL1/PLL2 lock */

    /* ---- LMX2594 x 3 ---- */
    if (program_lmx(fd, SS_LMX_U102, "LMX2594 U102 (ADC 224/225)") < 0 ||
        program_lmx(fd, SS_LMX_U103, "LMX2594 U103 (ADC 226/227)") < 0 ||
        program_lmx(fd, SS_LMX_U104, "LMX2594 U104 (DAC 228/229)") < 0)
        goto fail;
    usleep(50000);

    close(fd);
    return 0;

fail:
    close(fd);
    return -1;
}
