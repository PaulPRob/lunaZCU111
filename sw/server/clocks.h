/*
 * clocks.h - ZCU111 RF clock programming (LMK04208 + 3 x LMX2594)
 *
 * Path: PS I2C1 -> TCA9548A (0x74) port 5 -> SC18IS602B I2C-to-SPI (0x2F)
 *   SS0 = LMX2594 U104 (DAC tiles), SS1 = LMK04208 U90,
 *   SS2 = LMX2594 U103 (ADC 226/227), SS3 = LMX2594 U102 (ADC 224/225)
 */
#ifndef CLOCKS_H
#define CLOCKS_H

/* i2c_bus: Linux bus number of TCA9548A channel 5, or -1 to auto-detect */
int clocks_program(int i2c_bus);

#endif
