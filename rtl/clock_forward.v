`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// clock_forward.v - send a clock OUT of the chip on a normal pin.
//
// You should not just wire a clock net to an output pin: it goes through
// ordinary routing and picks up jitter. The standard trick is an ODDR
// (double-data-rate output flip-flop) fed with constants 1 and 0, so its
// output toggles with the clock edges themselves. Used to give the OV7670
// its XCLK from the pixel clock.
// Thin wrapper around a Xilinx primitive: only simulatable in xsim.
// ----------------------------------------------------------------------
module clock_forward (
    input  wire clk,
    output wire clk_out
);
    ODDR #(.DDR_CLK_EDGE("OPPOSITE_EDGE"), .INIT(1'b0), .SRTYPE("SYNC")) u_oddr (
        .Q(clk_out), .C(clk), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0)
    );
endmodule
