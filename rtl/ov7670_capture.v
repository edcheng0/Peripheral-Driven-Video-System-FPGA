`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// ov7670_capture.v - turns the OV7670's parallel pixel stream into pixels.
//
// How the camera talks (all signals are clocked by the camera's own PCLK):
//   VSYNC : high during the gap between frames (default polarity)
//   HREF  : high while a line of pixels is being sent
//   D[7:0]: one BYTE per PCLK. In RGB565 mode a pixel is TWO bytes:
//             first byte  = R4 R3 R2 R1 R0 G5 G4 G3
//             second byte = G2 G1 G0 B4 B3 B2 B1 B0
//           so we glue them into one 16-bit value.
//
// Output: a stream of "pixel valid" strobes with the pixel's x/y position
// in the frame, all in the PCLK domain. Position counters are re-synced at
// every line start (HREF rising) and frame start (VSYNC rising), so one
// glitchy line cannot shift the rest of the picture.
// Pixels outside WIDTH x HEIGHT are dropped.
//
// frame_start pulses once when VSYNC rises (start of the blanking gap);
// downstream filters use it to reset their line counters.
// ----------------------------------------------------------------------
module ov7670_capture #(
    parameter WIDTH  = 320,
    parameter HEIGHT = 240,
    parameter XW     = 9,      // bits for x (must be able to hold the value WIDTH)
    parameter YW     = 8       // bits for y (must hold HEIGHT-1)
) (
    input  wire          pclk,
    input  wire          vsync,
    input  wire          href,
    input  wire [7:0]    d,

    output reg           pix_valid,   // 1 pclk pulse per complete pixel
    output reg  [XW-1:0] pix_x,
    output reg  [YW-1:0] pix_y,
    output reg  [15:0]   pix_data,    // RGB565
    output reg           frame_start  // 1 pclk pulse at VSYNC rising
);

    reg vsync_d = 1'b0, href_d = 1'b0;
    reg        have_hi = 1'b0;       // 1 = we already hold the first byte of a pixel
    reg [7:0]  hi_byte = 8'd0;
    reg [XW-1:0] x_cnt = 0;
    reg [YW:0]   y_cnt = 0;          // one extra bit so "past the last line" is representable
    reg          seen_line = 1'b0;   // at least one line since frame start

    always @(posedge pclk) begin
        vsync_d     <= vsync;
        href_d      <= href;
        pix_valid   <= 1'b0;
        frame_start <= 1'b0;

        if (vsync && !vsync_d) begin
            frame_start <= 1'b1;
            y_cnt       <= 0;
            seen_line   <= 1'b0;
            have_hi     <= 1'b0;
            x_cnt       <= 0;
        end else begin
            // new line: the first line after frame start is y=0, then 1, 2, ...
            if (href && !href_d) begin
                x_cnt   <= 0;
                have_hi <= 1'b0;
                if (seen_line) y_cnt <= y_cnt + 1'b1;
                seen_line <= 1'b1;
            end

            if (href && !vsync) begin
                if (!have_hi) begin
                    hi_byte <= d;
                    have_hi <= 1'b1;
                end else begin
                    have_hi <= 1'b0;
                    if (x_cnt < WIDTH && y_cnt < HEIGHT) begin
                        pix_valid <= 1'b1;
                        pix_x     <= x_cnt;
                        pix_y     <= y_cnt[YW-1:0];
                        pix_data  <= {hi_byte, d};
                    end
                    if (x_cnt != WIDTH) x_cnt <= x_cnt + 1'b1;   // saturate: extra pixels dropped
                end
            end else begin
                have_hi <= 1'b0;
            end
        end
    end

endmodule
