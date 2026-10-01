/* rfdc_init.h - RF data converter start-up and multi-tile synchronisation */
#ifndef RFDC_INIT_H
#define RFDC_INIT_H

#include <stddef.h>

int  rf_init(void);                   /* libmetal + driver instance        */
int  rf_startup(void);                /* start tiles, wait for PLL lock    */
int  rf_mts(void);                    /* ADC multi-tile sync (tiles 0..3)  */
void rf_status(char *buf, size_t len);/* one-line status summary           */
void rf_close(void);

#endif
