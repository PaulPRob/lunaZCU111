# -----------------------------------------------------------------------------
# build_bd.tcl : block design "system" for the ZCU111 8-channel trigger/capture
#
# Sourced by build.tcl after the project exists and the HDL files are added.
#
#   PS (ZCU111 preset: DDR4, GEM3 1GbE, SD, UART, I2C) --HPM0--> SmartConnect
#       -> RFDC AXI-Lite            0xA000_0000  (pl_clk0 100 MHz)
#       -> trigger_capture regs     0xA010_0000  (clk_1x 245.76 MHz)
#       -> AXI DMA (S2MM) regs      0xA011_0000  (pl_clk0)
#       -> AXI GPIO (MMCM ctrl)     0xA012_0000  (pl_clk0)
#       -> spectrometer regs + mem  0xA014_0000  (clk_spec 122.88 MHz, 128 KiB)
#   RFDC 8 x ADC 3932.16 MSPS (4 dual tiles, PLL from 245.76 MHz, MTS)
#       m00/m02/m10/m12/m20/m22/m30/m32 (491.52 MHz) -> trigger_capture s00..s07
#   DAC tile 228 channel 0 enabled only so the Gen1 SYSREF master is powered
#   trigger_capture m_axis -> AXI DMA S2MM -> S_AXI_HP0 -> DDR
#   FPGA_REFCLK_OUT 122.88 MHz -> MMCM -> clk_2x 491.52 / clk_1x 245.76 /
#                                          clk_spec 122.88 MHz
#   trigger_capture spec_word (ADC 0) -> spectrometer (PFB 16 ch -> DFB 4096 ch)
#   PL SYSREF 7.68 MHz -> pl_sysref_sync -> RFDC user_sysref_adc
# -----------------------------------------------------------------------------

create_bd_design "system"

# ---------------------------------------------------------------- PS --------
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} $ps
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 1 \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH 32 \
    CONFIG.PSU__USE__M_AXI_GP1 0 \
    CONFIG.PSU__USE__M_AXI_GP2 0 \
    CONFIG.PSU__USE__S_AXI_GP2 1 \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH 128 \
    CONFIG.PSU__USE__IRQ0 1 \
    CONFIG.PSU__FPGA_PL0_ENABLE 1 \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ 100 \
    CONFIG.PSU__USE__FABRIC__RST 1 \
] $ps

# ------------------------------------------------------------- clocks --------
set cw [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz]
set_property -dict [list \
    CONFIG.PRIM_SOURCE Differential_clock_capable_pin \
    CONFIG.PRIM_IN_FREQ 122.880 \
    CONFIG.USE_PHASE_ALIGNMENT true \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 491.520 \
    CONFIG.CLKOUT2_USED true \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 245.760 \
    CONFIG.CLK_OUT1_PORT clk_2x \
    CONFIG.CLK_OUT2_PORT clk_1x \
    CONFIG.CLKOUT3_USED true \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ 122.880 \
    CONFIG.CLK_OUT3_PORT clk_spec \
    CONFIG.USE_RESET true \
    CONFIG.RESET_TYPE ACTIVE_HIGH \
    CONFIG.USE_LOCKED true \
    CONFIG.MMCM_CLKFBOUT_MULT_F 8.000 \
    CONFIG.MMCM_DIVCLK_DIVIDE 1 \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F 2.000 \
    CONFIG.MMCM_CLKOUT1_DIVIDE 4 \
    CONFIG.MMCM_CLKOUT2_DIVIDE 8 \
] $cw
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 fpga_refclk
set_property CONFIG.FREQ_HZ 122880000 [get_bd_intf_ports fpga_refclk]
connect_bd_intf_net [get_bd_intf_ports fpga_refclk] [get_bd_intf_pins $cw/CLK_IN1_D]

