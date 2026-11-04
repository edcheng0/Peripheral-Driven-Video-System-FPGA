`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// rgb565_to_gray.v - convert a 16-bit RGB565 pixel to 8-bit brightness.
//
// Step 1: widen each color to 8 bits by copying its top bits into the
//         low bits (so full-scale 5-bit 11111 becomes 11111111, not
//         11111000 - white stays white).
// Step 2: weighted sum matching how bright each color looks to the eye
//         (the ITU-R BT.601 weights 0.299 R + 0.587 G + 0.114 B, scaled by
//         256 and rounded to whole numbers: 77 + 150 + 29 = 256):
//             gray = (77*R + 150*G + 29*B) >> 8
// Purely combinational (no clock).
// ----------------------------------------------------------------------
module rgb565_to_gray (
    input  wire [15:0] rgb565,
    output wire [7:0]  gray
);
    wire [7:0] r = {rgb565[15:11], rgb565[15:13]};
    wire [7:0] g = {rgb565[10:5],  rgb565[10:9]};
    wire [7:0] b = {rgb565[4:0],   rgb565[4:2]};
    wire [15:0] sum = 16'd77 * r + 16'd150 * g + 16'd29 * b;
    assign gray = sum[15:8];
endmodule
