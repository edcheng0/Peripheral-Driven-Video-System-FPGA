# Clock relationships for designs that include the Zynq ARM (PS).
# The PS makes its own clock for the AXI bus (clk_fpga_0). It is unrelated to
# the 125 MHz board clock, its derived video clocks, and the camera pixel clock.
# The only signal crossing from it is the 2-bit filter mode, which goes through a
# 2-flop synchronizer in the camera clock domain.
set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_fpga_0] \
    -group [get_clocks -quiet cam_pclk] \
    -group [get_clocks -quiet -include_generated_clocks sys_clk_pin]
