# Zybo Z7-20 slide switches SW0..SW3.
# Source: Digilent "Zybo-Z7-Master.xdc" (github.com/Digilent/digilent-xdc), fetched 2026-11-04.
# Pin names/numbers copied from that file; comments here are on their own lines (Tcl rule).
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]
