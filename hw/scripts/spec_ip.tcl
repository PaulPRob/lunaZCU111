# -----------------------------------------------------------------------------
# spec_ip.tcl : CSIRO System Generator core used by spectrometer_top.vhd
#
# Sourced (with $top = repository root) by build.tcl and hw/sim/sim_spec.tcl
# after create_project.  The core is NOT in git: it must be present in the
# local folder refernces/PFB (dfb4096x1c_v2_0), or in the folder named by the
# environment variable LUNA_PFB_IP.  (The coarse filter bank is now our own
# oversampled hw/hdl/ospfb.vhd; pfb32x16t and rnd_23_18 are no longer used.)
# -----------------------------------------------------------------------------
set pfb_repo [file normalize $top/refernces/PFB]
if {[info exists ::env(LUNA_PFB_IP)]} {
    set pfb_repo [file normalize $::env(LUNA_PFB_IP)]
}
foreach core {dfb4096x1c_v2_0} {
    if {![file exists $pfb_repo/$core/component.xml]} {
        puts "BUILD ERROR: $pfb_repo/$core/component.xml not found."
        puts "  The CSIRO DFB core is kept out of git. Copy the folder"
        puts "  refernces/PFB into this checkout (or set LUNA_PFB_IP)."
        exit 3
    }
}

set_property ip_repo_paths [list $pfb_repo] [current_project]
update_ip_catalog -rebuild

# instance name must match the component in spectrometer_top.vhd
create_ip -vlnv CSIRO:SysGen:dfb4096x1c:2.0 -module_name dfb4096x1c_0
set spec_ips [get_ips {dfb4096x1c_0}]
# the core was packaged with System Generator 2018.2
foreach ip $spec_ips {
    if {[get_property UPGRADE_VERSIONS $ip] ne "" || [get_property IS_LOCKED $ip]} {
        catch {upgrade_ip $ip}
    }
}
generate_target all $spec_ips
