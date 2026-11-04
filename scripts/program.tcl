# ----------------------------------------------------------------------
# program.tcl - load a bitstream onto the board over JTAG (volatile; lost
# on power-cycle). Zybo Z7-20: power and JTAG both come over the PROG/UART
# micro-USB port (boot-mode jumper JP5 to JTAG; confirm in the Zybo Z7 reference manual).
#
# Usage: vivado -mode batch -nojournal -nolog -source scripts/program.tcl \
#               -tclargs build/top_phase0/top_phase0.bit
# ----------------------------------------------------------------------
set bit [lindex $argv 0]
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED: $bit"
close_hw_manager