# MMCM reset / lock via AXI GPIO (the LMK04208 is programmed from Linux, so the
# MMCM input clock only appears after boot and the MMCM must be reset then)
set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 mmcm_gpio]
set_property -dict [list \
    CONFIG.C_IS_DUAL 1 \
    CONFIG.C_GPIO_WIDTH 1 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000000 \
    CONFIG.C_GPIO2_WIDTH 1 CONFIG.C_ALL_INPUTS_2 1 \
] $gpio
connect_bd_net [get_bd_pins $gpio/gpio_io_o] [get_bd_pins $cw/reset]
connect_bd_net [get_bd_pins $cw/locked] [get_bd_pins $gpio/gpio2_io_i]

# ------------------------------------------------------------- resets --------
set rst100 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_100]
set rst1x  [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_1x]
set rst2x  [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_2x]
set rstsp  [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_spec]
connect_bd_net [get_bd_pins $ps/pl_clk0] [get_bd_pins $rst100/slowest_sync_clk]
connect_bd_net [get_bd_pins $ps/pl_resetn0] \
    [get_bd_pins $rst100/ext_reset_in] [get_bd_pins $rst1x/ext_reset_in] \
    [get_bd_pins $rst2x/ext_reset_in] [get_bd_pins $rstsp/ext_reset_in]
connect_bd_net [get_bd_pins $cw/clk_1x] [get_bd_pins $rst1x/slowest_sync_clk]
connect_bd_net [get_bd_pins $cw/clk_2x] [get_bd_pins $rst2x/slowest_sync_clk]
connect_bd_net [get_bd_pins $cw/clk_spec] [get_bd_pins $rstsp/slowest_sync_clk]
connect_bd_net [get_bd_pins $cw/locked] \
    [get_bd_pins $rst1x/dcm_locked] [get_bd_pins $rst2x/dcm_locked] \
    [get_bd_pins $rstsp/dcm_locked]

# ---------------------------------------------------------------- RFDC -------
set rf [create_bd_cell -type ip -vlnv xilinx.com:ip:usp_rf_data_converter:2.6 rfdc]
set cfg {}
foreach t {0 1 2 3} {
    lappend cfg CONFIG.ADC${t}_Enable 1 CONFIG.ADC${t}_Sampling_Rate 3.93216 \
        CONFIG.ADC${t}_Refclk_Freq 245.760 CONFIG.ADC${t}_PLL_Enable true \
        CONFIG.ADC${t}_Fabric_Freq 491.520 CONFIG.ADC${t}_Multi_Tile_Sync true
    foreach s {0 1 2 3} {
        lappend cfg CONFIG.ADC_Slice${t}${s}_Enable true CONFIG.ADC_Data_Type${t}${s} 0 \
            CONFIG.ADC_Decimation_Mode${t}${s} 1 CONFIG.ADC_Mixer_Type${t}${s} 0 \
            CONFIG.ADC_Data_Width${t}${s} 8
    }
}
# DAC tile 228 (tile 0): powered and clocked only to host the SYSREF receiver
# that the Gen1 MTS driver uses; its output is never driven with a signal.
lappend cfg CONFIG.DAC0_Enable 1 CONFIG.DAC0_Sampling_Rate 3.93216 \
    CONFIG.DAC0_Refclk_Freq 245.760 CONFIG.DAC0_PLL_Enable true \
    CONFIG.DAC0_Fabric_Freq 245.760 CONFIG.DAC_Slice00_Enable true \
    CONFIG.DAC_Interpolation_Mode00 1 CONFIG.DAC_Mixer_Type00 0 CONFIG.DAC_Data_Width00 16
set_property -dict $cfg $rf

