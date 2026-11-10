# ----------------------------------------------------------------------
# make_ddr_system.tcl - camera -> DDR3 frame buffer -> HDMI (640x480).
#
#   OV7670 --pins--> cam_axis_src --AXI4-Stream--> VDMA (write) --> DDR3
#   DDR3 --> VDMA (read) --AXI4-Stream--> video_sink --> HDMI pins
#   ARM (PS) configures the VDMA over AXI-Lite and owns the DDR3.
#
# The VDMA is Xilinx's video DMA block: it moves whole frames between a
# stream and memory without the processor touching the pixels.
# Frame store: 1 buffer, no genlock (simple; the picture can tear slightly).
#
# Needs Digilent's board files (see make_ps_hello.tcl).
# Run from the repo root:
#   vivado -mode batch -nojournal -nolog -source scripts/make_ddr_system.tcl
# Output: build/ddr_system/ddr_system.xsa
# ----------------------------------------------------------------------
if {[info exists ::env(BOARD_REPO)]} { set repo $::env(BOARD_REPO) } else { set repo "C:/Users/evan/vivado-boards/board_files" }
set_param board.repoPaths [list $repo]

create_project -force ddr_system build/ddr_system -part xc7z020clg400-1
set_property board_part digilentinc.com:zybo-z7-20:part0:1.2 [current_project]

