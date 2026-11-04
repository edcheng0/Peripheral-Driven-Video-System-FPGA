`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// pixel_reader.v - reads the frame buffer in step with the video timing.
//
// The display runs at (SRC_W << SHIFT) x (SRC_H << SHIFT) pixels, e.g.
// 640x480, but the stored image is smaller, e.g. 320x240. To fill the
// screen we show each stored pixel 2x2 times ("nearest-neighbour
// upscale"): stored pixel = (screen_x >> 1, screen_y >> 1).
//
// TIMING: the frame buffer's read is synchronous (data arrives 1 clock
// after the address). So this module delays hsync/vsync/de by one clock
// to stay lined up with the pixel data, and converts the stored RGB565
// into 8-bit-per-channel RGB for the TMDS encoders.
//
// The caller wires:  addr  -> frame_buffer.raddr
//                    rdata <- frame_buffer.rdata
// ----------------------------------------------------------------------
module pixel_reader #(
    parameter SRC_W  = 320,
    parameter SRC_H  = 240,
    parameter SHIFT  = 1,                       // upscale = 1<<SHIFT
    parameter CNT_W  = 10,                      // width of pixel_x / pixel_y
    parameter ADDR_W = $clog2(SRC_W * SRC_H)
) (
    input  wire              clk_pixel,
    // from video_timing_gen
    input  wire              hsync_in,
    input  wire              vsync_in,
    input  wire              de_in,
    input  wire [CNT_W-1:0]  pixel_x,
    input  wire [CNT_W-1:0]  pixel_y,
    // frame buffer
    output wire [ADDR_W-1:0] addr,
    input  wire [15:0]       rdata,
    // to the TMDS lanes (aligned with each other)
    output reg               hsync_out,
    output reg               vsync_out,
    output reg               de_out,
    output wire [7:0]        red,
    output wire [7:0]        green,
    output wire [7:0]        blue
);

    wire [CNT_W-1:0] sx = pixel_x >> SHIFT;
    wire [CNT_W-1:0] sy = pixel_y >> SHIFT;

    // outside the visible area read address 0 (value is ignored then)
    assign addr = de_in ? (sy * SRC_W + sx) : {ADDR_W{1'b0}};

    always @(posedge clk_pixel) begin
        hsync_out <= hsync_in;
        vsync_out <= vsync_in;
        de_out    <= de_in;
    end

    // RGB565 -> RGB888 by replicating the top bits into the low bits
    assign red   = de_out ? {rdata[15:11], rdata[15:13]} : 8'h00;
    assign green = de_out ? {rdata[10:5],  rdata[10:9]}  : 8'h00;
    assign blue  = de_out ? {rdata[4:0],   rdata[4:2]}   : 8'h00;

endmodule
