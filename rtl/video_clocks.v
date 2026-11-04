`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// video_clocks.v - makes the video clocks from the Zybo Z7-20's 125 MHz clock.
//
// Why we need it: a DVI/HDMI picture needs a "pixel clock" (one tick per
// pixel) and a much faster "serial clock" that shifts the 10 bits of each
// pixel out one at a time. The serial clock must be EXACTLY 5x the pixel
// clock (the serializers send 2 bits per serial tick = 10 bits per pixel).
//
// How: an MMCM is a Xilinx clock generator. It multiplies the input clock
// up to a fast internal "VCO" clock, then divides that down to the outputs.
// Because both outputs come from the same VCO with whole-number dividers,
// their 5:1 ratio is exact and their edges stay aligned.
//
//   125 MHz / DIVCLK_DIVIDE(5) = 25 MHz, x 25.25 = VCO = 631.25 MHz
//   (legal VCO range for a -1 Zynq-7000 part: 600-1200 MHz)
//   clk_serial = VCO / 5        = 126.25 MHz
//   clk_pixel  = VCO / 25       =  25.25  MHz  (standard is 25.175; monitors
//                                               accept the 0.3% difference)
//
// "locked" goes high once the MMCM output is stable. Keep everything else
// in reset until then.
//
// This is a thin wrapper around Xilinx primitives, so it can only be
// simulated in Vivado xsim (with the unisim library), not Icarus.
// ----------------------------------------------------------------------
module video_clocks #(
    // Defaults make 25.25 MHz pixel + 126.25 MHz serial from 125 MHz.
    parameter real  CLKIN_PERIOD     = 8.000,  // ns (125 MHz sysclk)
    parameter       DIVCLK_DIVIDE    = 5,
    parameter real  CLKFBOUT_MULT_F  = 25.25,
    parameter real  SERIAL_DIVIDE_F  = 5.0,    // VCO / this = serial clock
    parameter       PIXEL_DIVIDE     = 25      // VCO / this = pixel clock (must be 5x SERIAL_DIVIDE_F)
) (
    input  wire clk_in,      // 125 MHz
    input  wire rst,         // active-high reset
    output wire clk_pixel,   // ~25.25 MHz (through a global clock buffer)
    output wire clk_serial,  // ~126.25 MHz (5x pixel, through a global buffer)
    output wire locked
);

    wire clkfb, clkfb_buf;
    wire clk_serial_unbuf, clk_pixel_unbuf;

    MMCME2_BASE #(
        .CLKIN1_PERIOD    (CLKIN_PERIOD),
        .DIVCLK_DIVIDE    (DIVCLK_DIVIDE),
        .CLKFBOUT_MULT_F  (CLKFBOUT_MULT_F),
        .CLKOUT0_DIVIDE_F (SERIAL_DIVIDE_F),
        .CLKOUT1_DIVIDE   (PIXEL_DIVIDE)
    ) mmcm (
        .CLKIN1   (clk_in),
        .CLKFBIN  (clkfb_buf),
        .CLKFBOUT (clkfb),
        .CLKOUT0  (clk_serial_unbuf),
        .CLKOUT1  (clk_pixel_unbuf),
        .LOCKED   (locked),
        .PWRDWN   (1'b0),
        .RST      (rst),
        // unused outputs
        .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );

    // Global clock buffers spread each clock across the chip with low skew.
    BUFG bufg_fb     (.I(clkfb),            .O(clkfb_buf));
    BUFG bufg_serial (.I(clk_serial_unbuf), .O(clk_serial));
    BUFG bufg_pixel  (.I(clk_pixel_unbuf),  .O(clk_pixel));

endmodule