add_files [glob rtl/*.v]
add_files -fileset constrs_1 [list \
    constraints/zybo_clock.xdc constraints/zybo_hdmi_tx.xdc constraints/zybo_leds.xdc \
    constraints/zybo_camera_pmod.xdc constraints/zybo_ps_clocks.xdc]
update_compile_order -fileset sources_1

create_bd_design system

# ---- ARM processor with the Zybo preset; enable a 64-bit memory port (HP0) ----
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
    [get_bd_cells ps7]
set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {1}] [get_bd_cells ps7]

# ---- video DMA: 16-bit RGB565 streams, 64-bit memory side, one frame store ----
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma axi_vdma_0
set_property -dict [list \
    CONFIG.c_num_fstores {1} \
    CONFIG.c_include_internal_genlock {0} \
    CONFIG.c_m_axis_mm2s_tdata_width {16} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_mm2s_max_burst_length {16} \
    CONFIG.c_s2mm_max_burst_length {16}] [get_bd_cells axi_vdma_0]

# ARM -> VDMA control registers (AXI-Lite); this also creates the 100 MHz clock/reset wiring
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/ps7/M_AXI_GP0} Slave {/axi_vdma_0/S_AXI_LITE} intc_ip {New AXI Interconnect} master_apply_board_params {1}} \
    [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]

# ARM -> 2-bit GPIO that picks the display filter
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_0
set_property -dict [list CONFIG.C_GPIO_WIDTH {6} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {10} CONFIG.C_ALL_INPUTS_2 {1}] [get_bd_cells axi_gpio_0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/ps7/M_AXI_GP0} Slave {/axi_gpio_0/S_AXI} intc_ip {/ps7_axi_periph} master_apply_board_params {1}} \
    [get_bd_intf_pins axi_gpio_0/S_AXI]

# debug: second GPIO (inputs only) carries the camera/DMA counters from cam_stats
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_1
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_INPUTS_2 {1}] [get_bd_cells axi_gpio_1]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/ps7/M_AXI_GP0} Slave {/axi_gpio_1/S_AXI} intc_ip {/ps7_axi_periph} master_apply_board_params {1}} \
    [get_bd_intf_pins axi_gpio_1/S_AXI]

# find the 100 MHz reset the automation made
set rst100 [get_bd_cells -hier -filter {VLNV =~ "xilinx.com:ip:proc_sys_reset:*"}]
set rst100 [lindex $rst100 0]
puts "100 MHz reset block: $rst100"

# VDMA -> DDR3 memory path through an interconnect into HP0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect mem_ic
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells mem_ic]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_MM2S] [get_bd_intf_pins mem_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] [get_bd_intf_pins mem_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins mem_ic/M00_AXI]        [get_bd_intf_pins ps7/S_AXI_HP0]
foreach p {ACLK S00_ACLK S01_ACLK M00_ACLK} {
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins mem_ic/$p]
}
foreach p {ARESETN S00_ARESETN S01_ARESETN M00_ARESETN} {
    connect_bd_net [get_bd_pins $rst100/peripheral_aresetn] [get_bd_pins mem_ic/$p]
}
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_vdma_0/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_vdma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/S_AXI_HP0_ACLK]

# ---- our video blocks (plain Verilog, added as module references) ----
create_bd_cell -type module -reference video_clk_gen clk_gen
create_bd_cell -type module -reference cam_ctrl     cam_ctrl
create_bd_cell -type module -reference cam_axis_src cam_src
create_bd_cell -type module -reference video_sink   vid_sink


# clocks: 125 MHz in -> pixel (25.25 MHz) and serial (5x)
create_bd_port -dir I -type clk -freq_hz 125000000 sysclk
connect_bd_net [get_bd_ports sysclk] [get_bd_pins clk_gen/sysclk]
connect_bd_net [get_bd_ports sysclk] [get_bd_pins cam_ctrl/sysclk]
connect_bd_net [get_bd_pins clk_gen/clk_pixel]  [get_bd_pins vid_sink/s_axis_aclk]
connect_bd_net [get_bd_pins clk_gen/clk_pixel]  [get_bd_pins cam_ctrl/clk_pixel]
connect_bd_net [get_bd_pins clk_gen/clk_pixel]  [get_bd_pins axi_vdma_0/m_axis_mm2s_aclk]
connect_bd_net [get_bd_pins clk_gen/clk_serial] [get_bd_pins vid_sink/clk_serial]
connect_bd_net [get_bd_pins clk_gen/locked]     [get_bd_pins vid_sink/locked]
connect_bd_net [get_bd_pins clk_gen/locked]     [get_bd_pins cam_ctrl/locked]
# GPIO out: bits 1:0 = display filter, bit 2 = camera re-init; GPIO in: camera status
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice slice_mode
set_property -dict [list CONFIG.DIN_WIDTH {6} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {2}] [get_bd_cells slice_mode]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice slice_reinit
set_property -dict [list CONFIG.DIN_WIDTH {6} CONFIG.DIN_FROM {2} CONFIG.DIN_TO {2} CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_reinit]
connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_pins slice_mode/Din]
connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_pins slice_reinit/Din]
connect_bd_net [get_bd_pins slice_mode/Dout]   [get_bd_pins vid_sink/mode]
connect_bd_net [get_bd_pins slice_reinit/Dout] [get_bd_pins cam_ctrl/reinit]
foreach {nm bit pin} {slice_own 3 arm_own slice_scl 4 arm_scl_low slice_sda 5 arm_sda_low} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice $nm
    set_property -dict [list CONFIG.DIN_WIDTH {6} CONFIG.DIN_FROM $bit CONFIG.DIN_TO $bit CONFIG.DOUT_WIDTH {1}] [get_bd_cells $nm]
    connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_pins $nm/Din]
    connect_bd_net [get_bd_pins $nm/Dout] [get_bd_pins cam_ctrl/$pin]
}
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat concat_stat
set_property -dict [list CONFIG.NUM_PORTS {3} CONFIG.IN0_WIDTH {8} CONFIG.IN1_WIDTH {1} CONFIG.IN2_WIDTH {1}] [get_bd_cells concat_stat]
connect_bd_net [get_bd_pins cam_ctrl/ack_errs]  [get_bd_pins concat_stat/In0]
connect_bd_net [get_bd_pins cam_ctrl/init_done] [get_bd_pins concat_stat/In1]
connect_bd_net [get_bd_pins cam_ctrl/sda_in]    [get_bd_pins concat_stat/In2]
connect_bd_net [get_bd_pins concat_stat/dout]   [get_bd_pins axi_gpio_0/gpio2_io_i]

# the camera's own pixel clock drives the write-side stream

connect_bd_net [get_bd_pins cam_src/stat_a] [get_bd_pins axi_gpio_1/gpio_io_i]
connect_bd_net [get_bd_pins cam_src/stat_b] [get_bd_pins axi_gpio_1/gpio2_io_i]

# the two video streams
# a stream FIFO between the camera and the DMA: the camera cannot be paused, so any
# short stall in the DMA would otherwise lose pixels. Camera clock in, 100 MHz out.
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo cam_fifo
set_property -dict [list CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {4096} CONFIG.TDATA_NUM_BYTES {2} \
    CONFIG.HAS_TLAST {1} CONFIG.TUSER_WIDTH {1}] [get_bd_cells cam_fifo]
connect_bd_net [get_bd_pins cam_src/m_axis_aclk] [get_bd_pins cam_fifo/s_axis_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0]       [get_bd_pins cam_fifo/m_axis_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0]       [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk]
connect_bd_net [get_bd_pins $rst100/peripheral_aresetn] [get_bd_pins cam_fifo/s_axis_aresetn]
connect_bd_intf_net [get_bd_intf_pins cam_src/m_axis]      [get_bd_intf_pins cam_fifo/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins cam_fifo/M_AXIS]     [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXIS_MM2S] [get_bd_intf_pins vid_sink/s_axis]

# ---- external pins (names match the XDC files) ----
create_bd_port -dir O -from 3 -to 0 led
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat concat_led
set_property -dict [list CONFIG.NUM_PORTS {4}] [get_bd_cells concat_led]
connect_bd_net [get_bd_pins clk_gen/locked]            [get_bd_pins concat_led/In0]
connect_bd_net [get_bd_pins cam_ctrl/init_done]        [get_bd_pins concat_led/In1]
connect_bd_net [get_bd_pins cam_src/frame_toggle]      [get_bd_pins concat_led/In2]
connect_bd_net [get_bd_pins vid_sink/disp_frame_toggle] [get_bd_pins concat_led/In3]
connect_bd_net [get_bd_pins concat_led/dout] [get_bd_ports led]

create_bd_port -dir O hdmi_tx_clk_p;           connect_bd_net [get_bd_pins vid_sink/hdmi_tx_clk_p] [get_bd_ports hdmi_tx_clk_p]
create_bd_port -dir O hdmi_tx_clk_n;           connect_bd_net [get_bd_pins vid_sink/hdmi_tx_clk_n] [get_bd_ports hdmi_tx_clk_n]
create_bd_port -dir O -from 2 -to 0 hdmi_tx_p; connect_bd_net [get_bd_pins vid_sink/hdmi_tx_p] [get_bd_ports hdmi_tx_p]
create_bd_port -dir O -from 2 -to 0 hdmi_tx_n; connect_bd_net [get_bd_pins vid_sink/hdmi_tx_n] [get_bd_ports hdmi_tx_n]

create_bd_port -dir I -from 7 -to 0 cam_d;     connect_bd_net [get_bd_ports cam_d]     [get_bd_pins cam_src/cam_d]
create_bd_port -dir I cam_pclk;                connect_bd_net [get_bd_ports cam_pclk]  [get_bd_pins cam_src/cam_pclk]
create_bd_port -dir I cam_vsync;               connect_bd_net [get_bd_ports cam_vsync] [get_bd_pins cam_src/cam_vsync]
create_bd_port -dir I cam_href;                connect_bd_net [get_bd_ports cam_href]  [get_bd_pins cam_src/cam_href]
create_bd_port -dir O cam_xclk;                connect_bd_net [get_bd_pins cam_ctrl/cam_xclk]    [get_bd_ports cam_xclk]
create_bd_port -dir O cam_reset_n;             connect_bd_net [get_bd_pins cam_ctrl/cam_reset_n] [get_bd_ports cam_reset_n]
create_bd_port -dir O cam_pwdn;                connect_bd_net [get_bd_pins cam_ctrl/cam_pwdn]    [get_bd_ports cam_pwdn]
create_bd_port -dir O cam_sioc;                connect_bd_net [get_bd_pins cam_ctrl/cam_sioc]    [get_bd_ports cam_sioc]
create_bd_port -dir IO cam_siod;               connect_bd_net [get_bd_pins cam_ctrl/cam_siod]    [get_bd_ports cam_siod]

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
report_timing_summary -file build/ddr_system/timing_summary.rpt
report_drc            -file build/ddr_system/drc.rpt
report_utilization    -file build/ddr_system/utilization_impl.rpt
write_hw_platform -fixed -include_bit -force build/ddr_system/ddr_system.xsa
puts "DDR SYSTEM BUILD OK: build/ddr_system/ddr_system.xsa"
