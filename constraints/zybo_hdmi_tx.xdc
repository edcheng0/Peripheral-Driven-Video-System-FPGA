# Zybo Z7-20 HDMI TX (J? "HDMI OUT") - TMDS lanes wired straight to bank 35 FPGA pins.
# Lane order follows Digilent: [0]=blue, [1]=green, [2]=red, plus the clock pair.
# HPD / DDC / CEC pins exist (E18, G17, G18, E19) but this design leaves them unused.
# Source: Digilent "Zybo-Z7-Master.xdc" (github.com/Digilent/digilent-xdc), fetched 2026-11-04.
# Pin names/numbers copied from that file; comments here are on their own lines (Tcl rule).
set_property -dict { PACKAGE_PIN H16 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_p }]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_n }]
set_property -dict { PACKAGE_PIN D19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[0] }]
set_property -dict { PACKAGE_PIN D20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[0] }]
set_property -dict { PACKAGE_PIN C20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[1] }]
set_property -dict { PACKAGE_PIN B20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[1] }]
set_property -dict { PACKAGE_PIN B19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[2] }]
set_property -dict { PACKAGE_PIN A20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[2] }]