foreach t {0 1 2 3} {
    make_bd_intf_pins_external [get_bd_intf_pins $rf/adc${t}_clk]
    make_bd_intf_pins_external [get_bd_intf_pins $rf/vin${t}_01]
    make_bd_intf_pins_external [get_bd_intf_pins $rf/vin${t}_23]
    connect_bd_net [get_bd_pins $cw/clk_2x] [get_bd_pins $rf/m${t}_axis_aclk]
    connect_bd_net [get_bd_pins $rst2x/peripheral_aresetn] [get_bd_pins $rf/m${t}_axis_aresetn]
}
make_bd_intf_pins_external [get_bd_intf_pins $rf/dac0_clk]
make_bd_intf_pins_external [get_bd_intf_pins $rf/vout00]
make_bd_intf_pins_external [get_bd_intf_pins $rf/sysref_in]
connect_bd_net [get_bd_pins $ps/pl_clk0] [get_bd_pins $rf/s_axi_aclk]
connect_bd_net [get_bd_pins $rst100/peripheral_aresetn] [get_bd_pins $rf/s_axi_aresetn]
connect_bd_net [get_bd_pins $cw/clk_1x] [get_bd_pins $rf/s0_axis_aclk]
connect_bd_net [get_bd_pins $rst1x/peripheral_aresetn] [get_bd_pins $rf/s0_axis_aresetn]

# DAC stream: constant zero
set dz [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 dac_zero]
set_property -dict [list CONFIG.CONST_WIDTH 256 CONFIG.CONST_VAL 0] $dz
set d1 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 dac_valid]
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1] $d1
connect_bd_net [get_bd_pins $dz/dout] [get_bd_pins $rf/s00_axis_tdata]
connect_bd_net [get_bd_pins $d1/dout] [get_bd_pins $rf/s00_axis_tvalid]

# ---------------------------------------------------------- PL SYSREF --------
set sr [create_bd_cell -type module -reference pl_sysref_sync pl_sysref]
create_bd_port -dir I pl_sysref_p
create_bd_port -dir I pl_sysref_n
connect_bd_net [get_bd_ports pl_sysref_p] [get_bd_pins $sr/sysref_in_p]
connect_bd_net [get_bd_ports pl_sysref_n] [get_bd_pins $sr/sysref_in_n]
connect_bd_net [get_bd_pins $cw/clk_1x] [get_bd_pins $sr/clk_1x]
connect_bd_net [get_bd_pins $cw/clk_2x] [get_bd_pins $sr/clk_2x]
connect_bd_net [get_bd_pins $sr/user_sysref_adc] [get_bd_pins $rf/user_sysref_adc]

# ---------------------------------------------------- trigger / capture ------
set tc [create_bd_cell -type module -reference trigger_capture_top trigger_capture]
connect_bd_net [get_bd_pins $cw/clk_2x] [get_bd_pins $tc/clk_2x]
connect_bd_net [get_bd_pins $cw/clk_1x] [get_bd_pins $tc/clk_1x]
connect_bd_net [get_bd_pins $rst1x/peripheral_aresetn] [get_bd_pins $tc/aresetn]
connect_bd_net [get_bd_pins $sr/sysref_1x] [get_bd_pins $tc/sysref_1x]
set i 0
foreach m {m00 m02 m10 m12 m20 m22 m30 m32} {
    connect_bd_intf_net [get_bd_intf_pins $rf/${m}_axis] \
        [get_bd_intf_pins $tc/[format "s%02d_axis" $i]]
    incr i
}

# ---------------------------------------------------------- spectrometer ----
# ADC channel 0 (after the trigger core's gearbox) -> PFB/DFB integrating
# spectrometer; the CSIRO cores are created by spec_ip.tcl (from build.tcl)
set sp [create_bd_cell -type module -reference spectrometer_top spectrometer]
connect_bd_net [get_bd_pins $cw/clk_1x] [get_bd_pins $sp/clk_1x]
connect_bd_net [get_bd_pins $cw/clk_spec] [get_bd_pins $sp/clk_spec]
connect_bd_net [get_bd_pins $rstsp/peripheral_aresetn] [get_bd_pins $sp/aresetn]
connect_bd_net [get_bd_pins $tc/spec_word] [get_bd_pins $sp/din_1x]
connect_bd_net [get_bd_pins $tc/spec_ts] [get_bd_pins $sp/ts_1x]

