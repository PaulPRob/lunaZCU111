# -----------------------------------------------------------------------------
# spec_ip.tcl : CSIRO System Generator cores used by spectrometer_top.vhd
#
# Sourced (with $top = repository root) by build.tcl and hw/sim/sim_spec.tcl
# after create_project.  The cores are NOT in git: they must be present in the
# local folder refernces/PFB (pfb32x16t_v1_6, dfb4096x1c_v2_0, rnd_23_18_v1_0),
# or in the folder named by the environment variable LUNA_PFB_IP.
# -----------------------------------------------------------------------------
set pfb_repo [file normalize $top/refernces/PFB]
if {[info exists ::env(LUNA_PFB_IP)]} {
    set pfb_repo [file normalize $::env(LUNA_PFB_IP)]
}
foreach core {pfb32x16t_v1_6 dfb4096x1c_v2_0 rnd_23_18_v1_0} {
    if {![file exists $pfb_repo/$core/component.xml]} {
        puts "BUILD ERROR: $pfb_repo/$core/component.xml not found."
        puts "  The CSIRO PFB/DFB cores are kept out of git. Copy the folder"
        puts "  refernces/PFB into this checkout (or set LUNA_PFB_IP)."
        exit 3
    }
}

set_property ip_repo_paths [list $pfb_repo] [current_project]
update_ip_catalog -rebuild

# instance names must match the components in spectrometer_top.vhd
foreach {vlnv name} {
    CSIRO:SysGen:pfb32x16t:1.6  pfb32x16t_0
    CSIRO:SysGen:rnd_23_18:1.0  rnd_23_18_0
    CSIRO:SysGen:dfb4096x1c:2.0 dfb4096x1c_0
} {
    create_ip -vlnv $vlnv -module_name $name
}
set spec_ips [get_ips {pfb32x16t_0 rnd_23_18_0 dfb4096x1c_0}]
# the cores were packaged with System Generator 2018.2
foreach ip $spec_ips {
    if {[get_property UPGRADE_VERSIONS $ip] ne "" || [get_property IS_LOCKED $ip]} {
        catch {upgrade_ip $ip}
    }
}
generate_target all $spec_ips
