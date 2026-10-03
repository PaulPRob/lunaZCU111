# -----------------------------------------------------------------------------
# sim_spec.tcl : behavioural simulation of spectrometer_top with the real
#                CSIRO PFB/DFB cores (needs refernces/PFB, see spec_ip.tcl)
#
#   hw/sim/run_sim.sh spec          (runs both tests, then check_spec.py)
#
#   SPEC_TEST=data    : full chain, tones on ADC 5 (INPUT = 5) through PFB + DFB,
#                       decoy tone on ADC 0                        (default)
#   SPEC_TEST=restart : restart / shortening test, PFB model replaced by zeros
# -----------------------------------------------------------------------------
set here [file dirname [file normalize [info script]]]
set hw   [file normalize $here/..]
set top  [file normalize $hw/..]
set test [expr {[info exists ::env(SPEC_TEST)] ? $::env(SPEC_TEST) : "data"}]
set pdir $here/build/spec_sim_$test

create_project spec_sim $pdir -part xczu28dr-ffvg1517-2-e -force
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

source $hw/scripts/spec_ip.tcl

foreach f {luna_pkg capture_mem spec_regs_axil spectrometer_top} {
    add_files $hw/hdl/$f.vhd
}
add_files -fileset sim_1 $here/tb_spec.vhd
set_property file_type {VHDL 2008} [get_files tb_spec.vhd]
set_property top tb_spec [get_filesets sim_1]
if {$test eq "restart"} {
    set_property generic {TEST_MODE=1 NO_PFB=true} [get_filesets sim_1]
} else {
    set_property generic {TEST_MODE=0 NO_PFB=false TONE_CH=5} [get_filesets sim_1]
}
set_property -name xsim.simulate.runtime -value all -objects [get_filesets sim_1]
set_property -name xsim.simulate.log_all_signals -value false -objects [get_filesets sim_1]
# the System Generator / xfft behavioural models are slow: no debug info, optimise
set_property -name xsim.elaborate.debug_level -value off -objects [get_filesets sim_1]
set_property -name xsim.elaborate.xelab.more_options -value {-O3} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
close_sim
puts "SIM_DIR [get_property DIRECTORY [current_project]]/spec_sim.sim/sim_1/behav/xsim"
exit 0
