`timescale 1ns / 1ps
//------------------------------------------------------------------------
// video_timing_gen.v
//
// Generates standard 640x480 @ 60Hz video timing (also called "VGA
// timing" - the same numbers are reused by HDMI for this resolution).
// This module doesn't know or care about HDMI, VGA connectors, or your
// specific board - it just counts pixels and lines, and tells you:
//   - are we currently inside the visible picture area? (data_enable)
//   - where is the current pixel, in x/y coordinates?
//   - when should the horizontal/vertical sync pulses fire?
//
// Feed it a 25.175 MHz pixel clock (approximated here as 25 MHz, which
// works fine for most displays) and it does the rest.
//
// KEY CONCEPT: A display doesn't just receive pixels - between visible
// lines/frames there are deliberate "blanking" gaps (left over from
// old CRT monitors physically re-aiming an electron beam). Every
// digital display standard still includes these gaps because the
// timing became the universal standard. The numbers below (16, 96,
// 48, etc.) are the official standard blanking widths for 640x480 -
// they are not arbitrary and should not be changed.
//------------------------------------------------------------------------
module video_timing_gen #(
    // Defaults = 640x480@60. Other modes just pass different numbers.
    parameter CNT_W          = 10,   // counter/coordinate width in bits
    parameter H_VISIBLE      = 640,
    parameter H_FRONT_PORCH  = 16,
    parameter H_SYNC_PULSE   = 96,
    parameter H_BACK_PORCH   = 48,
    parameter V_VISIBLE      = 480,
    parameter V_FRONT_PORCH  = 10,
    parameter V_SYNC_PULSE   = 2,
    parameter V_BACK_PORCH   = 33
) (
    input  wire clk_pixel,       // 25 MHz pixel clock
    input  wire rst,

    output wire hsync,           // horizontal sync pulse (active high here)
    output wire vsync,           // vertical sync pulse (active high here)
    output wire data_enable,     // high = current pixel is in the visible area
    output wire [CNT_W-1:0] pixel_x,   // 0 - 639 during visible area
    output wire [CNT_W-1:0] pixel_y    // 0 - 479 during visible area
);

    // ---- Horizontal timing (in pixel clocks) ----
    localparam H_TOTAL = H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    // ---- Vertical timing (in lines) ----
    localparam V_TOTAL = V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

    reg [CNT_W-1:0] h_count = 0;  // counts 0..799, one tick per pixel clock
    reg [CNT_W-1:0] v_count = 0;  // counts 0..524, one tick per finished line

    // Horizontal counter: advances every pixel clock, wraps at H_TOTAL
    always @(posedge clk_pixel) begin
        if (rst) begin
            h_count <= 0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 0;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end

    // Vertical counter: advances once per finished horizontal line
    always @(posedge clk_pixel) begin
        if (rst) begin
            v_count <= 0;
        end else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1)
                v_count <= 0;
            else
                v_count <= v_count + 1'b1;
        end
    end

    // Sync pulses: active during a specific window of each counter
    assign hsync = (h_count >= (H_VISIBLE + H_FRONT_PORCH)) &&
                   (h_count <  (H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE));

    assign vsync = (v_count >= (V_VISIBLE + V_FRONT_PORCH)) &&
                   (v_count <  (V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE));

    // Data enable: high only while we're inside the visible picture
    assign data_enable = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

    // Pixel coordinates - only meaningful while data_enable is high
    assign pixel_x = h_count;
    assign pixel_y = v_count;

endmodule
