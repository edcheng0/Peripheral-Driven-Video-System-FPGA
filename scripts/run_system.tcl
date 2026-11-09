# ----------------------------------------------------------------------
# run_system.tcl - load the ARM + camera design and the filter-control
# program over JTAG (volatile).   xsdb scripts/run_system.tcl
# Then open a serial terminal (115200, 8N1) on the Zybo UART and type 0-3.
# ----------------------------------------------------------------------
set bit build/system/system.runs/impl_1/system_wrapper.bit
set elf build/vitis_mode/mode/build/mode.elf
set psinit build/vitis_mode/mode/_ide/psinit/ps7_init.tcl

connect
targets -set -nocase -filter {name =~ "ARM*#0"}
rst -system
after 1000
targets -set -nocase -filter {name =~ "ARM*#0"}
source $psinit
ps7_init
targets -set -nocase -filter {name =~ "xc7z*"}
fpga -file $bit
targets -set -nocase -filter {name =~ "ARM*#0"}
ps7_post_config
dow $elf
con
puts "RUNNING: bitstream loaded, mode control started"
after 2000
disconnect
