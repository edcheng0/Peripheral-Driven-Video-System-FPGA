# ----------------------------------------------------------------------
# run_eth.tcl - load the DDR3 frame-buffer design and the Ethernet version of the ARM
# program over JTAG (volatile).   xsdb scripts/run_eth.tcl
# The program prints VDMA status every 2 s on the UART (115200, 8N1).
# ----------------------------------------------------------------------
set bit build/ddr_system/ddr_system.runs/impl_1/system_wrapper.bit
set elf build/vitis_eth/eth.elf
set psinit build/vitis_eth/ps7_init.tcl

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
puts "RUNNING: bitstream loaded, Ethernet program started"
after 2000
disconnect
