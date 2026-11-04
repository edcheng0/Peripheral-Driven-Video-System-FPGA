# ----------------------------------------------------------------------
# build.tcl - Vivado NON-PROJECT batch build (synth -> impl -> bitstream)
#
# Usage (from project root, in a terminal where `vivado` is on PATH):
#   vivado -mode batch -nojournal -nolog -source scripts/build.tcl \
#          -tclargs <top_module> <xdc1> [xdc2 ...]
#
# Examples:
#   Bring-up: -tclargs top_zybo_bringup zybo_clock.xdc zybo_leds.xdc zybo_switches.xdc zybo_buttons.xdc
#   Colors:   -tclargs top_phase1_dvi zybo_clock.xdc zybo_hdmi_tx.xdc
#   Camera:   -tclargs top_camera_dvi zybo_clock.xdc zybo_hdmi_tx.xdc zybo_leds.xdc zybo_switches.xdc zybo_camera_pmod.xdc
#
# XDC names are looked up in constraints/. Only pass the XDC files that
# match the chosen top module (see "Build and run" in README.md).
#
# Outputs: build/<top>/<top>.bit plus timing/utilization/DRC reports.
# ----------------------------------------------------------------------

if {[llength $argv] < 2} {
    puts "ERROR: usage: -tclargs <top_module> <xdc1> \[xdc2 ...\]"
    exit 1
}

set top  [lindex $argv 0]
set xdcs [lrange $argv 1 end]
set part xc7z020clg400-1
set out  build/$top
file mkdir $out

# Read all RTL; synth_design only elaborates modules reachable from -top.
foreach f [glob rtl/*.v] { read_verilog $f }
foreach x $xdcs { read_xdc constraints/$x }

synth_design -top $top -part $part
write_checkpoint -force $out/post_synth.dcp
report_utilization -file $out/utilization_synth.rpt

opt_design
place_design
route_design
write_checkpoint -force $out/post_route.dcp

report_timing_summary -file $out/timing_summary.rpt
report_utilization    -file $out/utilization_impl.rpt
report_drc            -file $out/drc.rpt
report_io             -file $out/io.rpt

write_bitstream -force $out/$top.bit
puts "BUILD OK: $out/$top.bit"
