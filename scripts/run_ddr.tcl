# ----------------------------------------------------------------------
# run_ddr.tcl - load the DDR3 frame-buffer design and the VDMA setup
# program over JTAG (volatile).   xsdb scripts/run_ddr.tcl
# The program prints VDMA status every 2 s on the UART (115200, 8N1).
# ----------------------------------------------------------------------
set bit build/ddr_system/ddr_system.runs/impl_1/system_wrapper.bit
set elf build/vitis_ddr/ddr/build/ddr.elf
set psinit build/vitis_ddr/ddr/_ide/psinit/ps7_init.tcl

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
puts "RUNNING: bitstream loaded, DDR frame buffer program started"
after 2000
disconnect
