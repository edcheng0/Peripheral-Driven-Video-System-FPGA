`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// sobel_3x3.v - edge detector for a streaming 8-bit grayscale image.
//
// IDEA: an edge is a place where brightness changes quickly. The Sobel
// filter looks at a 3x3 neighborhood of pixels and measures the change
// left-to-right (Gx) and top-to-bottom (Gy):
//
//        Gx kernel        Gy kernel
//      -1  0 +1          -1 -2 -1
//      -2  0 +2           0  0  0
//      -1  0 +1          +1 +2 +1
//
//   strength = min(255, |Gx| + |Gy|)      (cheap stand-in for sqrt(Gx^2+Gy^2))
//
// HOW IT SEES 3 ROWS AT ONCE: pixels arrive one at a time in raster order
// (left to right, top to bottom). Two "line buffers" remember the last two
// rows. When pixel (c, r) arrives we also read (c, r-1) and (c, r-2) from
// those buffers, so we have one full column of 3 pixels. Three such columns
// side by side (kept in shift registers) form the 3x3 window.
//
// OUTPUT: one result per window, centered on pixel (c-1, r-1), i.e. only
// INTERIOR pixels get a result: x = 1..W-2, y = 1..H-2. The 1-pixel border
// of the image produces no output (documented limitation).
//
// Pixels may arrive with gaps (in_valid low). Pulse `sof` before each frame
// to restart the row/column counters.
// Latency: out_valid appears 2 clocks after the in_valid that completed
// the window.
// ----------------------------------------------------------------------
module sobel_3x3 #(
    parameter WIDTH = 320,
    parameter XW    = 9,
    parameter YW    = 8
) (
    input  wire          clk,
    input  wire          sof,        // start of frame: reset counters
    input  wire          in_valid,
    input  wire [7:0]    in_pixel,

    output reg           out_valid,
    output reg  [XW-1:0] out_x,
    output reg  [YW-1:0] out_y,
    output reg  [7:0]    out_mag
);

    // two line buffers (small enough for distributed RAM / registers)
    reg [7:0] lb1 [0:WIDTH-1];   // previous row
    reg [7:0] lb2 [0:WIDTH-1];   // row before that

    reg [XW-1:0] col = 0;
    reg [YW:0]   row = 0;

    // 3x3 window: [0]=oldest column (left) ... [2]=newest column (right)
    reg [7:0] top0 = 0, top1 = 0, top2 = 0;   // row r-2
    reg [7:0] mid0 = 0, mid1 = 0, mid2 = 0;   // row r-1
    reg [7:0] bot0 = 0, bot1 = 0, bot2 = 0;   // row r

    reg           win_valid = 1'b0;
    reg [XW-1:0]  win_x = 0;
    reg [YW-1:0]  win_y = 0;

    wire [7:0] from_lb2 = lb2[col];
    wire [7:0] from_lb1 = lb1[col];

    always @(posedge clk) begin
        win_valid <= 1'b0;

        if (sof) begin
            col <= 0;
            row <= 0;
        end else if (in_valid) begin
            lb2[col] <= from_lb1;
            lb1[col] <= in_pixel;

            top0 <= top1; top1 <= top2; top2 <= from_lb2;
            mid0 <= mid1; mid1 <= mid2; mid2 <= from_lb1;
            bot0 <= bot1; bot1 <= bot2; bot2 <= in_pixel;

            // the window including this pixel is complete when 3 columns
            // and 3 rows have been seen
            if (col >= 2 && row >= 2) begin
                win_valid <= 1'b1;
                win_x     <= col - 1'b1;
                win_y     <= row[YW-1:0] - 1'b1;
            end

            if (col == WIDTH - 1) begin
                col <= 0;
                row <= row + 1'b1;
            end else begin
                col <= col + 1'b1;
            end
        end
    end

    // ---- stage 2: arithmetic on the (stable) window ----
    wire signed [11:0] gx = $signed({4'b0, top2}) + 2 * $signed({4'b0, mid2}) + $signed({4'b0, bot2})
                          - $signed({4'b0, top0}) - 2 * $signed({4'b0, mid0}) - $signed({4'b0, bot0});
    wire signed [11:0] gy = $signed({4'b0, bot0}) + 2 * $signed({4'b0, bot1}) + $signed({4'b0, bot2})
                          - $signed({4'b0, top0}) - 2 * $signed({4'b0, top1}) - $signed({4'b0, top2});
    wire [11:0] ax = gx[11] ? -gx : gx;
    wire [11:0] ay = gy[11] ? -gy : gy;
    wire [12:0] sum = {1'b0, ax} + {1'b0, ay};

    always @(posedge clk) begin
        out_valid <= win_valid;
        out_x     <= win_x;
        out_y     <= win_y;
        out_mag   <= (sum > 13'd255) ? 8'd255 : sum[7:0];
    end

endmodule
