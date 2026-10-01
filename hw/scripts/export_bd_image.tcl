# Export the Vivado block diagram as SVG/PDF (write_bd_layout needs GUI mode):
#   vivado -mode gui -source hw/scripts/export_bd_image.tcl
set here [file dirname [file normalize [info script]]]
set top  [file normalize $here/../..]
open_project $top/hw/build/vivado/lunaZCU111.xpr
open_bd_design [get_files system.bd]
file mkdir $top/docs
write_bd_layout -force -format svg -orientation landscape -file $top/docs/vivado_bd.svg
write_bd_layout -force -format pdf -orientation landscape -file $top/docs/vivado_bd.pdf
exit
