# Zybo Z7-20 125 MHz system clock (always on, from the ethernet PHY oscillator).
# Source: Digilent "Zybo-Z7-Master.xdc" (github.com/Digilent/digilent-xdc), fetched 2026-11-04.
# Pin names/numbers copied from that file; comments here are on their own lines (Tcl rule).
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports { sysclk }]
create_clock -add -name sys_clk_pin -period 8.000 -waveform {0 4} [get_ports { sysclk }]
