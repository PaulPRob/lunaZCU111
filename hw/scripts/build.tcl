# -----------------------------------------------------------------------------
# build.tcl : unattended build of the ZCU111 trigger/capture design
#
#   source ~/Xilinx/license.sh
#   vivado -mode batch -source hw/scripts/build.tcl [-tclargs bd|synth|all] [jobs]
#
#   bd    : create project + block design only (quick check)
#   synth : ... + synthesis
#   all   : ... + implementation, bitstream, XSA  (default)
#
# Outputs (hw/build/):
#   vivado/                    Vivado project
#   lunaZCU111.xsa             hardware platform (with bitstream) for PetaLinux
#   lunaZCU111.bit             bitstream
#   timing_summary.rpt, utilization.rpt
# (docs/vivado_bd.{svg,pdf}: run export_bd_image.tcl in GUI mode afterwards)
# -----------------------------------------------------------------------------
set stage [expr {[llength $argv] > 0 ? [lindex $argv 0] : "all"}]
set jobs  [expr {[llength $argv] > 1 ? [lindex $argv 1] : 3}]   ;# keep <= 4 on a 16 GB machine

set here  [file dirname [file normalize [info script]]]
set hw    [file normalize $here/..]
set top   [file normalize $hw/..]
set bdir  $hw/build
set pdir  $bdir/vivado
file mkdir $bdir

create_project lunaZCU111 $pdir -part xczu28dr-ffvg1517-2-e -force
set_property board_part xilinx.com:zcu111:part0:1.4 [current_project]
set_property target_language VHDL [current_project]

# CSIRO PFB/DFB System Generator cores for the spectrometer (local only)
source $here/spec_ip.tcl

# custom HDL (module references)
add_files [lsort [glob $hw/hdl/*.vhd]]
update_compile_order -fileset sources_1
add_files -fileset constrs_1 $hw/constraints/zcu111.xdc

source $here/build_bd.tcl

set bd_file [get_files system.bd]
make_wrapper -files $bd_file -top
add_files -norecurse $pdir/lunaZCU111.gen/sources_1/bd/system/hdl/system_wrapper.vhd
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

if {$stage eq "bd"} {
    puts "BUILD: block design created and validated"
    exit 0
}

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "BUILD ERROR: synthesis failed"
    exit 1
}
if {$stage eq "synth"} {
    open_run synth_1
    report_utilization -file $bdir/utilization_synth.rpt
    puts "BUILD: synthesis done"
    exit 0
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "BUILD ERROR: implementation failed"
    exit 1
}

open_run impl_1
report_timing_summary -max_paths 20 -file $bdir/timing_summary.rpt
report_utilization -file $bdir/utilization.rpt
report_clock_interaction -file $bdir/clock_interaction.rpt
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "BUILD: WNS = $wns ns, WHS = $whs ns"

write_hw_platform -fixed -include_bit -force -file $bdir/lunaZCU111.xsa
file copy -force [glob $pdir/lunaZCU111.runs/impl_1/*.bit] $bdir/lunaZCU111.bit

if {$wns < 0 || $whs < 0} {
    puts "BUILD WARNING: timing NOT met - see $bdir/timing_summary.rpt"
    exit 2
}
puts "BUILD: done, timing met. XSA: $bdir/lunaZCU111.xsa"
exit 0
