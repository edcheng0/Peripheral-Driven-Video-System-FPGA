# ----------------------------------------------------------------------
# make_system.tcl - ARM + camera video pipeline in one design.
#
#   Zynq ARM (PS) --AXI--> AXI GPIO (2 bits) --> filter mode of top_camera_dvi
#   top_camera_dvi (our Verilog) = camera -> filter -> frame buffer -> HDMI
#
# The ARM software writes 0..3 to the GPIO: 0 raw, 1 gray, 2 Sobel edges,
# 3 invert. The board's slide switches are not used in this design.
#
# Needs Digilent's board files (see make_ps_hello.tcl for how to get them).
# Run from the repo root:
#   vivado -mode batch -nojournal -nolog -source scripts/make_system.tcl
# Output: build/system/system.xsa (+ bitstream inside build/system/system.runs)
# ----------------------------------------------------------------------
if {[info exists ::env(BOARD_REPO)]} { set repo $::env(BOARD_REPO) } else { set repo "C:/Users/evan/vivado-boards/board_files" }
set_param board.repoPaths [list $repo]

create_project -force system build/system -part xc7z020clg400-1
set_property board_part digilentinc.com:zybo-z7-20:part0:1.2 [current_project]

# our Verilog and constraints
add_files [glob rtl/*.v]
add_files -fileset constrs_1 [list \
    constraints/zybo_clock.xdc constraints/zybo_hdmi_tx.xdc constraints/zybo_leds.xdc \
    constraints/zybo_camera_pmod.xdc constraints/zybo_ps_clocks.xdc]
update_compile_order -fileset sources_1

# ---- block design ----
create_bd_design system
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
    [get_bd_cells ps7]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_0
set_property -dict [list CONFIG.C_GPIO_WIDTH {2} CONFIG.C_ALL_OUTPUTS {1}] [get_bd_cells axi_gpio_0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/ps7/M_AXI_GP0} Slave {/axi_gpio_0/S_AXI} intc_ip {New AXI Interconnect} master_apply_board_params {1}} \
    [get_bd_intf_pins axi_gpio_0/S_AXI]

# our video design as a module inside the block design
create_bd_cell -type module -reference top_camera_dvi cam_sys

# filter mode = {2'b00, gpio[1:0]} into the video design's sw[3:0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant const0
set_property -dict [list CONFIG.CONST_WIDTH {2} CONFIG.CONST_VAL {0}] [get_bd_cells const0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat concat_sw
set_property -dict [list CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {2} CONFIG.IN1_WIDTH {2}] [get_bd_cells concat_sw]
connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_pins concat_sw/In0]
connect_bd_net [get_bd_pins const0/dout]          [get_bd_pins concat_sw/In1]
connect_bd_net [get_bd_pins concat_sw/dout]       [get_bd_pins cam_sys/sw]

# external ports (same names as the XDC files use)
create_bd_port -dir I -type clk -freq_hz 125000000 sysclk
connect_bd_net [get_bd_ports sysclk] [get_bd_pins cam_sys/sysclk]
create_bd_port -dir O -from 3 -to 0 led;          connect_bd_net [get_bd_pins cam_sys/led]       [get_bd_ports led]
create_bd_port -dir O hdmi_tx_clk_p;              connect_bd_net [get_bd_pins cam_sys/hdmi_tx_clk_p] [get_bd_ports hdmi_tx_clk_p]
create_bd_port -dir O hdmi_tx_clk_n;              connect_bd_net [get_bd_pins cam_sys/hdmi_tx_clk_n] [get_bd_ports hdmi_tx_clk_n]
create_bd_port -dir O -from 2 -to 0 hdmi_tx_p;    connect_bd_net [get_bd_pins cam_sys/hdmi_tx_p] [get_bd_ports hdmi_tx_p]
create_bd_port -dir O -from 2 -to 0 hdmi_tx_n;    connect_bd_net [get_bd_pins cam_sys/hdmi_tx_n] [get_bd_ports hdmi_tx_n]
create_bd_port -dir I -from 7 -to 0 cam_d;        connect_bd_net [get_bd_ports cam_d] [get_bd_pins cam_sys/cam_d]
create_bd_port -dir I cam_pclk;                   connect_bd_net [get_bd_ports cam_pclk]  [get_bd_pins cam_sys/cam_pclk]
create_bd_port -dir I cam_vsync;                  connect_bd_net [get_bd_ports cam_vsync] [get_bd_pins cam_sys/cam_vsync]
create_bd_port -dir I cam_href;                   connect_bd_net [get_bd_ports cam_href]  [get_bd_pins cam_sys/cam_href]
create_bd_port -dir O cam_xclk;                   connect_bd_net [get_bd_pins cam_sys/cam_xclk]    [get_bd_ports cam_xclk]
create_bd_port -dir O cam_reset_n;                connect_bd_net [get_bd_pins cam_sys/cam_reset_n] [get_bd_ports cam_reset_n]
create_bd_port -dir O cam_pwdn;                   connect_bd_net [get_bd_pins cam_sys/cam_pwdn]    [get_bd_ports cam_pwdn]
create_bd_port -dir O cam_sioc;                   connect_bd_net [get_bd_pins cam_sys/cam_sioc]    [get_bd_ports cam_sioc]
create_bd_port -dir IO cam_siod;                  connect_bd_net [get_bd_pins cam_sys/cam_siod]    [get_bd_ports cam_siod]

assign_bd_address
validate_bd_design
save_bd_design

set wrapper [make_wrapper -files [get_files system.bd] -top]
add_files -norecurse $wrapper
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_timing_summary -file build/system/timing_summary.rpt
report_drc            -file build/system/drc.rpt
report_utilization    -file build/system/utilization_impl.rpt
write_hw_platform -fixed -include_bit -force build/system/system.xsa
puts "SYSTEM BUILD OK: build/system/system.xsa"
