# ----------------------------------------------------------------------
# make_ps_hello.tcl - builds a minimal Zynq design: just the ARM processor
# (PS) with the Zybo Z7-20 board preset (DDR3, UART, etc.) and exports the
# hardware description (.xsa) that Vitis needs to build ARM software.
#
# Needs Digilent's board files (not part of Vivado). Get them once with:
#   git clone https://github.com/Digilent/vivado-boards.git
# and point BOARD_REPO at   <clone>/new/board_files   (or copy that folder to
# the default path below).
#
# Run from the repo root:
#   vivado -mode batch -nojournal -nolog -source scripts/make_ps_hello.tcl
# Output: build/ps_hello/ps_hello.xsa
# ----------------------------------------------------------------------
if {[info exists ::env(BOARD_REPO)]} { set repo $::env(BOARD_REPO) } else { set repo "C:/Users/evan/vivado-boards/board_files" }
set_param board.repoPaths [list $repo]

create_project -force ps_hello build/ps_hello -part xc7z020clg400-1
set_property board_part digilentinc.com:zybo-z7-20:part0:1.2 [current_project]

create_bd_design ps_system
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
    [get_bd_cells ps7]
# the PS's AXI master port needs a clock; use the PS's own FCLK_CLK0
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
validate_bd_design
save_bd_design

set wrapper [make_wrapper -files [get_files ps_system.bd] -top]
add_files -norecurse $wrapper
set_property top ps_system_wrapper [current_fileset]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
write_hw_platform -fixed -include_bit -force build/ps_hello/ps_hello.xsa
puts "PS BUILD OK: build/ps_hello/ps_hello.xsa"