# ------------------------------------------------------------------ DMA -------
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma]
set_property -dict [list \
    CONFIG.c_include_sg 0 \
    CONFIG.c_include_mm2s 0 \
    CONFIG.c_include_s2mm 1 \
    CONFIG.c_sg_length_width 26 \
    CONFIG.c_m_axi_s2mm_data_width 128 \
    CONFIG.c_s_axis_s2mm_tdata_width 128 \
    CONFIG.c_s2mm_burst_size 64 \
    CONFIG.c_addr_width 32 \
] $dma
connect_bd_intf_net [get_bd_intf_pins $tc/m_axis] [get_bd_intf_pins $dma/S_AXIS_S2MM]
connect_bd_net [get_bd_pins $ps/pl_clk0] [get_bd_pins $dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins $cw/clk_1x] [get_bd_pins $dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins $rst100/peripheral_aresetn] [get_bd_pins $dma/axi_resetn]

# DMA -> HP0 (clk_1x)
set sc_hp [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 sc_hp0]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] $sc_hp
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_S2MM] [get_bd_intf_pins $sc_hp/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $sc_hp/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0_FPD]
connect_bd_net [get_bd_pins $cw/clk_1x] [get_bd_pins $sc_hp/aclk] [get_bd_pins $ps/saxihp0_fpd_aclk]
connect_bd_net [get_bd_pins $rst1x/peripheral_aresetn] [get_bd_pins $sc_hp/aresetn]

# ------------------------------------------------------- control bus ---------
set sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 sc_ctrl]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 5 CONFIG.NUM_CLKS 3] $sc
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_FPD] [get_bd_intf_pins $sc/S00_AXI]
connect_bd_net [get_bd_pins $ps/pl_clk0] [get_bd_pins $ps/maxihpm0_fpd_aclk] \
    [get_bd_pins $sc/aclk] [get_bd_pins $gpio/s_axi_aclk]
connect_bd_net [get_bd_pins $cw/clk_1x] [get_bd_pins $sc/aclk1]
connect_bd_net [get_bd_pins $cw/clk_spec] [get_bd_pins $sc/aclk2]
connect_bd_net [get_bd_pins $rst100/peripheral_aresetn] [get_bd_pins $sc/aresetn] \
    [get_bd_pins $gpio/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins $sc/M00_AXI] [get_bd_intf_pins $rf/s_axi]
connect_bd_intf_net [get_bd_intf_pins $sc/M01_AXI] [get_bd_intf_pins $tc/s_axi]
connect_bd_intf_net [get_bd_intf_pins $sc/M02_AXI] [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $sc/M03_AXI] [get_bd_intf_pins $gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $sc/M04_AXI] [get_bd_intf_pins $sp/s_axi]

# ------------------------------------------------------------ interrupts -----
set cc [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
set_property CONFIG.NUM_PORTS 4 $cc
connect_bd_net [get_bd_pins $tc/irq] [get_bd_pins $cc/In0]
connect_bd_net [get_bd_pins $dma/s2mm_introut] [get_bd_pins $cc/In1]
connect_bd_net [get_bd_pins $rf/irq] [get_bd_pins $cc/In2]
connect_bd_net [get_bd_pins $sp/irq] [get_bd_pins $cc/In3]
connect_bd_net [get_bd_pins $cc/dout] [get_bd_pins $ps/pl_ps_irq0]

# --------------------------------------------------------- address map --------
set psd [get_bd_addr_spaces ps/Data]
assign_bd_address -offset 0xA0000000 -range 256K -target_address_space $psd [get_bd_addr_segs rfdc/s_axi/Reg]
assign_bd_address -offset 0xA0100000 -range 4K   -target_address_space $psd [get_bd_addr_segs trigger_capture/s_axi/reg0]
assign_bd_address -offset 0xA0110000 -range 64K  -target_address_space $psd [get_bd_addr_segs dma/S_AXI_LITE/Reg]
assign_bd_address -offset 0xA0120000 -range 64K  -target_address_space $psd [get_bd_addr_segs mmcm_gpio/S_AXI/Reg]
assign_bd_address -offset 0xA0140000 -range 128K -target_address_space $psd [get_bd_addr_segs spectrometer/s_axi/reg0]
# DMA -> DDR through HP0
assign_bd_address

regenerate_bd_layout
validate_bd_design
save_bd_design
