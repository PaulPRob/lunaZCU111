/*
 * rfdc_init.c - RFDC bring-up with the Xilinx rfdc driver (librfdc/libmetal)
 *
 * Tiles: ADC 224..227 (driver tiles 0..3), 2 converters each, 3932.16 MSPS,
 * internal PLL from 245.76 MHz.  DAC tile 228 (driver DAC tile 0) is enabled
 * only because the Gen1 SYSREF master lives there; it outputs nothing.
 *
 * MTS: the LMK04208 supplies a continuous 7.68 MHz SYSREF (analog to DAC
 * tile 228, PL copy into user_sysref_adc).  After a successful sync the
 * SYSREF capture is disabled again so that the continuous SYSREF cannot
 * disturb the converters.
 */
#include "rfdc_init.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "log.h"

#ifdef LUNA_NO_RFDC

int  rf_init(void)     { LOGW("built without librfdc: RFDC not initialised"); return 0; }
int  rf_startup(void)  { return 0; }
int  rf_mts(void)      { return 0; }
void rf_status(char *buf, size_t len) { snprintf(buf, len, "rfdc=not-built-in"); }
void rf_close(void)    { }

#else

#include <metal/device.h>
#include <metal/sys.h>
#include "xrfdc.h"

#define RFDC_DEVICE_ID 0
#define ADC_TILES      0xFu
#define N_ADC_TILES    4

static XRFdc rfdc;
static struct metal_device *rfdc_dev;
static int rf_ready;
static int mts_ok;
static int mts_latency[N_ADC_TILES];
static int mts_offset[N_ADC_TILES];

int rf_init(void)
{
    struct metal_init_params init_param = METAL_INIT_DEFAULTS;
    if (metal_init(&init_param)) {
        LOGE("rfdc: metal_init failed");
        return -1;
    }
    metal_set_log_level(g_verbose ? METAL_LOG_DEBUG : METAL_LOG_WARNING);

    XRFdc_Config *cfg = XRFdc_LookupConfig(RFDC_DEVICE_ID);
    if (!cfg) {
        LOGE("rfdc: XRFdc_LookupConfig failed (device tree node / param-list?)");
        return -1;
    }
    if (XRFdc_RegisterMetal(&rfdc, RFDC_DEVICE_ID, &rfdc_dev) != XRFDC_SUCCESS) {
        LOGE("rfdc: XRFdc_RegisterMetal failed (is uio_pdrv_genirq loaded?)");
        return -1;
    }
    if (XRFdc_CfgInitialize(&rfdc, cfg) != XRFDC_SUCCESS) {
        LOGE("rfdc: XRFdc_CfgInitialize failed");
        return -1;
    }
    rf_ready = 1;
    LOGI("rfdc: driver initialised");
    return 0;
}

static int wait_pll(u32 type, u32 tile)
{
    u32 lock = 0;
    for (int i = 0; i < 200; i++) {
        if (XRFdc_GetPLLLockStatus(&rfdc, type, tile, &lock) == XRFDC_SUCCESS &&
            lock == XRFDC_PLL_LOCKED)
            return 0;
        usleep(5000);
    }
    return -1;
}

int rf_startup(void)
{
    if (!rf_ready)
        return -1;
    int bad = 0;

    /* (re)start all tiles now that the reference clocks and the fabric
     * clocks are present */
    if (XRFdc_StartUp(&rfdc, XRFDC_DAC_TILE, 0) != XRFDC_SUCCESS)
        LOGW("rfdc: DAC tile 0 start-up returned an error");
    if (XRFdc_StartUp(&rfdc, XRFDC_ADC_TILE, -1) != XRFDC_SUCCESS)
        LOGW("rfdc: ADC start-up returned an error");

    if (wait_pll(XRFDC_DAC_TILE, 0) < 0) {
        LOGE("rfdc: DAC tile 228 PLL not locked");
        bad++;
    }
    for (u32 t = 0; t < N_ADC_TILES; t++) {
        if (wait_pll(XRFDC_ADC_TILE, t) < 0) {
            LOGE("rfdc: ADC tile %u (%u) PLL not locked", t, 224 + t);
            bad++;
            continue;
        }
        XRFdc_PLL_Settings pll;
        if (XRFdc_GetPLLConfig(&rfdc, XRFDC_ADC_TILE, t, &pll) == XRFDC_SUCCESS)
            LOGI("rfdc: ADC tile %u (%u) PLL locked, ref %.3f MHz, fs %.3f MHz",
                     t, 224 + t, pll.RefClkFreq, pll.SampleRate * 1000.0);
    }

    XRFdc_IPStatus st;
    if (XRFdc_GetIPStatus(&rfdc, &st) == XRFDC_SUCCESS) {
        for (int t = 0; t < N_ADC_TILES; t++)
            LOGI("rfdc: ADC tile %d state %u power-up %u", t,
                     st.ADCTileStatus[t].TileState, st.ADCTileStatus[t].PowerUpState);
    }
    return bad ? -1 : 0;
}

int rf_mts(void)
{
    if (!rf_ready)
        return -1;
    XRFdc_MultiConverter_Sync_Config adc, dac;

    XRFdc_MultiConverter_Init(&adc, NULL, NULL, XRFDC_TILE_ID0);
    XRFdc_MultiConverter_Init(&dac, NULL, NULL, XRFDC_TILE_ID0);
    adc.Tiles = ADC_TILES;
    dac.Tiles = 0;
    adc.Target_Latency = -1;      /* align to the slowest tile */

    u32 status = XRFdc_MultiConverter_Sync(&rfdc, XRFDC_ADC_TILE, &adc);
    mts_ok = (status == XRFDC_MTS_OK);
    if (!mts_ok) {
        LOGE("rfdc: ADC multi-tile sync FAILED (code %u) - check SYSREF "
                "(LMK04208 OUT0/OUT1) and the PL SYSREF capture", status);
        return -1;
    }
    for (int t = 0; t < N_ADC_TILES; t++) {
        mts_latency[t] = adc.Latency[t];
        mts_offset[t] = adc.Offset[t];
        LOGI("rfdc: MTS ADC tile %d latency %d T1, offset %d words",
                 t, adc.Latency[t], adc.Offset[t]);
    }
    /* continuous SYSREF: stop capturing it now that the tiles are aligned */
    XRFdc_MTS_Sysref_Config(&rfdc, &dac, &adc, 0);
    LOGI("rfdc: ADC multi-tile sync OK");
    return 0;
}

void rf_status(char *buf, size_t len)
{
    if (!rf_ready) {
        snprintf(buf, len, "rfdc=down");
        return;
    }
    size_t n = (size_t)snprintf(buf, len, "rfdc=up mts=%s", mts_ok ? "ok" : "no");
    for (u32 t = 0; t < N_ADC_TILES && n < len; t++) {
        u32 lock = 0;
        XRFdc_GetPLLLockStatus(&rfdc, XRFDC_ADC_TILE, t, &lock);
        n += (size_t)snprintf(buf + n, len - n, " adc%u=%s/lat%d", 224 + t,
                              lock == XRFDC_PLL_LOCKED ? "lock" : "UNLOCK",
                              mts_latency[t]);
    }
}

void rf_close(void)
{
    if (rf_ready)
        metal_finish();
    rf_ready = 0;
}

#endif
