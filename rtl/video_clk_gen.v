`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// video_clk_gen.v - video_clocks with only simple ports.
// Vivado's block designer cannot use a module that has floating-point
// parameters (video_clocks does), so this thin wrapper hides them and ties
// the reset off. Pixel 25.25 MHz + serial 126.25 MHz from the 125 MHz clock.
// ----------------------------------------------------------------------
module video_clk_gen (
    input  wire sysclk,
    output wire clk_pixel,
    output wire clk_serial,
    output wire locked
);
    video_clocks u_clocks (
        .clk_in(sysclk), .rst(1'b0),
        .clk_pixel(clk_pixel), .clk_serial(clk_serial), .locked(locked)
    );
endmodule
