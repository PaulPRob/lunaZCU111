# -----------------------------------------------------------------------------
# ZCU111 (XCZU28DR-FFVG1517-2-E) - PL clock and SYSREF from the LMK04208 (U90)
# Pin locations from schematic 0381811 rev 1.0 sheet 4 (bank 64, HP, 1.8 V),
# net names as in UG1271 figure 3-18.  Both pairs are AC coupled (_C nets).
# RF data converter pins (ADC/DAC clocks, analog SYSREF, analog I/O) are
# dedicated and need no LOC constraints.
# -----------------------------------------------------------------------------

# FPGA_REFCLK_OUT_C_P/N : LMK04208 OUT2, 122.88 MHz  -> MMCM (clk_2x / clk_1x)
set_property PACKAGE_PIN AL16 [get_ports fpga_refclk_clk_p]
set_property PACKAGE_PIN AL15 [get_ports fpga_refclk_clk_n]
set_property IOSTANDARD LVDS [get_ports {fpga_refclk_clk_p fpga_refclk_clk_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {fpga_refclk_clk_p fpga_refclk_clk_n}]

# SYSREF_FPGA_C_P/N : LMK04208 OUT0, 7.68 MHz PL SYSREF (for MTS)
set_property PACKAGE_PIN AK17 [get_ports pl_sysref_p]
set_property PACKAGE_PIN AK16 [get_ports pl_sysref_n]
set_property IOSTANDARD LVDS [get_ports {pl_sysref_p pl_sysref_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {pl_sysref_p pl_sysref_n}]

# SYSREF leaves the LMK04208 edge aligned with FPGA_REFCLK_OUT (common VCO,
# SYNCed dividers). It is sampled on the falling edge of clk_1x.  The MMCM
# uses phase alignment (BUFG feedback, USE_PHASE_ALIGNMENT in build_bd.tcl)
# so clk_1x at the flops is aligned to the reference at the pin and the
# sampling point is ~2 ns away from any SYSREF transition.
set refclk [get_clocks -of_objects [get_ports fpga_refclk_clk_p]]
set_input_delay -clock $refclk -max  0.6 [get_ports pl_sysref_p]
set_input_delay -clock $refclk -min -0.6 [get_ports pl_sysref_p]

# The MMCM reset comes from an AXI GPIO (pl_clk0) and the MMCM LOCKED output
# is read back through the same GPIO: both are asynchronous and untimed
# (MMCM RST/LOCKED have no timing arcs), so no exception is needed.

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
