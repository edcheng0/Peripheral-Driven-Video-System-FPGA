# OV7670 camera on Zybo Z7-20 Pmod headers JC (8 data bits) and JD (control).
# Pmod pin numbers and FPGA pins checked against the Digilent Zybo Z7 reference
# manual Pmod table (verified by Evan, 2026-11-06). Pmod pins: 1-4 top row,
# 7-10 bottom row, 5 and 11 = GND, 6 and 12 = 3.3 V. Banks are 3.3 V.
#
#   camera pin  signal        Zybo Pmod pin   FPGA pin
#   D0..D7      cam_d[0..7]   JC 1,2,3,4,7,8,9,10   V15 W15 T11 T10 W14 Y14 T12 U12
#   VS          cam_vsync     JD 1            T14
#   HS          cam_href      JD 2            T15
#   MCLK        cam_xclk      JD 3            P14   (FPGA -> camera clock)
#   RET         cam_reset_n   JD 4            R14
#   PCLK        cam_pclk      JD 7            U14   (clock-capable pin)
#   PWDN        cam_pwdn      JD 8            U15
#   SCL         cam_sioc      JD 9            V17
#   SDA         cam_siod      JD 10           V18
#   3V3         -             JD 6  (3.3 V)
#   GND         -             JD 5  (GND)
#
# Camera module logic voltage still to be confirmed from its datasheet.
# Source of FPGA pin names: Digilent "Zybo-Z7-Master.xdc".
#
# Pin assignments and timing constraints
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { cam_d[0] }]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports { cam_d[1] }]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { cam_d[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { cam_d[3] }]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports { cam_d[4] }]
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports { cam_d[5] }]
set_property -dict { PACKAGE_PIN T12 IOSTANDARD LVCMOS33 } [get_ports { cam_d[6] }]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports { cam_d[7] }]
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { cam_vsync }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { cam_href }]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { cam_xclk }]
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports { cam_reset_n }]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { cam_pclk }]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports { cam_pwdn }]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { cam_sioc }]
set_property -dict { PACKAGE_PIN V18 IOSTANDARD LVCMOS33 } [get_ports { cam_siod }]

# SCCB data is open-drain (FPGA only pulls low): keep a weak pull-up as a backup
# to the pull-up that normally sits on the camera module.
set_property PULLUP true [get_ports { cam_siod }]

# Camera pixel clock. 39.6 ns = the fastest it can run here (XCLK 25.25 MHz,
# CLKRC divider 1 -> ~12.6 MHz in practice).
create_clock -name cam_pclk -period 39.600 [get_ports { cam_pclk }]

# Data changes after the FALLING edge of PCLK and is sampled on the rising
# edge. These numbers are a rough estimate (not from the datasheet) - tune.
set_input_delay -clock cam_pclk -max 35.0 [get_ports { cam_d[*] cam_vsync cam_href }]
set_input_delay -clock cam_pclk -min 15.0 [get_ports { cam_d[*] cam_vsync cam_href }]

# The camera clock domain and the board/video clock domains are unrelated;
# the only crossings are the mode switch (2-FF synchronizer) and the dual-clock
# frame buffer.
set_clock_groups -asynchronous     -group [get_clocks cam_pclk]     -group [get_clocks -include_generated_clocks sys_clk_pin]

# Unwired data pins read as 0 instead of floating (lets a partly wired camera still be tested).
# Harmless when the camera drives them.
set_property PULLDOWN true [get_ports { cam_d[*] }]
