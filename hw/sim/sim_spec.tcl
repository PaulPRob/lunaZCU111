# -----------------------------------------------------------------------------
# sim_spec.tcl : behavioural simulation of spectrometer_top with the real
#                CSIRO PFB/DFB cores (needs refernces/PFB, see spec_ip.tcl)
#
#   hw/sim/run_sim.sh spec          (runs this, then check_spec.py)
# -----------------------------------------------------------------------------
set here [file dirname [file normalize [info script]]]
set hw   [file normalize $here/..]
set top  [file normalize $hw/..]
set pdir $here/build/spec_sim

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
set_property -name xsim.simulate.runtime -value all -objects [get_filesets sim_1]
set_property -name xsim.simulate.log_all_signals -value false -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
close_sim
puts "SIM_DIR [get_property DIRECTORY [current_project]]/spec_sim.sim/sim_1/behav/xsim"
exit 0
