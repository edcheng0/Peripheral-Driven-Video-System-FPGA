`timescale 1ns / 1ps
//------------------------------------------------------------------------
// colorbar_gen.v
//
// Classic vertical color bar test pattern - the same one used to test
// broadcast video equipment for decades. Splits the visible width into
// 8 equal vertical stripes, each a different color.
//
// This module is purely combinational (no clock needed) - given an x
// coordinate, it immediately outputs what color that pixel should be.
// It doesn't know about timing at all; video_timing_gen handles that
// separately. This separation (timing vs. content) is a very common,
// reusable pattern in video pipelines - later, this module gets
// swapped out for "whatever the camera captured" instead of bars.
//------------------------------------------------------------------------
module colorbar_gen #(
    parameter CNT_W     = 10,   // width of pixel_x
    parameter BAR_WIDTH = 80    // visible width / 8 (640 -> 80)
) (
    input  wire [CNT_W-1:0] pixel_x,   // current pixel's horizontal position (0-639)
    output reg  [7:0] red,
    output reg  [7:0] green,
    output reg  [7:0] blue
);

    // 640 pixels wide / 8 bars = 80 pixels per bar

    always @(*) begin
        case (pixel_x / BAR_WIDTH)
            0: begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end // white
            1: begin red = 8'hFF; green = 8'hFF; blue = 8'h00; end // yellow
            2: begin red = 8'h00; green = 8'hFF; blue = 8'hFF; end // cyan
            3: begin red = 8'h00; green = 8'hFF; blue = 8'h00; end // green
            4: begin red = 8'hFF; green = 8'h00; blue = 8'hFF; end // magenta
            5: begin red = 8'hFF; green = 8'h00; blue = 8'h00; end // red
            6: begin red = 8'h00; green = 8'h00; blue = 8'hFF; end // blue
            default: begin red = 8'h00; green = 8'h00; blue = 8'h00; end // black
        endcase
    end

endmodule
