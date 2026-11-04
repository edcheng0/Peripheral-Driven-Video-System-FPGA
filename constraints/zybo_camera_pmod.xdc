# OV7670 camera on Zybo Z7-20 Pmod headers JC (8 data bits) and JD (control).
# DRAFT wiring plan - nothing is plugged in yet; change freely before wiring.
# FPGA pins/banks come from Digilent's master XDC (all in bank 34, 3.3 V).
# Physical Pmod pin numbers (1-4 top row, 7-10 bottom row, 5/11 GND, 6/12 3V3)
# are NOT yet checked against the Zybo Z7 reference manual: do that before wiring.
#
#   header-name  FPGA  camera signal            header-name  FPGA  camera signal
#   jc[0]        V15   D0                       jd[0]        T14   VSYNC
#   jc[1]        W15   D1                       jd[1]        T15   HREF
#   jc[2]        T11   D2                       jd[2]        P14   XCLK (FPGA -> camera)
#   jc[3]        T10   D3                       jd[3]        R14   RESET# (FPGA -> camera)
#   jc[4]        W14   D4                       jd[4]        U14   PCLK (clock-capable pin)
#   jc[5]        Y14   D5                       jd[5]        U15   PWDN (FPGA -> camera)
#   jc[6]        T12   D6                       jd[6]        V17   SIOC (SCCB clock)
#   jc[7]        U12   D7                       jd[7]        V18   SIOD (SCCB data, open-drain)
#
# Camera module power: 3.3 V and GND from a Pmod power pin pair (check your
# breakout's voltage rating). Some OV7670 boards want 2.8 V logic - check.
# Source: Digilent "Zybo-Z7-Master.xdc" (github.com/Digilent/digilent-xdc), fetched 2026-11-04.
# Pin names/numbers copied from that file; comments here are on their own lines (Tcl rule).
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
