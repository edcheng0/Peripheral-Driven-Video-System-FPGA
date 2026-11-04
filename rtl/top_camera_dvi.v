`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// top_camera_dvi.v - OV7670 camera -> (filter) -> HDMI, 640x480 output.
//
//   sysclk 125 MHz --> video_clocks --> clk_pixel 25.25 MHz, clk_serial 126.25 MHz
//   clk_pixel ------> ODDR (clock_forward) --> cam_xclk (camera's input clock)
//   ov7670_init + i2c_master (sysclk) --SCCB--> camera config (QVGA RGB565)
//   camera --> cam_to_display (capture, filters, frame buffer, 2x upscale)
//   video_timing_gen --> cam_to_display --> tmds_tx_lanes --> HDMI TX pins
//
// Switches SW1:SW0 choose the filter: 00 raw, 01 gray, 10 Sobel edges, 11 invert.
// LEDs:  LD0 MMCM locked    LD1 camera config sent
//        LD2 toggles every camera frame (camera alive)
//        LD3 toggles every displayed frame (HDMI timing alive)
//
// STATUS: simulated in pieces and built, never run on hardware (the camera
// and the Zybo are not here yet). The camera wiring is a draft, see
// constraints/zybo_camera_pmod.xdc.
// ----------------------------------------------------------------------
module top_camera_dvi #(
    parameter TEST_BARS = 0     // 1 = ask the camera for its built-in color bars
) (
    input  wire       sysclk,
    input  wire [3:0] sw,
    output wire [3:0] led,

    // HDMI TX
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n,

    // OV7670
    input  wire [7:0] cam_d,
    input  wire       cam_pclk,
    input  wire       cam_vsync,
    input  wire       cam_href,
    output wire       cam_xclk,
    output wire       cam_reset_n,
    output wire       cam_pwdn,
    output wire       cam_sioc,
    inout  wire       cam_siod
);

    // ---- clocks ----
    wire clk_pixel, clk_serial, locked;
    video_clocks u_clocks (
        .clk_in(sysclk), .rst(1'b0),
        .clk_pixel(clk_pixel), .clk_serial(clk_serial), .locked(locked)
    );

    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync = 2'b11;
    always @(posedge clk_pixel or negedge locked) begin
        if (!locked) rst_sync <= 2'b11;
        else         rst_sync <= {rst_sync[0], 1'b0};
    end
    wire rst_pix = rst_sync[1];

    // ---- camera clock out + static control pins ----
    clock_forward u_xclk (.clk(clk_pixel), .clk_out(cam_xclk));
    assign cam_pwdn = 1'b0;                 // 0 = normal operation

    // ---- SCCB config, sysclk domain; starts once the MMCM (hence XCLK) is stable ----
    (* ASYNC_REG = "TRUE" *) reg [1:0] lock_s = 2'b00;
    always @(posedge sysclk) lock_s <= {lock_s[0], locked};
    reg lock_d = 1'b0;
    always @(posedge sysclk) lock_d <= lock_s[1];
    wire rst_sys = ~lock_s[1];
    wire go      = lock_s[1] & ~lock_d;     // one pulse when lock arrives

    assign cam_reset_n = lock_s[1];         // hold the camera in reset until XCLK runs

    wire        i2c_start, i2c_busy, i2c_done, i2c_ack_error, init_done;
    wire [6:0]  i2c_dev;
    wire [7:0]  i2c_reg, i2c_val;
    ov7670_init #(.DELAY_CYCLES(1_250_000), .TEST_BARS(TEST_BARS)) u_init (
        .clk(sysclk), .rst(rst_sys), .go(go), .init_done(init_done),
        .i2c_start(i2c_start), .i2c_dev_addr(i2c_dev), .i2c_reg_addr(i2c_reg),
        .i2c_reg_data(i2c_val), .i2c_busy(i2c_busy), .i2c_done(i2c_done)
    );
    i2c_master #(.CLK_FREQ_HZ(125_000_000), .I2C_FREQ_HZ(100_000)) u_sccb (
        .clk(sysclk), .rst(rst_sys), .start(i2c_start), .dev_addr(i2c_dev),
        .reg_addr(i2c_reg), .reg_data(i2c_val), .busy(i2c_busy), .done(i2c_done),
        .ack_error(i2c_ack_error), .scl(cam_sioc), .sda(cam_siod)
    );

    // ---- display timing: 640x480@60 ----
    wire hsync, vsync, de;
    wire [9:0] pixel_x, pixel_y;
    video_timing_gen u_timing (
        .clk_pixel(clk_pixel), .rst(rst_pix),
        .hsync(hsync), .vsync(vsync), .data_enable(de),
        .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

    // ---- camera -> display ----
    wire hs_o, vs_o, de_o;
    wire [7:0] red, green, blue;
    cam_to_display #(.SRC_W(320), .SRC_H(240), .XW(9), .YW(8), .SHIFT(1), .CNT_W(10)) u_c2d (
        .cam_pclk(cam_pclk), .cam_vsync(cam_vsync), .cam_href(cam_href), .cam_d(cam_d),
        .mode(sw[1:0]),
        .clk_pixel(clk_pixel), .hsync_in(hsync), .vsync_in(vsync), .de_in(de),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .hsync_out(hs_o), .vsync_out(vs_o), .de_out(de_o),
        .red(red), .green(green), .blue(blue)
    );

    // ---- HDMI out ----
    tmds_tx_lanes #(.SYNC_ACTIVE_LOW(1)) u_tx (
        .clk_pixel(clk_pixel), .clk_serial(clk_serial), .rst(rst_pix),
        .red(red), .green(green), .blue(blue),
        .hsync(hs_o), .vsync(vs_o), .de(de_o),
        .tmds_clk_p(hdmi_tx_clk_p), .tmds_clk_n(hdmi_tx_clk_n),
        .tmds_d_p(hdmi_tx_p), .tmds_d_n(hdmi_tx_n)
    );

    // ---- status LEDs ----
    reg cam_frame_led = 1'b0, vs_c_d = 1'b0;
    always @(posedge cam_pclk) begin
        vs_c_d <= cam_vsync;
        if (cam_vsync && !vs_c_d) cam_frame_led <= ~cam_frame_led;
    end
    reg disp_frame_led = 1'b0, vs_p_d = 1'b0;
    always @(posedge clk_pixel) begin
        vs_p_d <= vsync;
        if (vsync && !vs_p_d) disp_frame_led <= ~disp_frame_led;
    end
    assign led = {disp_frame_led, cam_frame_led, init_done, locked};

endmodule
