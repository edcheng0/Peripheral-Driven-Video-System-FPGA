`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// display_filter.v - picks what the screen shows, on the way out to HDMI.
//   mode 0 = raw color          1 = grayscale
//   mode 2 = Sobel edges        3 = inverted color
//
// The video that comes in is already shaped like a monitor signal (hsync,
// vsync, data-enable, 24-bit color). Gray and invert are simple per-pixel
// maths. Sobel needs the rows above and below a pixel, so its answer for
// pixel (x, y) is ready one line plus a few clocks later. Rather than
// shifting the picture, everything else (the sync signals and the colour
// of the other modes) is held back by exactly that time, so every mode
// lines up with the same output timing.
// ----------------------------------------------------------------------
module display_filter #(
    parameter WIDTH = 640,
    parameter XW    = 10,
    parameter YW    = 9,
    parameter DELAY = 802        // clocks: 1 line (H_TOTAL) + 1 pixel + 1
) (
    input  wire        clk,
    input  wire [1:0]  mode,     // already in the clk domain
    input  wire        hs_in, vs_in, de_in,
    input  wire [7:0]  r_in, g_in, b_in,
    output reg         hs_out, vs_out, de_out,
    output reg  [7:0]  r_out, g_out, b_out
);
    // ---- per-pixel colour maths ----
    wire [15:0] sum = 16'd77 * r_in + 16'd150 * g_in + 16'd29 * b_in;
    wire [7:0]  gray = sum[15:8];

    reg [23:0] px;
    always @(*) begin
        case (mode)
            2'd1:    px = {gray, gray, gray};
            2'd3:    px = ~{r_in, g_in, b_in};
            default: px = {r_in, g_in, b_in};
        endcase
    end

    // ---- Sobel on the gray value, only pixels inside the picture ----
    wire        sob_valid;
    wire [XW-1:0] sob_x;
    wire [YW-1:0] sob_y;
    wire [7:0]  sob_mag;
    sobel_3x3 #(.WIDTH(WIDTH), .XW(XW), .YW(YW)) u_sobel (
        .clk(clk), .sof(vs_in), .in_valid(de_in), .in_pixel(gray),
        .out_valid(sob_valid), .out_x(sob_x), .out_y(sob_y), .out_mag(sob_mag)
    );

    // ---- hold sync + colour back by DELAY clocks ----
    reg [26:0] mem [0:DELAY-1];
    integer wp = 0;
    reg [26:0] dly = 27'd0;
    always @(posedge clk) begin
        dly     <= mem[wp];
        mem[wp] <= {hs_in, vs_in, de_in, px};
        wp      <= (wp == DELAY-1) ? 0 : wp + 1;
    end

    always @(posedge clk) begin
        hs_out <= dly[26];
        vs_out <= dly[25];
        de_out <= dly[24];
        if (mode == 2'd2) begin
            r_out <= sob_valid ? sob_mag : 8'd0;
            g_out <= sob_valid ? sob_mag : 8'd0;
            b_out <= sob_valid ? sob_mag : 8'd0;
        end else begin
            {r_out, g_out, b_out} <= dly[23:0];
        end
    end
endmodule
