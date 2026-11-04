# Zybo Z7-20 user LEDs LD0..LD3 (direct FPGA pins, unlike the old carrier board!).
# Source: Digilent "Zybo-Z7-Master.xdc" (github.com/Digilent/digilent-xdc), fetched 2026-11-04.
# Pin names/numbers copied from that file; comments here are on their own lines (Tcl rule).
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]
