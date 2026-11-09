# ----------------------------------------------------------------------
# run_ps_hello.tcl - load and start the ARM hello-world over JTAG (volatile).
#   xsdb scripts/run_ps_hello.tcl
# Open a serial terminal (115200 baud, 8N1) on the Zybo's UART COM port to
# see the text. Board must be powered with the PROG/UART USB cable attached.
# ----------------------------------------------------------------------
set ws build/vitis_ws
connect
targets -set -nocase -filter {name =~ "ARM*#0"}
rst -system
after 1000
targets -set -nocase -filter {name =~ "ARM*#0"}
source $ws/hello/_ide/psinit/ps7_init.tcl
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "ARM*#0"}
dow $ws/hello/build/hello.elf
con
puts "RUNNING: hello.elf started on ARM core 0"
after 3000
disconnect
