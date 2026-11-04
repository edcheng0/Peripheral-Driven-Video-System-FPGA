`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// top_phase1_dvi.v - 640x480 color bars out of the Zybo Z7-20 HDMI TX port.
//
// The Zybo's HDMI TX connector is wired straight to FPGA pins (no HDMI
// chip in between), so the FPGA itself makes the HDMI signal. HDMI video
// (called TMDS) is 4 differential pairs: three carry color data, one
// carries a clock.
//
//   125 MHz board clock -> video_clocks -> pixel clock (25.25 MHz)
//                                       -> serial clock (5x pixel)
//   video_timing_gen -> where are we on screen? (x, y, sync, visible?)
//   colorbar_gen     -> what color is this pixel?
//   3x tmds_encoder  -> turn each 8-bit color into a 10-bit TMDS word
//                       (blue's encoder also carries hsync/vsync)
//   4x tmds_serializer -> shift the words out, one bit at a time
//
// Lane naming follows the usual DVI convention:
//   hdmi_tx_*[0] = blue (+ hsync/vsync)   [1] = green   [2] = red
//   hdmi_tx_clk  = clock lane; it always sends 10'b0000011111, which looks
//                  like a clock at the pixel rate.
// ----------------------------------------------------------------------
module top_phase1_dvi #(
    // Defaults = 640x480@60 (active-low sync, 25.25 MHz pixel clock).
    // top_dvi_svga.v and top_dvi_720p.v pass other numbers.
    parameter       CNT_W            = 10,
    parameter       H_VISIBLE        = 640,
    parameter       H_FRONT_PORCH    = 16,
    parameter       H_SYNC_PULSE     = 96,
    parameter       H_BACK_PORCH     = 48,
    parameter       V_VISIBLE        = 480,
    parameter       V_FRONT_PORCH    = 10,
    parameter       V_SYNC_PULSE     = 2,
    parameter       V_BACK_PORCH     = 33,
    parameter       SYNC_ACTIVE_LOW  = 1,      // 1 = negative-polarity sync pulses
    parameter       DIVCLK_DIVIDE    = 5,      // MMCM settings, see video_clocks.v
    parameter real  CLKFBOUT_MULT_F  = 25.25,
    parameter real  SERIAL_DIVIDE_F  = 5.0,
    parameter       PIXEL_DIVIDE     = 25
) (
    input  wire       sysclk,          // 125 MHz board clock (K17)

    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n
);

    // ---- pixel + serial clocks ----
    wire clk_pixel, clk_serial, locked;
    video_clocks #(
        .DIVCLK_DIVIDE   (DIVCLK_DIVIDE),
        .CLKFBOUT_MULT_F (CLKFBOUT_MULT_F),
        .SERIAL_DIVIDE_F (SERIAL_DIVIDE_F),
        .PIXEL_DIVIDE    (PIXEL_DIVIDE)
    ) u_clocks (
        .clk_in     (sysclk),
        .rst        (1'b0),
        .clk_pixel  (clk_pixel),
        .clk_serial (clk_serial),
        .locked     (locked)
    );

    // ---- reset: held high until the MMCM locks, released in step with
    // the pixel clock (2-flop synchronizer, starts asserted) ----
    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync = 2'b11;
    always @(posedge clk_pixel or negedge locked) begin
        if (!locked) rst_sync <= 2'b11;
        else         rst_sync <= {rst_sync[0], 1'b0};
    end
    wire rst_pix = rst_sync[1];

    // ---- picture ----
    wire        hsync, vsync, de;
    wire [CNT_W-1:0] pixel_x, pixel_y;
    video_timing_gen #(
        .CNT_W(CNT_W),
        .H_VISIBLE(H_VISIBLE), .H_FRONT_PORCH(H_FRONT_PORCH),
        .H_SYNC_PULSE(H_SYNC_PULSE), .H_BACK_PORCH(H_BACK_PORCH),
        .V_VISIBLE(V_VISIBLE), .V_FRONT_PORCH(V_FRONT_PORCH),
        .V_SYNC_PULSE(V_SYNC_PULSE), .V_BACK_PORCH(V_BACK_PORCH)
    ) u_timing (
        .clk_pixel   (clk_pixel),
        .rst         (rst_pix),
        .hsync       (hsync),
        .vsync       (vsync),
        .data_enable (de),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y)
    );

    wire [7:0] red, green, blue;
    colorbar_gen #(.CNT_W(CNT_W), .BAR_WIDTH(H_VISIBLE / 8)) u_bars (
        .pixel_x (pixel_x),
        .red     (red),
        .green   (green),
        .blue    (blue)
    );

    // ---- TMDS encode + serialize + drive the HDMI TX pins ----
    // video_timing_gen makes active-high sync pulses. SYNC_ACTIVE_LOW=1 (640x480)
    // inverts them here; 800x600 and 720p use positive sync and pass them as-is.
    tmds_tx_lanes #(.SYNC_ACTIVE_LOW(SYNC_ACTIVE_LOW)) u_tx (
        .clk_pixel (clk_pixel), .clk_serial (clk_serial), .rst (rst_pix),
        .red (red), .green (green), .blue (blue),
        .hsync (hsync), .vsync (vsync), .de (de),
        .tmds_clk_p (hdmi_tx_clk_p), .tmds_clk_n (hdmi_tx_clk_n),
        .tmds_d_p (hdmi_tx_p), .tmds_d_n (hdmi_tx_n)
    );

endmodule
